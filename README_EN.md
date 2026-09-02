# Oracle APEX + ORDS + ClamAV + C-ICAP Docker Stack

[🇩🇪 Deutsch](README.md) | [🇬🇧 English](README_EN.md)

Fully automated, containerized environment for **Oracle Database 23ai Free**, **Oracle APEX 24.2**, **Oracle REST Data Services (ORDS) 24.3.0**, **ClamAV 1.4.3**, and a **C-ICAP Server** with pure TCP network streaming and strict fail-closed security.

---

## 🌟 Highlights of this Solution

1. **No `latest` Tags**: All container and base images are pinned to specific, up-to-date, stable versions.
2. **Strict Fail-Closed Security**: C-ICAP and ORDS are configured to **strictly block file uploads** if ClamAV is offline or unreachable (`Threat=ClamAV-Scanner-Offline`).
3. **Horizontal Scalability**: C-ICAP communicates with ClamAV **strictly over the network via TCP (port 3310 / `INSTREAM`)** — zero shared filesystem volumes between C-ICAP and ClamAV.
4. **Fully Automated Single-Command Initialization**:
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
|      +--------------------------------+                   |                             |
|                                                           | TCP Stream (Port 3310)      |
|                                                           | (INSTREAM Protocol)         |
|                                                           v                             |
|                                            +--------------+---------------+             |
|                                            |     ClamAV 1.4.3 Daemon      |             |
|                                            |  - Official LTS image        |             |
|                                            |  - Signature database        |             |
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

### 2. Start the Stack
```bash
docker compose up -d
```

### 3. What Happens Automatically in the Background:
1. **`apex-download`**: Downloads the official APEX 24.2 distribution and extracts it into the volume `apex_software_files`.
2. **`clamav`**: Starts the ClamAV daemon and opens TCP port 3310 with detailed logging (`LogClean=yes`).
3. **`c-icap`**: Builds the C-ICAP container with the patched `squidclamav` module and connects via TCP to ClamAV.
4. **`db`**: Starts Oracle Database 23ai Free. On first run, it executes `01_setup_users.sql` (schema `DEMO`, table `DEMO_FILES`) and `02_install_apex.sh` (silent APEX install in `FREEPDB1`, creates workspace `DEMO` and admin `DEMO_ADMIN`).
5. **`ords`**: Sets up the PL/SQL gateway, enables ICAP integration (`c-icap:1344`), and mounts static APEX images (`/i/`).

> **Note on Initial Setup**:  
> The first-time APEX database installation takes approximately **3 to 5 minutes**.  
> You can monitor the progress live:
> ```bash
> docker compose logs -f db ords
> ```

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

## 🧪 Testing Antivirus & Uploads

For detailed instructions and log tracking commands, see [**`test.md`**](test.md).

### Quick Test Overview:

* **Test 1: Clean File**: Checked by ClamAV (`instream: OK`), C-ICAP returns `204 No modification needed`, upload succeeds.
* **Test 2: EICAR Test Virus**: Intercepted (`Eicar-Test-Signature FOUND`), C-ICAP sends `X-Infection-Found`, ORDS terminates the upload and prevents database persistence.
* **Test 3: Fail-Closed (ClamAV Offline)**:
  ```bash
  docker compose stop clamav
  ```
  Attempting an upload triggers C-ICAP to report `Threat=ClamAV-Scanner-Offline`. ORDS immediately aborts the upload. **No file can bypass scanning!**

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

## 📈 Horizontal Scaling

Because C-ICAP uses pure TCP network streaming without shared filesystem volumes, you can scale ClamAV horizontally:
1. Run multiple ClamAV replicas behind an internal load balancer or Docker DNS round-robin.
2. In `c-icap/squidclamav.conf`, multiple backend IPs can be specified as a comma-separated list (`clamd_ip host1,host2`).

---

## 🤖 AI Assistance Notice

This project, its configuration, and integration scripts were created and tested with the help of advanced AI pair programming tools (Google Antigravity).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE). You are free to use, modify, and distribute it. Provided "AS IS", without warranty of any kind.
