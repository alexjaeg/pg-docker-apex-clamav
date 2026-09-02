# Oracle APEX + ORDS + ClamAV + C-ICAP Docker Stack

[🇩🇪 Deutsch](README.md) | [🇬🇧 English](README_EN.md)

Fully automated, containerized environment for **Oracle Database 23ai Free**, **Oracle APEX 24.2**, **Oracle REST Data Services (ORDS) 24.3.0**, **ClamAV 1.4.3**, and a **C-ICAP Server** with pure TCP network streaming, strict fail-closed security, and native custom corporate/AI certificate integration (Corporate CA / LiteLLM).

---

## 🌟 Highlights of this Solution

1. **No `latest` Tags**: All container and base images are pinned to specific, up-to-date, stable versions.
2. **Strict Fail-Closed Security**: C-ICAP and ORDS are configured to **strictly block file uploads** if ClamAV is offline or unreachable (`Threat=ClamAV-Scanner-Offline`).
3. **Custom Certificates & AI Support (Corporate CA & LiteLLM)**: Any certificates placed in the [`cert/`](cert/) directory (`.crt`, `.pem`, `.cer`) are automatically imported across all 5 containers (Oracle DB 23ai, ORDS/Java, C-ICAP, ClamAV, Downloader). Eliminates certificate validation errors (`ORA-29024` / `PKIX`) when calling internal AI services (LiteLLM, Ollama) or operating behind SSL interception proxies.
4. **Horizontal Scalability**: C-ICAP communicates with ClamAV **strictly over the network via TCP (port 3310 / `INSTREAM`)** — zero shared filesystem volumes between C-ICAP and ClamAV.
5. **Fully Automated Single-Command Initialization**:
   - The database initializes itself (`gvenzl/oracle-free:23.5-slim-faststart`).
   - APEX downloads automatically and performs a silent install into the Pluggable Database (`FREEPDB1`).
   - Demo Workspace (`DEMO`) and Administrator User (`DEMO_ADMIN`) are created automatically.
   - ORDS automatically configures the schemas, PL/SQL gateway, and ICAP antivirus integration.
   - All credentials and ports are managed centrally via `.env`.

---

## 🏗️ Architecture

```
                                  +-----------------------+
                                  |      Web Browser      |
                                  +-----------+-----------+
                                              | HTTP (8080)
                                              v
+-----------------------------------------------------------------------------------------+
| Docker Compose Network: apex_clamav_network                                             |
|                                                                                         |
|      +--------------------------------------------------------------------+             |
|      |               ORDS 24.3.0 (Oracle REST Data Services)              |             |
|      |  - Gateway proxy for APEX                                          |             |
|      |  - ICAP client: intercepts uploads before DB persistence           |             |
|      |  - Custom CAs in Java Keystore & OS trust store                    |             |
|      +---------------------+------------------------------+---------------+             |
|                            |                              |                             |
|          JDBC (Port 1521)  |                              | ICAP (Port 1344)            |
|                            v                              v                             |
|      +---------------------+----------+    +--------------+---------------+             |
|      |    Oracle DB 23ai Free         |    |      C-ICAP Server           |             |
|      |    (23.5-slim-faststart)       |    |      (debian:12.9-slim)      |             |
|      |  - PDB: FREEPDB1               |    |  - Service: AVSCAN           |             |
|      |  - APEX 24.2 pre-installed     |    |  - TCP streaming             |             |
|      |  - Workspace: DEMO             |    +--------------+---------------+             |
|      |  - Shared CA bundle for AI/REST|                   |                             |
|      +--------------------------------+                   | TCP Stream (Port 3310)      |
|                                                           | (INSTREAM Protocol)         |
|                                                           v                             |
|                                            +--------------+---------------+             |
|                                            |     ClamAV 1.4.3 Daemon      |             |
|                                            |  - Official LTS image        |             |
|                                            |  - Signature database        |             |
|                                            |  - CA bundle for freshclam   |             |
|                                            +------------------------------+             |
+-----------------------------------------------------------------------------------------+
```

---

## 📦 Components & Versions

| Component | Image / Base | Version | Role |
| :--- | :--- | :--- | :--- |
| **ClamAV** | `clamav/clamav:1.4.3` | `1.4.3` (LTS) | Official antivirus daemon |
| **C-ICAP** | `custom-c-icap:debian-12.9` | `debian:12.9-slim` | ICAP server with TCP streaming (`squidclamav 7.3`) |
| **Oracle DB** | `gvenzl/oracle-free:23.5-slim-faststart` | `23.5` | Oracle Database 23ai Free |
| **Oracle APEX** | Oracle CDN Archive | `24.2` | Low-code application platform |
| **ORDS** | `container-registry.oracle.com/database/ords:24.3.0` | `24.3.0` | Web server & ICAP gateway |

---

## 🚀 Quick Start (1 Step)

### 1. Configure Environment (Optional)
Copy `.env.example` to `.env` and adjust passwords if needed:
```bash
cp .env.example .env
```

### 2. Add Custom Certificates (Optional)
If working behind a corporate proxy or connecting to local AI services (LiteLLM, Ollama):  
Simply place your `.crt` or `.pem` files in the [`cert/`](cert/) directory.

### 3. Start the Stack
```bash
docker compose up -d
```

### 4. What Happens Automatically in the Background:
1. **`apex-download`**: Imports custom certs, builds the shared database CA bundle, and downloads APEX 24.2.
2. **`clamav`**: Starts with imported CA certificates (allowing `freshclam` to update over corporate proxies) and detailed logging (`LogClean=yes`).
3. **`c-icap`**: Builds the patched `squidclamav` module and connects via TCP to ClamAV.
4. **`db`**: Starts Oracle Database 23ai Free with the augmented CA bundle. Runs `01_setup_users.sql` and `02_install_apex.sh` (silent install in `FREEPDB1`).
5. **`ords`**: Imports certificates into Java's keystore (`cacerts`), configures the PL/SQL gateway and ICAP scanner.

---

## 🔑 Credentials & URLs

All credentials are loaded from `.env` (template: `.env.example`):

| Service | URL / Connection | Workspace | Username | Password |
| :--- | :--- | :--- | :--- | :--- |
| **APEX Workspace** | `http://localhost:8080/ords` | `DEMO` | `DEMO_ADMIN` | `DemoPassword123!4` |
| **APEX Internal Admin**| `http://localhost:8080/ords/apex_admin` | `INTERNAL` | `ADMIN` | `Welcome12345!2` |
| **Oracle Database** | `localhost:1521/freepdb1` | - | `SYS AS SYSDBA` | `Welcome12345!1` |
| **Demo Schema** | `localhost:1521/freepdb1` | - | `DEMO` | `DemoPassword123!4` |

---

## 🧪 Testing & Verification

Detailed step-by-step test guides are available in the [**test/**](test/) folder:

* [**test/test-clamav.md**](test/test-clamav.md): Antivirus verification, live log tracing, and fail-closed test when ClamAV is stopped.
* [**test/test-cert.md**](test/test-cert.md): Custom certificate verification (Corporate CA / LiteLLM / BadSSL) in Oracle DB 23ai, Java/ORDS, and ClamAV.

---

## 🧹 Complete Teardown & Clean Reset

To completely reset the environment for testing:

```bash
# 1. Remove all containers and volumes (-v removes databases and configurations)
docker compose down -v

# 2. Re-initialize everything from scratch with a single command:
docker compose up -d
```

---

## 🤖 AI Assistance Notice

This project, its configuration, and integration scripts were created and tested with the help of advanced AI pair programming tools (Google Antigravity).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE). You are free to use, modify, and distribute it. Provided "AS IS", without warranty of any kind.
