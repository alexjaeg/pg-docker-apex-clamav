# Testanleitung: Download-Manager & Manuelle Bereitstellung (`dl/`)

[🇩🇪 Deutsch](#deutsch) | [🇬🇧 English](#english)

---

<a name="deutsch"></a>
## 🇩🇪 Deutsch

Diese Dokumentation beschreibt, wie du den Download-Service und die manuelle Bereitstellung von Software-Paketen im Ordner `dl/` testest.

---

## 🎯 Funktionsweise des Download-Managers

Der Service `apex-download` übernimmt beim Stack-Start (`docker compose up -d`) folgende Aufgaben:
1. **Zertifikats-Import**: Bindet vorhandene Firmenzertifikate aus `cert/` ein, damit Downloads auch über restriktive Firmen-Proxys mit SSL-Interception funktionieren.
2. **Download-Manifest**: Schreibt bzw. aktualisiert automatisch die Datei [**`dl/downloads.txt`**](../dl/downloads.txt) mit allen Download-URLs und manuellem Status.
3. **Erkennung manueller Dateien**: Prüft, ob `dl/apex_24.2.zip` oder `dl/squidclamav-7.3.tar.gz` bereits im Ordner `dl/` liegen.
   - Wenn **vorhanden**: Überspringt den Download und verwendet die lokale Datei direkt (ideal für Offline-/Airgapped-Systeme).
   - Wenn **fehlt**: Lädt die Datei automatisch von der offiziellen Quelle herunter.
4. **Extraktion**: Entpackt die APEX-Dateien in das persistente Volume `apex_files`.

---

## 🧪 Testfälle zum Nachstellen

### Testfall 1: Automatischer Download bei leerem `dl/`-Ordner
1. Stelle sicher, dass `dl/` keine `apex_24.2.zip` enthält.
2. Starte den Download-Service:
   ```powershell
   docker compose up apex-download
   ```
3. Beobachte die Logs:
   ```text
   [DOWNLOAD-MGR] APEX archive missing in /downloads. Downloading from https://...
   [DOWNLOAD-MGR] Download completed.
   [DOWNLOAD-MGR] Extracting /downloads/apex_24.2.zip into /apex-files...
   ```
4. Prüfe, ob die Datei auf deinem Host im Ordner `dl/` gelandet ist:
   ```powershell
   Get-ChildItem dl/
   ```

---

### Testfall 2: Erkennung manuell bereitgestellter Dateien (Offline-Modus)
1. Wenn die Datei `dl/apex_24.2.zip` bereits im Ordner `dl/` liegt:
2. Starte den Download-Service erneut:
   ```powershell
   docker compose up apex-download
   ```
3. Beobachte die Logs:
   ```text
   [DOWNLOAD-MGR] Found APEX archive: /downloads/apex_24.2.zip (Manual/Pre-downloaded).
   [DOWNLOAD-MGR] Skipping download.
   ```
   *(Der Service lädt nichts erneut aus dem Internet herunter, sondern nutzt sofort deine lokale Datei.)*

---

### Testfall 3: Prüfen des Manifests (`dl/downloads.txt`)
Öffne die Datei `dl/downloads.txt`. Du siehst dort die Liste aller benötigten Pakete mit aktuellem Status `PRESENT` oder `MISSING` sowie die genauen Befehle für PowerShell und cURL.

---

<a name="english"></a>
## 🇬🇧 English

This guide describes how to verify the download manager and manual package placement in `dl/`.

### How It Works
1. When starting `docker compose up -d`, `apex-download` checks `dl/` for required files.
2. If files like `apex_24.2.zip` are present, it skips downloading and uses them directly.
3. If files are missing, it downloads them and stores them in `dl/` on the host.
4. It maintains `dl/downloads.txt` with URLs and status.
