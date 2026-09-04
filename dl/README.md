# Download-Verzeichnis / Download Directory (`dl/`)

[🇩🇪 Deutsch](#deutsch) | [🇬🇧 English](#english)

---

<a name="deutsch"></a>
## 🇩🇪 Deutsch

In diesem Verzeichnis landen alle externen Software-Archive und Downloads, die für den Stack benötigt werden.

### Funktionsweise:
1. **Automatischer Download**:
   - Wenn du den Stack startest (`docker compose up -d`), prüft der Download-Service (`apex-download`), ob die benötigten Dateien hier vorhanden sind.
   - Fehlende Dateien werden automatisch aus den offiziellen Quellen heruntergeladen und hier gespeichert.
2. **Manueller Download (Offline / Zero-Trust / Airgapped)**:
   - Wenn dein Server keinen Internetzugang hat oder strenge Firewall-Regeln gelten, kannst du die Dateien vorab manuell herunterladen und direkt in diesen Ordner `dl/` legen.
   - Der Download-Service erkennt vorhandene Dateien automatisch und überspringt den Download!
3. **Download-Übersichtsliste**:
   - Die vollständige Liste aller Download-Quellen, Dateinamen und manuellen Download-Befehle findest du in [**`downloads.txt`**](downloads.txt).

### Standard-Dateien in diesem Ordner:
- `apex_26.1.zip`: Offizielle Oracle APEX 26.1 Distribution (~326 MB)
- `squidclamav-7.3.tar.gz`: SquidClamAV Quellcode-Archiv (~160 KB)

---

<a name="english"></a>
## 🇬🇧 English

This directory contains all external software archives required by the stack.

### How It Works:
1. **Automatic Download**:
   - Running `docker compose up -d` starts the downloader service, which checks for required files.
   - Missing files are downloaded automatically into this folder.
2. **Manual Pre-Download (Airgapped / Zero-Trust Environments)**:
   - You can manually download the required files and place them into this `dl/` directory before starting the stack.
   - The downloader service automatically detects existing files and skips downloading.
3. **Manifest & Source List**:
   - See [**`downloads.txt`**](downloads.txt) for full URLs and manual download commands.
