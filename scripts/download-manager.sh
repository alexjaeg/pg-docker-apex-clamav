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

APEX_URL="${APEX_DOWNLOAD_URL:-https://download.oracle.com/otn_software/apex/apex_24.2.zip}"
SQUIDCLAMAV_URL="${SQUIDCLAMAV_URL:-https://github.com/darold/squidclamav/archive/refs/tags/v7.3.tar.gz}"

echo "================================================================="
echo "[DOWNLOAD-MGR] Starting Download Manager & Certificate Setup..."
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
# 2. Build shared CA trust bundle for Oracle Database 23ai
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
# 3. Generate Download Manifest (downloads.txt) in dl/
# ------------------------------------------------------------------------------
MANIFEST_FILE="${DOWNLOAD_DIR}/downloads.txt"

check_status() {
    if [ -f "$1" ]; then
        echo "PRESENT ($(du -h "$1" | cut -f1))"
    else
        echo "MISSING (Will be auto-downloaded or can be manually added)"
    fi
}

cat << EOF > "${MANIFEST_FILE}"
# ==============================================================================
# Oracle APEX + ClamAV Stack - Download Manifest & Sources
# ==============================================================================
# In Zero-Trust / Airgapped / Offline networks, manually download these files
# and place them directly into this 'dl/' directory.
# ==============================================================================

[APEX_DISTRIBUTION]
FILE: apex_24.2.zip
STATUS: $(check_status "${DOWNLOAD_DIR}/apex_24.2.zip")
PURPOSE: Oracle APEX 24.2 Full Release (Database Application Express & Static Images)
URL: ${APEX_URL}
MANUAL_COMMAND_POWERSHELL: Invoke-WebRequest -Uri "${APEX_URL}" -OutFile "dl\\apex_24.2.zip"
MANUAL_COMMAND_CURL: curl -fsSL -o dl/apex_24.2.zip ${APEX_URL}

[SQUIDCLAMAV_SOURCE]
FILE: squidclamav-7.3.tar.gz
STATUS: $(check_status "${DOWNLOAD_DIR}/squidclamav-7.3.tar.gz")
PURPOSE: SquidClamAV 7.3 Source Code (C-ICAP Antivirus & TCP Streaming Module)
URL: ${SQUIDCLAMAV_URL}
MANUAL_COMMAND_POWERSHELL: Invoke-WebRequest -Uri "${SQUIDCLAMAV_URL}" -OutFile "dl\\squidclamav-7.3.tar.gz"
MANUAL_COMMAND_CURL: curl -fsSL -o dl/squidclamav-7.3.tar.gz ${SQUIDCLAMAV_URL}
EOF

# ------------------------------------------------------------------------------
# 4. Handle SquidClamAV archive
# ------------------------------------------------------------------------------
SQUIDCLAMAV_FILE="${DOWNLOAD_DIR}/squidclamav-7.3.tar.gz"
if [ -f "${SQUIDCLAMAV_FILE}" ]; then
    echo "[DOWNLOAD-MGR] Found SquidClamAV archive: ${SQUIDCLAMAV_FILE} (Manual/Pre-downloaded)."
else
    echo "[DOWNLOAD-MGR] Downloading SquidClamAV 7.3 from ${SQUIDCLAMAV_URL}..."
    curl -L --fail --show-error --progress-bar -o "${SQUIDCLAMAV_FILE}" "${SQUIDCLAMAV_URL}"
    echo "[DOWNLOAD-MGR] SquidClamAV download completed."
fi

# ------------------------------------------------------------------------------
# 5. Handle Oracle APEX 24.2 archive
# ------------------------------------------------------------------------------
APEX_ZIP="${DOWNLOAD_DIR}/apex_24.2.zip"
if [ -f "${APEX_ZIP}" ]; then
    echo "[DOWNLOAD-MGR] Found APEX archive: ${APEX_ZIP} (Manual/Pre-downloaded)."
else
    echo "[DOWNLOAD-MGR] APEX archive missing in ${DOWNLOAD_DIR}. Downloading from ${APEX_URL}..."
    curl -L --fail --show-error --progress-bar -o "${APEX_ZIP}" "${APEX_URL}"
    echo "[DOWNLOAD-MGR] APEX download completed."
fi

# Update manifest with new PRESENT status after download
cat << EOF > "${MANIFEST_FILE}"
# ==============================================================================
# Oracle APEX + ClamAV Stack - Download Manifest & Sources
# ==============================================================================
# In Zero-Trust / Airgapped / Offline networks, manually download these files
# and place them directly into this 'dl/' directory.
# ==============================================================================

[APEX_DISTRIBUTION]
FILE: apex_24.2.zip
STATUS: $(check_status "${DOWNLOAD_DIR}/apex_24.2.zip")
PURPOSE: Oracle APEX 24.2 Full Release (Database Application Express & Static Images)
URL: ${APEX_URL}
MANUAL_COMMAND_POWERSHELL: Invoke-WebRequest -Uri "${APEX_URL}" -OutFile "dl\\apex_24.2.zip"
MANUAL_COMMAND_CURL: curl -fsSL -o dl/apex_24.2.zip ${APEX_URL}

[SQUIDCLAMAV_SOURCE]
FILE: squidclamav-7.3.tar.gz
STATUS: $(check_status "${DOWNLOAD_DIR}/squidclamav-7.3.tar.gz")
PURPOSE: SquidClamAV 7.3 Source Code (C-ICAP Antivirus & TCP Streaming Module)
URL: ${SQUIDCLAMAV_URL}
MANUAL_COMMAND_POWERSHELL: Invoke-WebRequest -Uri "${SQUIDCLAMAV_URL}" -OutFile "dl\\squidclamav-7.3.tar.gz"
MANUAL_COMMAND_CURL: curl -fsSL -o dl/squidclamav-7.3.tar.gz ${SQUIDCLAMAV_URL}
EOF

# ------------------------------------------------------------------------------
# 6. Extract APEX into shared volume if needed
# ------------------------------------------------------------------------------
if [ -f "${APEX_TARGET_DIR}/apxsilentins.sql" ] && [ -d "${APEX_TARGET_DIR}/images" ]; then
    echo "[DOWNLOAD-MGR] APEX files already extracted in ${APEX_TARGET_DIR}. Skipping extraction."
else
    echo "[DOWNLOAD-MGR] Extracting ${APEX_ZIP} into ${APEX_TARGET_DIR}..."
    TEMP_EXTRACT="/tmp/apex_extract"
    rm -rf "${TEMP_EXTRACT}"
    mkdir -p "${TEMP_EXTRACT}"
    unzip -q "${APEX_ZIP}" -d "${TEMP_EXTRACT}"

    if [ ! -f "${TEMP_EXTRACT}/apex/apxsilentins.sql" ]; then
        echo "[DOWNLOAD-MGR] ERROR: apxsilentins.sql not found in downloaded archive!"
        exit 1
    fi

    echo "[DOWNLOAD-MGR] Moving extracted files to ${APEX_TARGET_DIR}..."
    cp -r "${TEMP_EXTRACT}/apex"/* "${APEX_TARGET_DIR}/"
    chmod -R 755 "${APEX_TARGET_DIR}"
    rm -rf "${TEMP_EXTRACT}"
    echo "[DOWNLOAD-MGR] APEX extraction complete."
fi

echo "================================================================="
echo "[DOWNLOAD-MGR] All downloads and certificates prepared successfully."
echo "================================================================="
