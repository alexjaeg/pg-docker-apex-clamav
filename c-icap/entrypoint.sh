#!/bin/bash
set -e

CLAMD_HOST="${CLAMD_HOST:-clamav}"
CLAMD_PORT="${CLAMD_PORT:-3310}"
CERT_DIR="/cert"

# 0. Import custom corporate certificates into system trust store
if [ -d "$CERT_DIR" ]; then
    count=0
    for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
        if [ -f "$cert" ]; then
            count=$((count + 1))
        fi
    done

    if [ "$count" -gt 0 ]; then
        echo "[ICAP] Found $count custom certificate(s) in $CERT_DIR. Importing..."
        mkdir -p /usr/local/share/ca-certificates/custom
        for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
            if [ -f "$cert" ]; then
                cp "$cert" /usr/local/share/ca-certificates/custom/
            fi
        done
        update-ca-certificates >/dev/null 2>&1 || true
        echo "[ICAP] System CA trust store updated successfully."
    fi
fi

echo "[ICAP] Waiting for ClamAV daemon at ${CLAMD_HOST}:${CLAMD_PORT} to respond with PONG..."
max_retries=60
counter=0
until echo "PING" | nc -w 3 "${CLAMD_HOST}" "${CLAMD_PORT}" 2>/dev/null | grep -q "PONG"; do
    counter=$((counter + 1))
    if [ $counter -ge $max_retries ]; then
        echo "[ICAP] Warning: Timeout waiting for ClamAV at ${CLAMD_HOST}:${CLAMD_PORT}. Starting in Fail-Closed mode."
        break
    fi
    echo "[ICAP] ClamAV is initializing / loading signatures. Waiting 2s... ($counter/$max_retries)"
    sleep 2
done

if [ $counter -lt $max_retries ]; then
    echo "[ICAP] ClamAV daemon is ready and responding with PONG on port ${CLAMD_PORT}."
fi

echo "[ICAP] Starting Native Antivirus ICAP Server..."
exec python3 /app/server.py
