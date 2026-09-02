# ==============================================================================
# Multi-Stage Dockerfile for C-ICAP with SquidClamav TCP Streaming (INSTREAM)
# Enforces strict Fail-Closed security for Oracle ORDS & APEX
# Pinned Debian release (Bookworm) - No latest tags
# ==============================================================================

# Stage 1: Build squidclamav.so with Fail-Closed patch
FROM debian:12.9-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        c-icap \
        libicapapi-dev \
        libssl-dev \
        libc6-dev \
        gcc \
        make \
        curl \
        ca-certificates \
        python3

COPY patch_fail_closed.py /tmp/patch_fail_closed.py

RUN mkdir -p /tmp/build && \
    cd /tmp/build && \
    curl -sL https://github.com/darold/squidclamav/archive/refs/tags/v7.3.tar.gz | tar xz && \
    cd squidclamav-7.3 && \
    python3 /tmp/patch_fail_closed.py && \
    ./configure --with-c-icap --sysconfdir=/etc/c-icap && \
    make && \
    make install

# Stage 2: Final clean runtime image
FROM debian:12.9-slim

LABEL maintainer="Antigravity Team"
LABEL description="C-ICAP Server with SquidClamav streaming module for Oracle ORDS & APEX"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        c-icap \
        curl \
        ca-certificates \
        netcat-openbsd \
        procps && \
    rm -rf /var/lib/apt/lists/*

# Copy compiled squidclamav module and templates from builder
COPY --from=builder /usr/lib/*-linux-gnu/c_icap/squidclamav.so /usr/lib/c_icap/squidclamav.so
COPY --from=builder /usr/share/c_icap/templates/squidclamav /usr/share/c_icap/templates/squidclamav

# Ensure library is in architecture-specific paths as well
RUN for libdir in /usr/lib/*-linux-gnu/c_icap; do \
        if [ -d "$libdir" ]; then \
            cp /usr/lib/c_icap/squidclamav.so "$libdir/" 2>/dev/null || true; \
        fi; \
    done

# Copy configurations and entrypoint script
COPY c-icap.conf /etc/c-icap/c-icap.conf
COPY squidclamav.conf /etc/c-icap/squidclamav.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
    mkdir -p /var/run/c-icap /var/log/c-icap /tmp && \
    chown -R c-icap:c-icap /var/run/c-icap /var/log/c-icap /tmp /etc/c-icap /usr/share/c_icap/templates

EXPOSE 1344

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD nc -z localhost 1344 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
