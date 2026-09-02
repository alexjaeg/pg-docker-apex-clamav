# Oracle APEX + ORDS + ClamAV + C-ICAP Docker Stack

[🇩🇪 Deutsch](README.md) | [🇬🇧 English](README_EN.md)

Vollständig automatisierte, containerisierte Umgebung für **Oracle Database 23ai Free**, **Oracle APEX 24.2**, **Oracle REST Data Services (ORDS) 24.3.0**, **ClamAV 1.4.3** und einen **C-ICAP Server** mit reinem TCP-Streaming, striktem Fail-Closed-Schutz und nativer Einbindung eigener Firmen- und KI-Zertifikate (Corporate CA / LiteLLM).

---

## 🌟 Highlights dieser Lösung

1. **Keine `latest`-Tags**: Alle Container-Images und Basis-Images sind auf konkrete, aktuelle und stabile Versionen gepinnt.
2. **Strikte Fail-Closed Sicherheit**: C-ICAP und ORDS sind so konfiguriert, dass Dateiuploads **ausnahmslos blockiert werden**, wenn ClamAV offline oder nicht erreichbar ist (`Threat=ClamAV-Scanner-Offline`).
3. **Eigene Zertifikate & KI-Unterstützung (Corporate CA & LiteLLM)**: Alle im Ordner [`cert/`](cert/) abgelegten Zertifikate (`.crt`, `.pem`, `.cer`) werden automatisch in alle 5 Container (Oracle DB 23ai, ORDS/Java, C-ICAP, ClamAV, Downloader) eingebunden. Damit funktionieren Unternehmens-Proxys (SSL-Interception) und interne KI-Endpunkte (z. B. LiteLLM, Ollama, Azure OpenAI) ohne Zertifikatsfehler (`ORA-29024` / `PKIX`).
4. **Horizontale Skalierbarkeit**: C-ICAP kommuniziert mit ClamAV **ausschließlich über das Netzwerk via TCP (Port 3310 / `INSTREAM`)** – es existieren keine gemeinsamen Dateisystem-Volumes zwischen C-ICAP und ClamAV.
5. **Vollautomatische Initialisierung mit einem Befehl**:
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
|      |  - Eigene CA-Zertifikate in Java-Keystore & OS integriert          |             |
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
|      |  - Shared CA-Bundle für KI/REST|                   |                             |
|      +--------------------------------+                   | TCP Stream (Port 3310)      |
|                                                           | (INSTREAM Protokoll)        |
|                                                           v                             |
|                                            +--------------+---------------+             |
|                                            |     ClamAV 1.4.3 Daemon      |             |
|                                            |  - Offizielles Image         |             |
|                                            |  - Signatur-Datenbank        |             |
|                                            |  - CA-Bundle für freshclam   |             |
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

### 2. Eigene Zertifikate hinterlegen (optional)
Wenn du hinter einem Unternehmens-Proxy arbeitest oder lokale KI-Dienste (LiteLLM, Ollama) anbindest:  
Kopiere deine `.crt`- oder `.pem`-Dateien einfach in den Ordner [`cert/`](cert/).

### 3. Stack starten
```bash
docker compose up -d
```

### 4. Was im Hintergrund automatisch abläuft:
1. **`apex-download`**: Lädt custom Zertifikate, baut das gemeinsame CA-Bundle für die Datenbank und lädt APEX 24.2 herunter.
2. **`clamav`**: Startet mit importierten CA-Zertifikaten (damit `freshclam` auch über Firmen-Proxys aktualisieren kann) und aktiviert detailliertes Logging (`LogClean=yes`).
3. **`c-icap`**: Baut das gepatchte `squidclamav`-Modul und verbindet sich via TCP mit ClamAV.
4. **`db`**: Startet Oracle Database 23ai Free mit dem erweiterten CA-Bundle. Führt `01_setup_users.sql` und `02_install_apex.sh` (silent APEX-Installation) aus.
5. **`ords`**: Importiert Zertifikate in den Java-Keystore (`cacerts`), richtet das PL/SQL-Gateway und die ICAP-Anbindung ein.

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

## 🧪 Tests & Verifikation

Ausführliche Anleitungen findest du im Ordner [**test/**](test/):

* [**test/test-clamav.md**](test/test-clamav.md): Virenscanner-Verifikation, Log-Nachverfolgung und Fail-Closed-Test bei gestopptem ClamAV.
* [**test/test-cert.md**](test/test-cert.md): Verifikation eigener Zertifikate (Corporate CA / LiteLLM / BadSSL) in Oracle DB 23ai, Java/ORDS und ClamAV.

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

## 🤖 Hinweis zu KI-generierten Inhalten

Dieses Projekt, seine Konfigurationen und die Integrationsskripte wurden unter Einsatz fortschrittlicher KI-Pair-Programming-Tools (Google Antigravity) entwickelt, getestet und verifiziert.

---

## 📄 Lizenz

Dieses Projekt ist unter der [MIT License](LICENSE) lizenziert. Du kannst den Code frei verwenden, anpassen und weitergeben. Es wird keinerlei Haftung oder Gewährleistung übernommen.
