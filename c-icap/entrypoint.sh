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
        echo "[C-ICAP] Found $count custom certificate(s) in $CERT_DIR. Importing..."
        mkdir -p /usr/local/share/ca-certificates/custom
        for cert in "$CERT_DIR"/*.crt "$CERT_DIR"/*.pem "$CERT_DIR"/*.cer; do
            if [ -f "$cert" ]; then
                cp "$cert" /usr/local/share/ca-certificates/custom/
            fi
        done
        update-ca-certificates >/dev/null 2>&1 || true
        echo "[C-ICAP] System CA trust store updated successfully."
    fi
fi

echo "[C-ICAP] Checking directories and permissions..."
mkdir -p /var/run/c-icap /var/log/c-icap /tmp
chown -R c-icap:c-icap /var/run/c-icap /var/log/c-icap /tmp /etc/c-icap
rm -f /var/run/c-icap/c-icap.pid /var/run/c-icap/c-icap.ctl

# Dynamically update clamd_ip and clamd_port in squidclamav.conf
if [ -f /etc/c-icap/squidclamav.conf ]; then
    sed -i "s/^clamd_ip .*/clamd_ip ${CLAMD_HOST}/" /etc/c-icap/squidclamav.conf
    sed -i "s/^clamd_port .*/clamd_port ${CLAMD_PORT}/" /etc/c-icap/squidclamav.conf
fi

echo "[C-ICAP] Waiting for ClamAV daemon at ${CLAMD_HOST}:${CLAMD_PORT} to respond with PONG..."
max_retries=60
counter=0
until echo "PING" | nc -w 3 "${CLAMD_HOST}" "${CLAMD_PORT}" 2>/dev/null | grep -q "PONG"; do
    counter=$((counter + 1))
    if [ $counter -ge $max_retries ]; then
        echo "[C-ICAP] Error: Timeout waiting for ClamAV at ${CLAMD_HOST}:${CLAMD_PORT}."
        exit 1
    fi
    echo "[C-ICAP] ClamAV is initializing / loading signatures. Waiting 2s... ($counter/$max_retries)"
    sleep 2
done

echo "[C-ICAP] ClamAV daemon is ready and responding with PONG on port ${CLAMD_PORT}."
echo "[C-ICAP] Starting c-icap server in foreground..."
exec c-icap -f /etc/c-icap/c-icap.conf -N -D -d 1
