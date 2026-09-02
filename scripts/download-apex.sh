#!/bin/bash
set -euo pipefail

APEX_TARGET_DIR="${APEX_TARGET_DIR:-/apex-files}"
APEX_DOWNLOAD_URL="${APEX_DOWNLOAD_URL:-https://download.oracle.com/otn_software/apex/apex_24.2.zip}"

echo "================================================================="
echo "[APEX-DOWNLOAD] Checking APEX installation files..."
echo "================================================================="

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
