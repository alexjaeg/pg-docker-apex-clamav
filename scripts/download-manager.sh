#!/bin/bash
set -euo pipefail

# ==============================================================================
# Central Download Manager & Certificate Trust Builder
# Manages host ./dl folder, auto-downloads missing files, respects manual placement,
# sanitizes certificates, and generates download manifest.
# ==============================================================================

DOWNLOAD_DIR="/downloads"
APEX_TARGET_DIR="${APEX_TARGET_DIR:-/apex-files}"
CERT_DIR="/cert"
CA_BUNDLE_DIR="/ca-trust-bundle"

APEX_VER="${APEX_VERSION:-26.1}"
APEX_URL="${APEX_DOWNLOAD_URL:-https://download.oracle.com/otn_software/apex/apex_${APEX_VER}.zip}"
APEX_FILE="apex_${APEX_VER}.zip"

echo "================================================================="
echo "[DOWNLOAD-MGR] Starting Download Manager & Certificate Setup..."
echo "[DOWNLOAD-MGR] Configured APEX Version: ${APEX_VER} (${APEX_FILE})"
echo "================================================================="

mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${APEX_TARGET_DIR}"
mkdir -p "${CA_BUNDLE_DIR}"

# Helper function to sanitize certificates (handles Windows UTF-16, CRLF, missing trailing newlines)
sanitize_cert() {
    local src="$1"
    local dst="$2"
    if head -c 2 "$src" | grep -q $'\xff\xfe' || head -c 2 "$src" | grep -q $'\xfe\xff'; then
        iconv -f UTF-16 -t UTF-8 "$src" 2>/dev/null | tr -d '\r' > "$dst" || tr -d '\r\0\xff\xfe' < "$src" > "$dst"
    else
        tr -d '\r' < "$src" > "$dst"
    fi
    # Guarantee newline at end of certificate
    echo "" >> "$dst"
}

# ------------------------------------------------------------------------------
# 1. Import custom certificates into downloader system trust store
# ------------------------------------------------------------------------------
if [ -d "$CERT_DIR" ]; then
    count=0
    for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
        if [ -f "$cert" ]; then
            count=$((count + 1))
        fi
    done

    if [ "$count" -gt 0 ]; then
        echo "[DOWNLOAD-MGR] Found $count custom certificate(s) in $CERT_DIR. Importing..."
        mkdir -p /usr/local/share/ca-certificates/custom
        for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
            if [ -f "$cert" ]; then
                base=$(basename "$cert")
                sanitize_cert "$cert" "/usr/local/share/ca-certificates/custom/${base}.crt"
            fi
        done
        update-ca-certificates >/dev/null 2>&1 || true
        echo "[DOWNLOAD-MGR] Downloader system CA trust store updated."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Build shared CA trust bundle for Oracle Database
# ------------------------------------------------------------------------------
echo "[DOWNLOAD-MGR] Generating shared CA trust bundle for Oracle Database..."
cp /etc/ssl/certs/ca-certificates.crt "$CA_BUNDLE_DIR/tls-ca-bundle.pem"
echo "" >> "$CA_BUNDLE_DIR/tls-ca-bundle.pem"

if [ -d "$CERT_DIR" ]; then
    for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
        if [ -f "$cert" ]; then
            base=$(basename "$cert")
            echo "[DOWNLOAD-MGR] Injecting $base into shared DB CA bundle..."
            TMP_SAN="/tmp/sanitized_${base}"
            sanitize_cert "$cert" "$TMP_SAN"
            cat "$TMP_SAN" >> "$CA_BUNDLE_DIR/tls-ca-bundle.pem"
            rm -f "$TMP_SAN"
        fi
    done
fi
chmod 777 "$CA_BUNDLE_DIR"
chmod 666 "$CA_BUNDLE_DIR/tls-ca-bundle.pem"
echo "[DOWNLOAD-MGR] Shared DB CA bundle ready."

# ------------------------------------------------------------------------------
# 3. Helper to check file status
# ------------------------------------------------------------------------------
check_status() {
    if [ -f "$1" ]; then
        echo "PRESENT ($(du -h "$1" | cut -f1))"
    else
        echo "MISSING (Will be auto-downloaded or can be manually added)"
    fi
}

write_manifest() {
    cat << EOF > "${DOWNLOAD_DIR}/downloads.txt"
# ==============================================================================
# Oracle APEX + ClamAV Stack - Download Manifest & Sources
# ==============================================================================
# In Zero-Trust / Airgapped / Offline networks, manually download these files
# and place them directly into this 'dl/' directory.
# ==============================================================================

[APEX_DISTRIBUTION]
FILE: ${APEX_FILE}
STATUS: $(check_status "${DOWNLOAD_DIR}/${APEX_FILE}")
PURPOSE: Oracle APEX ${APEX_VER} Full Release (Database Application Express & Static Images)
URL: ${APEX_URL}
MANUAL_COMMAND_POWERSHELL: Invoke-WebRequest -Uri "${APEX_URL}" -OutFile "dl\\${APEX_FILE}"
MANUAL_COMMAND_CURL: curl -fsSL -o dl/${APEX_FILE} ${APEX_URL}
EOF
}

# Write initial manifest
write_manifest

# ------------------------------------------------------------------------------
# 4. Handle Oracle APEX archive
# ------------------------------------------------------------------------------
APEX_ZIP_PATH="${DOWNLOAD_DIR}/${APEX_FILE}"
if [ -f "${APEX_ZIP_PATH}" ]; then
    echo "[DOWNLOAD-MGR] Found APEX archive: ${APEX_ZIP_PATH} (Manual/Pre-downloaded)."
else
    echo "[DOWNLOAD-MGR] APEX archive missing in ${DOWNLOAD_DIR}. Downloading from ${APEX_URL}..."
    curl -L --fail --show-error --progress-bar -o "${APEX_ZIP_PATH}" "${APEX_URL}"
    echo "[DOWNLOAD-MGR] APEX download completed."
fi

# Update manifest with final status
write_manifest

# ------------------------------------------------------------------------------
# 5. Extract APEX into shared volume if needed
# ------------------------------------------------------------------------------
VERSION_MARKER="${APEX_TARGET_DIR}/.apex_version_${APEX_VER}"
if [ -f "${APEX_TARGET_DIR}/apxsilentins.sql" ] && [ -d "${APEX_TARGET_DIR}/images" ] && [ -f "${VERSION_MARKER}" ]; then
    echo "[DOWNLOAD-MGR] APEX ${APEX_VER} files already extracted in ${APEX_TARGET_DIR}. Skipping extraction."
else
    echo "[DOWNLOAD-MGR] Extracting ${APEX_ZIP_PATH} into ${APEX_TARGET_DIR}..."
    TEMP_EXTRACT="/tmp/apex_extract"
    rm -rf "${TEMP_EXTRACT}"
    mkdir -p "${TEMP_EXTRACT}"
    unzip -q "${APEX_ZIP_PATH}" -d "${TEMP_EXTRACT}"

    if [ ! -f "${TEMP_EXTRACT}/apex/apxsilentins.sql" ]; then
        echo "[DOWNLOAD-MGR] ERROR: apxsilentins.sql not found in downloaded archive!"
        exit 1
    fi

    echo "[DOWNLOAD-MGR] Moving extracted files to ${APEX_TARGET_DIR}..."
    rm -f "${APEX_TARGET_DIR}/.apex_version_"* 2>/dev/null || true
    cp -r "${TEMP_EXTRACT}/apex"/* "${APEX_TARGET_DIR}/"
    touch "${VERSION_MARKER}"
    chmod -R 755 "${APEX_TARGET_DIR}"
    rm -rf "${TEMP_EXTRACT}"
    echo "[DOWNLOAD-MGR] APEX ${APEX_VER} extraction complete."
fi

echo "================================================================="
echo "[DOWNLOAD-MGR] All downloads and certificates prepared successfully."
echo "================================================================="
