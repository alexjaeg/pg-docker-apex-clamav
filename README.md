# Oracle APEX + ORDS + ClamAV + C-ICAP Docker Stack

[🇩🇪 Deutsch](README.md) | [🇬🇧 English](README_EN.md)

Vollständig automatisierte, containerisierte Umgebung für **Oracle Database 23ai Free**, **Oracle APEX 24.2**, **Oracle REST Data Services (ORDS) 24.3.0**, **ClamAV 1.4.3** und einen **C-ICAP Server** mit reinem TCP-Streaming und striktem Fail-Closed-Schutz.

---

## 🌟 Highlights dieser Lösung

1. **Keine `latest`-Tags**: Alle Container-Images und Basis-Images sind auf konkrete, aktuelle und stabile Versionen gepinnt.
2. **Strikte Fail-Closed Sicherheit**: C-ICAP und ORDS sind so konfiguriert, dass Dateiuploads **ausnahmslos blockiert werden**, wenn ClamAV offline oder nicht erreichbar ist (`Threat=ClamAV-Scanner-Offline`).
3. **Horizontale Skalierbarkeit**: C-ICAP kommuniziert mit ClamAV **ausschließlich über das Netzwerk via TCP (Port 3310 / `INSTREAM`)** – es existieren keine gemeinsamen Dateisystem-Volumes zwischen C-ICAP und ClamAV.
4. **Vollautomatische Initialisierung mit einem Befehl**:
   - Die Datenbank initialisiert sich selbst (`gvenzl/oracle-free:23.5-slim-faststart`).
   - APEX lädt sich automatisch herunter und installiert sich silent in die Pluggable Database (`FREEPDB1`).
   - Der Demo-Workspace (`DEMO`) und der Administrator-User (`DEMO_ADMIN`) werden vollautomatisch angelegt.
   - ORDS richtet die Schemas und die ICAP-Virenscanner-Integration automatisch ein.
   - Alle Passwörter und Ports werden zentral über die Datei `.env` gesteuert.

---

## 🏗️ Architektur

```
                                  +-----------------------+
                                  |     Web-Browser       |
                                  +-----------+-----------+
                                              | HTTP (8080)
                                              v
+-----------------------------------------------------------------------------------------+
| Docker-Compose Netzwerk: apex_clamav_network                                            |
|                                                                                         |
|      +--------------------------------------------------------------------+             |
|      |               ORDS 24.3.0 (Oracle REST Data Services)              |             |
|      |  - Gateway-Proxy für APEX                                          |             |
|      |  - ICAP-Client: leitet Uploads vor DB-Speicherung an C-ICAP weiter |             |
|      +---------------------+------------------------------+---------------+             |
|                            |                              |                             |
|          JDBC (Port 1521)  |                              | ICAP (Port 1344)            |
|                            v                              v                             |
|      +---------------------+----------+    +--------------+---------------+             |
|      |    Oracle DB 23ai Free         |    |      C-ICAP Server           |             |
|      |    (23.5-slim-faststart)       |    |      (debian:12.9-slim)      |             |
|      |  - PDB: FREEPDB1               |    |  - Dienst: AVSCAN            |             |
|      |  - APEX 24.2 vorinstalliert    |    |  - TCP-Streaming             |             |
|      |  - Workspace: DEMO             |    +--------------+---------------+             |
|      +--------------------------------+                   |                             |
|                                                           | TCP Stream (Port 3310)      |
|                                                           | (INSTREAM Protokoll)        |
|                                                           v                             |
|                                            +--------------+---------------+             |
|                                            |     ClamAV 1.4.3 Daemon      |             |
|                                            |  - Offizielles Image         |             |
|                                            |  - Signatur-Datenbank        |             |
|                                            +------------------------------+             |
+-----------------------------------------------------------------------------------------+
```

---

## 📦 Komponenten & Versionen

| Komponente | Image / Basis | Version | Rolle |
| :--- | :--- | :--- | :--- |
| **ClamAV** | `clamav/clamav:1.4.3` | `1.4.3` (LTS) | Offizieller Virenscanner-Dienst |
| **C-ICAP** | `custom-c-icap:debian-12.9` | `debian:12.9-slim` | ICAP-Server mit TCP-Streaming (`squidclamav 7.3`) |
| **Oracle DB** | `gvenzl/oracle-free:23.5-slim-faststart` | `23.5` | Oracle Database 23ai Free |
| **Oracle APEX** | Oracle CDN Archive | `24.2` | Low-Code Plattform |
| **ORDS** | `container-registry.oracle.com/database/ords:24.3.0` | `24.3.0` | Webserver & ICAP-Gateway |

---

## 🚀 Schnellstart (In 1 Schritt hochfahren)

### 1. Umgebungsvariablen anpassen (optional)
Kopiere die Vorlage `.env.example` nach `.env` und passe bei Bedarf Passwörter an:
```bash
cp .env.example .env
```

### 2. Stack starten
```bash
docker compose up -d
```

### 3. Was im Hintergrund automatisch abläuft:
1. **`apex-download`**: Lädt die offizielle APEX 24.2 Distribution herunter und entpackt sie in das Volume `apex_software_files`.
2. **`clamav`**: Startet den ClamAV-Daemon und öffnet den TCP-Port 3310 mit detailliertem Logging (`LogClean=yes`).
3. **`c-icap`**: Baut den C-ICAP-Container mit dem gepatchten `squidclamav`-Modul und verbindet sich via TCP mit ClamAV.
4. **`db`**: Startet Oracle Database 23ai Free. Führt beim ersten Start automatisch das Schema `DEMO` und die Tabelle `DEMO_FILES` ein sowie die vollständige Installation von APEX 24.2 in `FREEPDB1` mit dem Workspace `DEMO` und Benutzer `DEMO_ADMIN`.
5. **`ords`**: Konfiguriert das PL/SQL-Gateway, aktiviert die ICAP-Anbindung (`c-icap:1344`) und bindet die APEX-Bilder (`/i/`) ein.

> **Hinweis zur Erstinstallation**:  
> Die erstmalige Installation von APEX in die Datenbank benötigt beim ersten Start ca. **3 bis 5 Minuten**.  
> Den Status kannst du live mitverfolgen:
> ```bash
> docker compose logs -f db ords
> ```

---

## 🔑 Zugangsdaten & URLs

Alle Zugangsdaten werden aus der Datei `.env` geladen (Vorlage: `.env.example`):

| Dienst | URL / Verbindung | Workspace | Benutzername | Passwort |
| :--- | :--- | :--- | :--- | :--- |
| **APEX Workspace** | `http://localhost:8080/ords` | `DEMO` | `DEMO_ADMIN` | `DemoPassword123!4` |
| **APEX Internal Admin**| `http://localhost:8080/ords/apex_admin` | `INTERNAL` | `ADMIN` | `Welcome12345!2` |
| **Oracle Database** | `localhost:1521/freepdb1` | - | `SYS AS SYSDBA` | `Welcome12345!1` |
| **Demo Schema** | `localhost:1521/freepdb1` | - | `DEMO` | `DemoPassword123!4` |

---

## 🧪 Virenscanner & Dateiupload testen

Eine ausführliche Anleitung mit allen Log-Befehlen findest du in [**`test.md`**](test.md).

### Schnellübersicht der Testfälle:

* **Testfall 1: Saubere Datei**: Wird sofort von ClamAV geprüft (`instream: OK`), C-ICAP liefert `204 No modification needed` und der Upload wird akzeptiert.
* **Testfall 2: EICAR-Testvirus**: Wird abgefangen (`Eicar-Test-Signature FOUND`), C-ICAP sendet `X-Infection-Found`, ORDS bricht den Upload ab und die Datei gelangt nicht in die Datenbank.
* **Testfall 3: Fail-Closed (ClamAV offline)**:
  ```bash
  docker compose stop clamav
  ```
  Versuchst du nun eine Datei hochzuladen, meldet C-ICAP `Threat=ClamAV-Scanner-Offline`. ORDS bricht den Upload sofort ab. **Kein Upload an ClamAV vorbei möglich!**

---

## 🧹 Komplett löschen und neu aufsetzen

Wenn du für Tests alles auf Anfang zurücksetzen möchtest:

```bash
# 1. Alle Container und Volumes vollständig entfernen (-v löscht alle Datenbanken und Daten)
docker compose down -v

# 2. Mit einem einzigen Befehl alles komplett neu initialisieren:
docker compose up -d
```

---

## 📈 Horizontale Skalierung von ClamAV

Da C-ICAP keine gemeinsamen Dateisystem-Volumes mit ClamAV nutzt, sondern Streaming über TCP einsetzt, kannst du ClamAV bei hohem Durchsatz problemlos horizontal skalieren:
1. Mehrere ClamAV-Container hinter einem internen Load-Balancer oder Docker DNS Round-Robin betreiben.
2. In `c-icap/squidclamav.conf` können auch mehrere Backends kommagetrennt eingetragen werden (`clamd_ip host1,host2`).

---

## 🤖 Hinweis zu KI-generierten Inhalten

Dieses Projekt, seine Konfigurationen und die Integrationsskripte wurden unter Einsatz fortschrittlicher KI-Pair-Programming-Tools (Google Antigravity) entwickelt, getestet und verifiziert.

---

## 📄 Lizenz

Dieses Projekt ist unter der [MIT License](LICENSE) lizenziert. Du kannst den Code frei verwenden, anpassen und weitergeben. Es wird keinerlei Haftung oder Gewährleistung übernommen.
