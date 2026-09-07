# Oracle APEX + ClamAV Playwright End-to-End Tests

[🇩🇪 Deutsch](#deutsch) | [🇬🇧 English](#english)

---

<a name="deutsch"></a>
## 🇩🇪 Deutsch

Automatisierte End-to-End (E2E) Testsuite mit **Playwright**, um die Virenscanner-Integration und den Fail-Closed-Schutz in **Oracle APEX 26.1**, **ORDS 26.2.2** und **ClamAV 1.4.3** lückenlos im echten Browser zu verifizieren.

---

### 🌟 Was diese E2E-Tests prüfen

1. **Automatischer Durchlauf**:
   - Startet auf `http://localhost:8080/ords/_/landing` und betätigt den Button **[Los]** auf der Oracle APEX Card.
   - Führt den Login am Workspace **`DEMO`** mit dem User **`DEMO_ADMIN`** durch.
   - Öffnet die Beispielanwendung **"Sample File Upload and Download"** (bzw. installiert sie bei Bedarf automatisch aus der Gallery).
   - Startet die Anwendung über den **[Run Application]** (Play)-Button.
   - Führt bei Bedarf den Login in der Sample App mit `DEMO_ADMIN` durch.
   - Klickt im Bereich **Recent Files** oben rechts auf das Plus-Symbol **[+]** (**Add File**).
2. **Testfall 1: Saubere Datei (Erlaubt)**:
   - Wählt ein Projekt aus und lädt die saubere Testdatei hoch.
   - **Ergebnis**: Upload gelingt, Weiterleitung zur Dateiliste, Meldung *"Action Processed."* erscheint.
3. **Testfall 2: EICAR-Testvirus (Blockiert)**:
   - Lädt die Testvirendatei `eicar.txt` aus dem konfigurierten Verzeichnis hoch.
   - **Ergebnis**: Upload wird von ORDS/ClamAV **sofort abgewiesen** (*"File Infected"* / HTTP 400/403). Die Datei gelangt **nicht** in die Datenbank.
4. **Testfall 3: Strikter Fail-Closed Schutz (ClamAV gestoppt)**:
   - Stoppt den ClamAV-Container (`docker stop apex-clamav`).
   - Versucht einen Upload einer an sich sauberen Datei.
   - **Ergebnis**: Upload wird **strikt verweigert** (*"ICAP Server Unavailable"* / Fehler). Bei inaktivem Scanner sind Uploads zu 100 % unmöglich.
   - Startet den ClamAV-Container am Ende des Tests automatisch wieder.

---

### 📂 Konfiguration der Testdateien (`D:\_AVFree_`)

Die Pfade und Zugangsdaten können über Umgebungsvariablen oder in der Datei [`.env`](.env) angepasst werden:

```ini
BASE_URL=http://localhost:8080
APEX_WORKSPACE=DEMO
APEX_USER=DEMO_ADMIN
APEX_PASSWORD=DemoPassword123!4

# Verzeichnis für Testdateien (Standard für Virenscanner-Tests)
TEST_FILES_DIR=D:\_AVFree_
EICAR_FILE_NAME=eicar.txt
CLEAN_FILE_NAME=clean_sample.txt
```

> **Wichtiger Hinweis**: `TEST_FILES_DIR` ist standardmäßig auf `D:\_AVFree_` konfiguriert (der vom lokalen Virenscanner ausgenommene Ordner). Liegen die Dateien dort noch nicht, legt die Testsuite sie beim ersten Start automatisch an.

---

### 🚀 Ausführung

Wechsle in den Ordner `e2e-test`:
```powershell
cd e2e-test
```

#### 1. Beim Testlauf im Browser live zusehen (Headed Mode)
Öffnet ein sichtbares Chromium-Browserfenster, sodass du die Klicks, Logins und Uploads in Echtzeit beobachten kannst:
```powershell
npm run test:headed
```

#### 2. Schnelltest im Hintergrund (Headless Mode)
Führt alle Tests unsichtbar im Hintergrund aus (ideal für die Konsole):
```powershell
npm test
```

#### 3. Interaktive Playwright UI (Debugger / Einzelschritte)
Öffnet die visuelle Playwright-Oberfläche für Time-Travel-Debugging und Einzelschritt-Ausführung:
```powershell
npm run test:ui
```

#### 4. Gezielte Einzelausführung bestimmter Tests
```powershell
# Nur den sauberen Upload testen:
npm run test:clean

# Nur die EICAR-Virenblockade testen:
npm run test:eicar

# Nur den Fail-Closed-Schutz bei Scanner-Ausfall testen:
npm run test:fail-closed
```

---

### 🐳 Ausführung im Docker-Container (Für CI/CD Pipelines)

Für automatisierte Tests in Pipelines (GitHub Actions, GitLab CI usw.) steht ein Dockerfile bereit:

```powershell
# 1. Test-Container bauen und im Docker-Compose Netzwerk ausführen:
docker compose -f docker-compose.test.yml run --rm e2e-test

# Testergebnisse und HTML-Reports landen danach im lokalen Ordner playwright-report/
```

---

<a name="english"></a>
## 🇬🇧 English

Automated End-to-End (E2E) test suite using **Playwright** to verify real-browser antivirus scanning and fail-closed security across **Oracle APEX 26.1**, **ORDS 26.2.2**, and **ClamAV 1.4.3**.

---

### 🌟 What is Tested

1. **End-to-End Navigation**:
   - Navigates from `http://localhost:8080/ords/_/landing` through the APEX card [Los] button.
   - Logs into Workspace **`DEMO`** using **`DEMO_ADMIN`**.
   - Opens or automatically installs the **"Sample File Upload and Download"** application.
   - Clicks **[Run Application]** (Play button) and authenticates if prompted.
   - Clicks the **[+]** (**Add File**) button in the **Recent Files** region.
2. **Test 1: Clean File Upload (Allowed)**:
   - Uploads a clean test file. Verifies successful completion and *"Action Processed."* notification.
3. **Test 2: EICAR Test Virus (Blocked)**:
   - Uploads `eicar.txt` from the configured directory.
   - Verifies that ORDS/ClamAV strictly blocks the upload with *"File Infected"* (HTTP 400/403). The file never enters the database.
4. **Test 3: Fail-Closed Security (ClamAV Offline)**:
   - Stops the ClamAV container (`docker stop apex-clamav`).
   - Attempts uploading a clean file. Verifies that the upload is 100% blocked (*"ICAP Server Unavailable"*).
   - Automatically restarts the ClamAV container.

---

### 🚀 Running the Tests

```powershell
cd e2e-test

# Run with visible browser window (watch test live):
npm run test:headed

# Run silently in background:
npm test

# Run interactive UI:
npm run test:ui

# Run in Docker container:
docker compose -f docker-compose.test.yml run --rm e2e-test
```
