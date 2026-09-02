#!/bin/bash
set -euo pipefail

MARKER_FILE="/opt/oracle/oradata/.apex_installed"
APEX_DIR="/apex"

echo "================================================================="
echo "[DB-INIT] Oracle Database APEX Installation Script"
echo "================================================================="

if [ -f "${MARKER_FILE}" ]; then
    echo "[DB-INIT] APEX is already installed (marker found: ${MARKER_FILE}). Skipping."
    exit 0
fi

echo "[DB-INIT] Checking for APEX installation files in ${APEX_DIR}..."
max_wait=120
counter=0
while [ ! -f "${APEX_DIR}/apexins.sql" ]; do
    counter=$((counter + 1))
    if [ $counter -ge $max_wait ]; then
        echo "[DB-INIT] ERROR: APEX installer files not found in ${APEX_DIR} after timeout."
        exit 1
    fi
    echo "[DB-INIT] Waiting for APEX files to become available ($counter/$max_wait)..."
    sleep 3
done

echo "[DB-INIT] APEX installer found. Starting installation into FREEPDB1..."
echo "[DB-INIT] This process installs APEX schemas and will take approximately 3-5 minutes. Please wait..."

APEX_PASSWORD="${APEX_PWD:-Welcome12345!2}"
DEMO_WS="${DEMO_WORKSPACE:-DEMO}"
DEMO_USR="${DEMO_USER:-DEMO_ADMIN}"
DEMO_PASSWORD="${DEMO_PWD:-DemoPassword123!4}"
DEMO_MAIL="${DEMO_EMAIL:-demo@example.com}"

cd "${APEX_DIR}"

# 1. Recompile invalid objects in FREEPDB1 (ensures XDB and prerequisites are VALID)
echo "[DB-INIT] Validating database components..."
sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR CONTINUE;
ALTER SESSION SET CONTAINER = FREEPDB1;
@?/rdbms/admin/utlrp.sql;
EXIT;
EOF

# 2. Run official APEX installation for Multitenant PDB
echo "[DB-INIT] Running @apexins.sql SYSAUX SYSAUX TEMP /i/ ..."
sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
ALTER SESSION SET CONTAINER = FREEPDB1;
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
EOF

echo "[DB-INIT] APEX schema installation completed successfully."

# 3. Configure APEX REST endpoints
echo "[DB-INIT] Configuring APEX REST services..."
sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR CONTINUE;
ALTER SESSION SET CONTAINER = FREEPDB1;
@apex_rest_config_core.sql ${APEX_DIR}/ "${APEX_PASSWORD}" "${APEX_PASSWORD}"
EXIT;
EOF

# 4. Unlock and set passwords for APEX gateway users & internal ADMIN
echo "[DB-INIT] Setting passwords and unlocking APEX accounts..."
sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR CONTINUE;
ALTER SESSION SET CONTAINER = FREEPDB1;

ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${APEX_PASSWORD}";

ALTER USER APEX_LISTENER ACCOUNT UNLOCK;
ALTER USER APEX_LISTENER IDENTIFIED BY "${APEX_PASSWORD}";

ALTER USER APEX_REST_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_REST_PUBLIC_USER IDENTIFIED BY "${APEX_PASSWORD}";

-- Set internal ADMIN password
DECLARE
    v_schema VARCHAR2(30);
BEGIN
    SELECT username INTO v_schema FROM all_users WHERE username LIKE 'APEX_%' AND username NOT LIKE '%_FILES' AND username NOT LIKE '%_PUBLIC_USER' AND ROWNUM = 1;
    EXECUTE IMMEDIATE '
        BEGIN
            ' || v_schema || '.wwv_flow_instance_admin.create_or_update_admin_user(
                p_username => ''ADMIN'',
                p_email    => ''admin@example.com'',
                p_password => ''' || REPLACE('${APEX_PASSWORD}', '''', '''''') || '''
            );
            COMMIT;
        END;
    ';
END;
/
EXIT;
EOF

# 5. Create Demo Workspace and Demo Administrator
echo "[DB-INIT] Creating Demo Workspace [${DEMO_WS}] and Administrator [${DEMO_USR}]..."
sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Add Demo Workspace
BEGIN
    apex_instance_admin.add_workspace(
        p_workspace      => '${DEMO_WS}',
        p_primary_schema => 'DEMO'
    );
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Create Demo Administrator User
BEGIN
    apex_util.set_security_group_id(apex_util.find_security_group_id('${DEMO_WS}'));
    BEGIN
        apex_util.create_user(
            p_user_name                    => '${DEMO_USR}',
            p_web_password                 => '${DEMO_PASSWORD}',
            p_email_address                => '${DEMO_MAIL}',
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_default_schema               => 'DEMO',
            p_allow_access_to_schemas      => 'DEMO',
            p_change_password_on_first_use => 'N'
        );
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
    COMMIT;
END;
/
EXIT;
EOF

touch "${MARKER_FILE}"
echo "================================================================="
echo "[DB-INIT] Oracle APEX and Demo Workspace initialization complete!"
echo "[DB-INIT] Workspace: ${DEMO_WS} | User: ${DEMO_USR}"
echo "================================================================="
