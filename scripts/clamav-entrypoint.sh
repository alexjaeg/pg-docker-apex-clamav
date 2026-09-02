#!/bin/sh
set -e

# ==============================================================================
# ClamAV Entrypoint Wrapper: Custom Corporate Certificate Importer
# Ensures freshclam and clamd trust corporate SSL interception proxies
# ==============================================================================

CERT_DIR="/cert"

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

# Hand over to original ClamAV entrypoint
exec /init "$@"
