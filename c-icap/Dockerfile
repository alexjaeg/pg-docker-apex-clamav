# ==============================================================================
# Dockerfile for C-ICAP with SquidClamav TCP Streaming (INSTREAM)
# Enforces strict Fail-Closed security for Oracle ORDS & APEX
# Pure local build from ./dl (ZERO internet downloads in this container)
# Pinned Debian release (Bookworm) - No latest tags
# ==============================================================================

FROM debian:12.9-slim

LABEL maintainer="Antigravity Team"
LABEL description="C-ICAP Server with SquidClamav streaming module for Oracle ORDS & APEX"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        c-icap \
        libicapapi-dev \
        libssl-dev \
        libc6-dev \
        gcc \
        make \
        tar \
        gzip \
        python3 \
        ca-certificates \
        netcat-openbsd \
        procps && \
    rm -rf /var/lib/apt/lists/*

# Copy configurations, fail-closed patch script, and entrypoint
COPY patch_fail_closed.py /etc/c-icap/patch_fail_closed.py
COPY c-icap.conf /etc/c-icap/c-icap.conf
COPY squidclamav.conf /etc/c-icap/squidclamav.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
    mkdir -p /var/run/c-icap /var/log/c-icap /tmp /usr/share/c_icap/templates && \
    chown -R c-icap:c-icap /var/run/c-icap /var/log/c-icap /tmp /etc/c-icap /usr/share/c_icap/templates

EXPOSE 1344

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD nc -z localhost 1344 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
