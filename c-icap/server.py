#!/usr/bin/env python3
"""
Lightweight High-Performance ICAP Antivirus Server (RFC 3507)
Translates ICAP REQMOD/RESPMOD requests into ClamAV INSTREAM TCP calls.
Enforces strict Fail-Closed security.
Uses standard Python 3 standard library only (no external dependencies).
"""

import asyncio
import logging
import os
import re
import socket
import struct
import sys

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] [ICAP-Server] %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger('icap_server')

CLAMD_HOST = os.environ.get('CLAMD_HOST', 'clamav')
CLAMD_PORT = int(os.environ.get('CLAMD_PORT', '3310'))
ICAP_PORT = int(os.environ.get('ICAP_PORT', '1344'))
SERVICE_NAME = os.environ.get('SERVICE_NAME', 'avscan')
ISTAG = '"CLAMAV-INSTREAM-1.0"'

async def scan_stream_with_clamav(chunks):
    """
    Connects to ClamAV daemon over TCP, sends zINSTREAM, and streams the chunks.
    Returns (status: 'CLEAN'|'INFECTED'|'ERROR', threat_name: str).
    """
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(CLAMD_HOST, CLAMD_PORT),
            timeout=5.0
        )
    except Exception as e:
        logger.error(f"Cannot connect to ClamAV daemon at {CLAMD_HOST}:{CLAMD_PORT}: {e}")
        return 'ERROR', 'ClamAV-Scanner-Offline'

    try:
        writer.write(b'zINSTREAM\0')
        await writer.drain()

        total_bytes = 0
        for chunk in chunks:
            if chunk:
                total_bytes += len(chunk)
                writer.write(struct.pack('>I', len(chunk)) + chunk)
                await writer.drain()

        # Send zero-length chunk to signal EOF
        writer.write(struct.pack('>I', 0))
        await writer.drain()

        # Read response from ClamAV (e.g. b"stream: OK\0" or b"stream: Eicar-Test-Signature FOUND\0")
        response_bytes = await asyncio.wait_for(reader.read(4096), timeout=30.0)
        writer.close()
        await writer.wait_closed()

        response_str = response_bytes.decode('utf-8', errors='replace').strip('\0\r\n ')
        logger.info(f"ClamAV scan completed ({total_bytes} bytes). Response: {response_str}")

        if 'FOUND' in response_str:
            # Format is usually: "stream: <VirusName> FOUND"
            m = re.search(r'stream:\s*(.+?)\s+FOUND', response_str)
            threat = m.group(1) if m else response_str
            return 'INFECTED', threat
        elif 'OK' in response_str:
            return 'CLEAN', 'None'
        else:
            logger.warning(f"Unexpected ClamAV response: {response_str}")
            return 'ERROR', f"ClamAV-Error: {response_str}"

    except Exception as e:
        logger.error(f"Error during ClamAV streaming: {e}")
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass
        return 'ERROR', 'ClamAV-Scan-Failed'

def parse_encapsulated(header_val):
    """
    Parses 'Encapsulated: req-hdr=0, req-body=210' into dict {'req-hdr': 0, 'req-body': 210}
    """
    offsets = {}
    for part in header_val.split(','):
        if '=' in part:
            k, v = part.strip().split('=', 1)
            try:
                offsets[k.strip().lower()] = int(v.strip())
            except ValueError:
                pass
    return offsets

async def handle_client(reader, writer):
    peer = writer.get_extra_info('peername')
    logger.info(f"New ICAP connection from {peer}")

    try:
        while True:
            # Read ICAP request header until \r\n\r\n
            header_data = b""
            while b"\r\n\r\n" not in header_data:
                chunk = await reader.read(4096)
                if not chunk:
                    break
                header_data += chunk
                if len(header_data) > 65536:
                    raise ValueError("ICAP Header too large")

            if not header_data:
                break

            header_part, rest_of_data = header_data.split(b"\r\n\r\n", 1)
            header_lines = header_part.decode('iso-8859-1').split("\r\n")
            if not header_lines or not header_lines[0]:
                break

            req_line = header_lines[0].strip()
            logger.info(f"Received request: {req_line}")
            req_parts = req_line.split()
            if len(req_parts) < 2:
                break

            method = req_parts[0].upper()
            uri = req_parts[1]

            headers = {}
            for line in header_lines[1:]:
                if ':' in line:
                    k, v = line.split(':', 1)
                    headers[k.strip().lower()] = v.strip()

            # ------------------------------------------------------------------
            # 1. Handle OPTIONS request (Capability negotiation)
            # ------------------------------------------------------------------
            if method == 'OPTIONS':
                response = (
                    "ICAP/1.0 200 OK\r\n"
                    "Methods: REQMOD, RESPMOD\r\n"
                    "Service: Antivirus-ICAP/1.0\r\n"
                    f"ISTag: {ISTAG}\r\n"
                    "Max-Connections: 100\r\n"
                    "Options-TTL: 3600\r\n"
                    f"Service-Id: {SERVICE_NAME}\r\n"
                    "Allow: 204\r\n"
                    "Preview: 0\r\n"
                    "Encapsulated: null-body=0\r\n"
                    "\r\n"
                )
                writer.write(response.encode('iso-8859-1'))
                await writer.drain()
                continue

            # ------------------------------------------------------------------
            # 2. Handle REQMOD and RESPMOD (Content Scanning)
            # ------------------------------------------------------------------
            elif method in ('REQMOD', 'RESPMOD'):
                encapsulated_val = headers.get('encapsulated', '')
                offsets = parse_encapsulated(encapsulated_val)

                # Determine body offset
                body_type = None
                body_offset = None
                for btype in ('req-body', 'res-body', 'opt-body'):
                    if btype in offsets:
                        body_type = btype
                        body_offset = offsets[btype]
                        break

                # The encapsulated headers (HTTP request or response) occupy rest_of_data[:body_offset]
                # The chunks start after body_offset bytes from the beginning of the encapsulated entity.
                payload_buffer = rest_of_data
                if body_offset is not None and body_offset > 0:
                    while len(payload_buffer) < body_offset:
                        more = await reader.read(4096)
                        if not more:
                            break
                        payload_buffer += more
                    # Slice off the encapsulated HTTP headers
                    encapsulated_http_headers = payload_buffer[:body_offset]
                    chunked_body = payload_buffer[body_offset:]
                else:
                    encapsulated_http_headers = b""
                    chunked_body = payload_buffer

                # Read and de-chunk ICAP body
                # ICAP chunks are: <hex-size>[;extensions]\r\n<data>\r\n ... 0\r\n\r\n
                body_chunks = []
                buffer = chunked_body

                while True:
                    # Find chunk size line ending with \r\n
                    while b"\r\n" not in buffer:
                        more = await reader.read(8192)
                        if not more:
                            break
                        buffer += more

                    if b"\r\n" not in buffer:
                        break

                    size_line, rest = buffer.split(b"\r\n", 1)
                    # Extract hex size (ignore extensions like ; ieof)
                    size_hex = size_line.split(b';')[0].strip()
                    try:
                        chunk_size = int(size_hex, 16)
                    except ValueError:
                        logger.error(f"Invalid chunk size: {size_hex}")
                        break

                    if chunk_size == 0:
                        # End of chunks. Consume trailing \r\n
                        buffer = rest
                        if buffer.startswith(b"\r\n"):
                            buffer = buffer[2:]
                        break

                    # Read chunk_size bytes + trailing \r\n
                    needed = chunk_size + 2
                    while len(rest) < needed:
                        more = await reader.read(max(4096, needed - len(rest)))
                        if not more:
                            break
                        rest += more

                    chunk_data = rest[:chunk_size]
                    body_chunks.append(chunk_data)
                    buffer = rest[chunk_size:]
                    if buffer.startswith(b"\r\n"):
                        buffer = buffer[2:]

                # Now scan the extracted body with ClamAV
                scan_res, threat = await scan_stream_with_clamav(body_chunks)
                logger.info(f"Scan result: {scan_res} (Threat: {threat})")

                # If CLEAN: respond with ICAP 204 No Content
                if scan_res == 'CLEAN':
                    response = (
                        "ICAP/1.0 204 No Content\r\n"
                        f"ISTag: {ISTAG}\r\n"
                        "Connection: keep-alive\r\n"
                        "\r\n"
                    )
                    writer.write(response.encode('iso-8859-1'))
                    await writer.drain()
                    continue

                # If INFECTED or ERROR (ClamAV offline) -> STRICT FAIL-CLOSED BLOCK!
                else:
                    status_text = f"{threat} FOUND" if scan_res == 'INFECTED' else f"{threat}"
                    error_title = "403 Forbidden - Security Violation"
                    if scan_res == 'INFECTED':
                        error_msg = f"Virus or Malware Detected: {threat}"
                    else:
                        error_msg = f"Security Scan Service Unavailable ({threat}). Uploads blocked by Fail-Closed policy."

                    html_body = (
                        f"<!DOCTYPE html><html><head><title>{error_title}</title></head>"
                        f"<body><h1>{error_title}</h1>"
                        f"<p><b>Status:</b> {error_msg}</p>"
                        f"<hr><p><small>Secured by Antivirus Protection Service</small></p>"
                        f"</body></html>\r\n"
                    ).encode('utf-8')

                    http_headers = (
                        "HTTP/1.1 403 Forbidden\r\n"
                        "Server: Antivirus-ICAP\r\n"
                        "Content-Type: text/html; charset=utf-8\r\n"
                        f"Content-Length: {len(html_body)}\r\n"
                        f"X-Virus-ID: {status_text}\r\n"
                        f"X-Infection-Found: Type=0; Resolution=2; Threat={threat};\r\n"
                        "Connection: close\r\n"
                        "\r\n"
                    ).encode('iso-8859-1')

                    icap_headers = (
                        "ICAP/1.0 200 OK\r\n"
                        "Server: Antivirus-ICAP/1.0\r\n"
                        f"ISTag: {ISTAG}\r\n"
                        f"X-Virus-ID: {status_text}\r\n"
                        f"X-Infection-Found: Type=0; Resolution=2; Threat={threat};\r\n"
                        "Connection: close\r\n"
                        f"Encapsulated: res-hdr=0, res-body={len(http_headers)}\r\n"
                        "\r\n"
                    ).encode('iso-8859-1')

                    # Chunked transfer for ICAP res-body
                    chunk_hex = f"{len(html_body):x}\r\n".encode('ascii')
                    chunk_data = chunk_hex + html_body + b"\r\n0\r\n\r\n"

                    writer.write(icap_headers + http_headers + chunk_data)
                    await writer.drain()
                    # Close connection on block
                    break

            else:
                logger.warning(f"Unsupported ICAP method: {method}")
                writer.write(b"ICAP/1.0 501 Method Not Implemented\r\n\r\n")
                await writer.drain()
                break

    except (asyncio.IncompleteReadError, ConnectionResetError, BrokenPipeError):
        pass
    except Exception as e:
        logger.error(f"Error handling ICAP connection: {e}", exc_info=True)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass
        logger.info(f"Connection closed for {peer}")

async def main():
    logger.info("=================================================================")
    logger.info(f"Starting Native Antivirus ICAP Service on port {ICAP_PORT}...")
    logger.info(f"Forwarding to ClamAV Daemon at {CLAMD_HOST}:{CLAMD_PORT}")
    logger.info(f"Service Name: /{SERVICE_NAME}")
    logger.info("Security Policy: STRICT FAIL-CLOSED (Blocks all uploads if ClamAV offline)")
    logger.info("=================================================================")

    server = await asyncio.start_server(handle_client, '0.0.0.0', ICAP_PORT)
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server stopped by user.")
