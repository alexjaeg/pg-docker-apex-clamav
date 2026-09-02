#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/ords/config"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-1521}"
DB_SERVICE="${DB_SERVICE:-freepdb1}"
ICAP_HOST="${ICAP_HOST:-c-icap}"
ICAP_PORT="${ICAP_PORT:-1344}"
ORACLE_PASSWORD="${ORACLE_PWD:-Welcome12345!1}"
APEX_PASSWORD="${APEX_PWD:-Welcome12345!2}"

echo "================================================================="
echo "[ORDS] Starting Oracle REST Data Services Initialization..."
echo "================================================================="

mkdir -p "${CONFIG_DIR}"

# 1. Wait for database listener to accept connections
echo "[ORDS] Waiting for database at ${DB_HOST}:${DB_PORT}..."
until (echo > /dev/tcp/${DB_HOST}/${DB_PORT}) >/dev/null 2>&1; do
    echo "[ORDS] Database listener not ready yet. Retrying in 5s..."
    sleep 5
done
echo "[ORDS] Database listener is reachable."

# 2. Wait for C-ICAP server
echo "[ORDS] Waiting for C-ICAP server at ${ICAP_HOST}:${ICAP_PORT}..."
until (echo > /dev/tcp/${ICAP_HOST}/${ICAP_PORT}) >/dev/null 2>&1; do
    echo "[ORDS] C-ICAP server not ready yet. Retrying in 5s..."
    sleep 5
done
echo "[ORDS] C-ICAP server is reachable."

# 3. Check if ORDS connection pool has been installed
POOL_CONFIG="${CONFIG_DIR}/databases/default/pool.xml"
if [ ! -f "${POOL_CONFIG}" ]; then
    echo "[ORDS] First startup detected: Installing and configuring ORDS schema in ${DB_SERVICE}..."
    
    /opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" install \
        --admin-user SYS \
        --proxy-user \
        --db-hostname "${DB_HOST}" \
        --db-port "${DB_PORT}" \
        --db-servicename "${DB_SERVICE}" \
        --feature-db-api true \
        --feature-rest-enabled-sql true \
        --feature-sdw true \
        --gateway-mode proxied \
        --gateway-user APEX_PUBLIC_USER \
        --password-stdin <<EOF
${ORACLE_PASSWORD}
${APEX_PASSWORD}
EOF

    echo "[ORDS] ORDS database schema installation completed."
else
    echo "[ORDS] Existing ORDS configuration found. Skipping schema installation."
fi

# 4. Configure Gateway, ICAP Virus Scanner and Static Resources
echo "[ORDS] Configuring PL/SQL Gateway & ICAP Virus Scanner integration..."
/opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" config --db-pool default set plsql.gateway.mode proxied || true
/opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" config set icap.server "${ICAP_HOST}"
/opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" config set icap.port "${ICAP_PORT}"
/opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" config set standalone.static.context.path "/i"
/opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" config set standalone.static.path "/opt/oracle/apex/images"

echo "================================================================="
echo "[ORDS] All configurations set. Starting ORDS Standalone Server..."
echo "================================================================="

exec /opt/oracle/ords/bin/ords --config "${CONFIG_DIR}" serve
