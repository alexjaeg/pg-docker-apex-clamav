#!/bin/sh
set -e

# ==============================================================================
# ClamAV Entrypoint Wrapper: Custom Corporate Certificate & Offline DB Importer
# Ensures freshclam and clamd trust corporate SSL interception proxies
# Supports offline virus definitions from ./dl
# ==============================================================================

CERT_DIR="/cert"
DOWNLOAD_DIR="/downloads"

# 1. Import custom certificates
if [ -d "$CERT_DIR" ]; then
    count=0
    for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
        if [ -f "$cert" ]; then
            count=$((count + 1))
        fi
    done

    if [ "$count" -gt 0 ]; then
        echo "[ClamAV] Found $count custom certificate(s) in $CERT_DIR. Importing into CA bundle..."
        for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
            if [ -f "$cert" ]; then
                base=$(basename "$cert")
                echo "[ClamAV] Appending $base to /etc/ssl/certs/ca-certificates.crt..."
                cat "$cert" >> /etc/ssl/certs/ca-certificates.crt
            fi
        done
        echo "[ClamAV] CA bundle updated successfully."
    else
        echo "[ClamAV] No custom certificates found in $CERT_DIR."
    fi
fi

# 2. Check for offline virus database files in ./dl
if [ -d "$DOWNLOAD_DIR" ]; then
    for cvd in "$DOWNLOAD_DIR"/*.cvd "$DOWNLOAD_DIR"/clamav/*.cvd; do
        if [ -f "$cvd" ]; then
            echo "[ClamAV] Found offline virus database: $(basename "$cvd"). Copying to /var/lib/clamav/..."
            cp -f "$cvd" /var/lib/clamav/
            chown clamav:clamav /var/lib/clamav/"$(basename "$cvd")" 2>/dev/null || true
        fi
    done
fi

# Hand over to original ClamAV entrypoint
exec /init "$@"
