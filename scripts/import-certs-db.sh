#!/bin/bash
set -e

# ==============================================================================
# Oracle Database 23ai Startup Hook: Custom Corporate Certificate Importer
# Runs on every database start via /container-entrypoint-startdb.d/
# ==============================================================================

CERT_DIR="/cert"
BUNDLE_FILE="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

if [ -d "$CERT_DIR" ]; then
    shopt -s nullglob
    certs=("$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer)
    shopt -u nullglob

    if [ ${#certs[@]} -gt 0 ]; then
        echo "[DB-Cert] Found ${#certs[@]} custom certificate(s) in $CERT_DIR."
        if [ -w "$BUNDLE_FILE" ]; then
            for cert in "${certs[@]}"; do
                base=$(basename "$cert")
                echo "[DB-Cert] Appending $base to $BUNDLE_FILE..."
                cat "$cert" >> "$BUNDLE_FILE"
            done
            echo "[DB-Cert] Oracle Database TLS CA bundle updated successfully."
        else
            echo "[DB-Cert] Notice: $BUNDLE_FILE is not writable directly (managed via shared volume)."
        fi
    else
        echo "[DB-Cert] No custom certificates found in $CERT_DIR."
    fi
fi
