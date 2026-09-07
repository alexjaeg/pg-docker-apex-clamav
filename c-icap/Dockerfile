# ==============================================================================
# Dockerfile for Native Antivirus ICAP Service (RFC 3507)
# Enforces strict Fail-Closed security for Oracle ORDS & APEX
# Standard Debian 12.9 package (python3) - Zero third-party C dependencies or GitHub downloads
# ==============================================================================

FROM debian:12.9-slim

LABEL maintainer="Antigravity Team"
LABEL description="Native ICAP Antivirus Service with ClamAV TCP Streaming for Oracle ORDS & APEX"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        ca-certificates \
        netcat-openbsd \
        procps && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY server.py /app/server.py
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 1344

HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --retries=3 \
    CMD nc -z localhost 1344 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
