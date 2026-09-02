#!/bin/bash
set -euo pipefail

# ==============================================================================
# APEX Downloader & Shared CA Trust Bundle Initializer
# ==============================================================================

APEX_TARGET_DIR="${APEX_TARGET_DIR:-/apex-files}"
APEX_DOWNLOAD_URL="${APEX_DOWNLOAD_URL:-https://download.oracle.com/otn_software/apex/apex_24.2.zip}"
CERT_DIR="/cert"
CA_BUNDLE_DIR="/ca-trust-bundle"

echo "================================================================="
echo "[APEX-DOWNLOAD] Checking certificates & APEX installation..."
echo "================================================================="

# 1. Import custom certificates into downloader system trust store
if [ -d "$CERT_DIR" ]; then
    count=0
    for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
        if [ -f "$cert" ]; then
            count=$((count + 1))
        fi
    done

    if [ "$count" -gt 0 ]; then
        echo "[APEX-DOWNLOAD] Found $count custom certificate(s) in $CERT_DIR. Importing..."
        mkdir -p /usr/local/share/ca-certificates/custom
        for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
            if [ -f "$cert" ]; then
                cp "$cert" /usr/local/share/ca-certificates/custom/
            fi
        done
        update-ca-certificates >/dev/null 2>&1 || true
        echo "[APEX-DOWNLOAD] System CA trust store updated."
    fi
fi

# 2. Build shared CA trust bundle for Oracle Database 23ai
mkdir -p "$CA_BUNDLE_DIR"
cp /etc/ssl/certs/ca-certificates.crt "$CA_BUNDLE_DIR/tls-ca-bundle.pem"

if [ -d "$CERT_DIR" ]; then
    for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
        if [ -f "$cert" ]; then
            base=$(basename "$cert")
            echo "[APEX-DOWNLOAD] Injecting $base into shared DB CA bundle..."
            cat "$cert" >> "$CA_BUNDLE_DIR/tls-ca-bundle.pem"
        fi
    done
fi
chmod 777 "$CA_BUNDLE_DIR"
chmod 666 "$CA_BUNDLE_DIR/tls-ca-bundle.pem"
echo "[APEX-DOWNLOAD] Shared DB CA bundle ready."

# 3. Download APEX if not already present
mkdir -p "${APEX_TARGET_DIR}"

if [ -f "${APEX_TARGET_DIR}/apxsilentins.sql" ] && [ -d "${APEX_TARGET_DIR}/images" ]; then
    echo "[APEX-DOWNLOAD] APEX files already present in ${APEX_TARGET_DIR}. Skipping download."
    exit 0
fi

echo "[APEX-DOWNLOAD] APEX files not found in ${APEX_TARGET_DIR}."
echo "[APEX-DOWNLOAD] Downloading APEX from ${APEX_DOWNLOAD_URL}..."

TEMP_ZIP="/tmp/apex.zip"
TEMP_EXTRACT="/tmp/apex_extract"
rm -rf "${TEMP_ZIP}" "${TEMP_EXTRACT}"
mkdir -p "${TEMP_EXTRACT}"

curl -L --fail --show-error --progress-bar -o "${TEMP_ZIP}" "${APEX_DOWNLOAD_URL}"

echo "[APEX-DOWNLOAD] Download completed. Extracting archive..."
unzip -q "${TEMP_ZIP}" -d "${TEMP_EXTRACT}"

if [ ! -f "${TEMP_EXTRACT}/apex/apxsilentins.sql" ]; then
    echo "[APEX-DOWNLOAD] ERROR: apxsilentins.sql not found in downloaded archive!"
    exit 1
fi

echo "[APEX-DOWNLOAD] Moving extracted files to ${APEX_TARGET_DIR}..."
cp -r "${TEMP_EXTRACT}/apex"/* "${APEX_TARGET_DIR}/"
chmod -R 755 "${APEX_TARGET_DIR}"

rm -rf "${TEMP_ZIP}" "${TEMP_EXTRACT}"
echo "[APEX-DOWNLOAD] APEX files successfully installed in ${APEX_TARGET_DIR}."
