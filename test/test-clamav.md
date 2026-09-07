# Testanleitung & Log-Verifikation (ClamAV & ICAP-Service)

Diese Dokumentation beschreibt Schritt für Schritt, wie du Dateiuploads testen kannst und **in Echtzeit in den Logs nachverfolgst**, dass jede Datei durch den **ICAP-Service** und **ClamAV** geprüft wurde.

---

## 📊 Wo und wie sehe ich die Prüfungen in den Logs?

Jeder Dateiupload in Oracle APEX durchläuft die Kette:
$$\text{Browser} \longrightarrow \text{ORDS} \overset{\text{ICAP}}{\longrightarrow} \text{ICAP-Service} \overset{\text{TCP INSTREAM}}{\longrightarrow} \text{ClamAV}$$

Du kannst die Prüfung lückenlos nachvollziehen:

### 1. ClamAV Daemon Log (Direkter Scan-Beweis)
Im ClamAV-Container ist `LogClean=yes` und `LogVerbose=yes` aktiviert. ClamAV protokolliert **jeden einzelnen Stream-Scan**:

```bash
docker compose logs -f clamav
```

* **Saubere Datei**:
  ```text
  instream(172.18.0.4@...): OK
  ```
  *(Bedeutet: Der ICAP-Service hat die Bytes über TCP gestreamt und ClamAV hat sie als sauber freigegeben.)*
* **Virendatei (EICAR)**:
  ```text
  instream(172.18.0.4@...): Eicar-Test-Signature FOUND
  ```

---

### 2. ICAP-Service Log (Echtzeit-Entscheidung)
Im Container des ICAP-Services (`c-icap`) siehst du jeden Scan-Vorgang und die Fail-Closed-Entscheidung:

```bash
docker compose logs -f c-icap
```

* **Saubere Datei**:
  ```text
  [INFO] [ICAP-Server] ClamAV scan completed (2150 bytes). Response: stream: OK
  [INFO] [ICAP-Server] Scan result: CLEAN (Threat: None)
  ```
  *(Antwortet mit `ICAP/1.0 204 No Content` -> Upload in APEX erlaubt)*
* **Virendatei (EICAR)**:
  ```text
  [INFO] [ICAP-Server] ClamAV scan completed (68 bytes). Response: stream: Eicar-Test-Signature FOUND
  [INFO] [ICAP-Server] Scan result: INFECTED (Threat: Eicar-Test-Signature)
  ```
  *(Antwortet mit `ICAP/1.0 200 OK` + `X-Infection-Found: Threat=Eicar-Test-Signature` + `HTTP 403 Forbidden` -> ORDS bricht Upload ab)*
* **ClamAV ist offline (Fail-Closed Test)**:
  ```text
  [ERROR] [ICAP-Server] Cannot connect to ClamAV daemon at clamav:3310: ...
  [INFO] [ICAP-Server] Scan result: ERROR (Threat: ClamAV-Scanner-Offline)
  ```
  *(Erzwingt sofort `X-Infection-Found: Threat=ClamAV-Scanner-Offline` + `HTTP 403 Forbidden` -> Upload blockiert)*

---

## 🧪 Die 3 Testfälle zum Nachstellen

Öffne ein Terminal für die Live-Logs und führe die Tests durch:

### Terminal 1: Live-Logs mitlesen
```powershell
docker compose logs -f clamav c-icap
```

---

### Test 1: Upload einer sauberen Datei (Erfolgreich)
1. Melde dich in APEX an: `http://localhost:8080/ords`
   * **Workspace**: `DEMO`
   * **User**: `DEMO_ADMIN`
   * **Passwort**: `DemoPassword123!4`
2. Lade eine beliebige Datei hoch.
3. **Beobachtung in den Logs**:
   * ClamAV meldet: `instream(...): OK`
   * ICAP meldet: `Scan result: CLEAN`
   * Der Upload wird in APEX erfolgreich abgeschlossen.

---

### Test 2: Upload der EICAR-Testvirendatei (Blockiert)
1. Erstelle eine Testdatei `eicar.txt` mit folgendem Inhalt:
   ```text
   X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
   ```
2. Versuche, diese Datei in APEX hochzuladen.
3. **Beobachtung in den Logs**:
   * ClamAV meldet: `instream(...): Eicar-Test-Signature FOUND`
   * ICAP generiert:
     `X-Infection-Found: Type=0; Resolution=2; Threat=Eicar-Test-Signature;`
   * ORDS bricht den Upload mit `HTTP 403 Forbidden` ab.
   * **In APEX**: Die Datei wird **nicht** in der Datenbank gespeichert!

---

### Test 3: Fail-Closed Test (ClamAV ausgeschaltet)
1. Stoppe den ClamAV-Container:
   ```powershell
   docker compose stop clamav
   ```
2. Versuche nun, eine **völlig harmlose, saubere Datei** in APEX hochzuladen.
3. **Ergebnis**:
   * ICAP erkennt den Ausfall von ClamAV sofort.
   * ICAP erzwingt den Fail-Closed-Schutz und generiert:
     `X-Infection-Found: Type=0; Resolution=2; Threat=ClamAV-Scanner-Offline;`
   * ORDS bricht den Upload sofort ab.
   * **Dateiuploads sind strikt verboten, solange ClamAV nicht erreichbar ist!**
4. Starte ClamAV wieder:
   ```powershell
   docker compose start clamav
   ```

---

## ⚡ Schneller Kommandozeilen-Test (Ohne Browser)

Du kannst alle drei Tests direkt über PowerShell ausführen:

```powershell
# 1. Saubere Datei prüfen (Antwort: ICAP/1.0 204 No Content)
python -c "
import socket
s = socket.create_connection(('127.0.0.1', 1344), timeout=5)
http = b'POST /ords/test HTTP/1.1\r\nHost: localhost\r\n\r\n'
body = b'Clean file test'
chunk = f'{len(body):x}\r\n'.encode() + body + b'\r\n0\r\n\r\n'
s.sendall(f'REQMOD icap://127.0.0.1:1344/avscan ICAP/1.0\r\nHost: 127.0.0.1\r\nAllow: 204\r\nEncapsulated: req-hdr=0, req-body={len(http)}\r\n\r\n'.encode('latin1') + http + chunk)
print(s.recv(1024).decode('latin1').split('\r\n')[0])
s.close()
"

# 2. EICAR-Virus prüfen (Antwort: 403 Forbidden & Threat=Eicar-Test-Signature)
python -c "
import socket, base64
s = socket.create_connection(('127.0.0.1', 1344), timeout=5)
http = b'POST /ords/test HTTP/1.1\r\nHost: localhost\r\n\r\n'
eicar = base64.b64decode('WDVPIVAlQEFQWzRcUFpYNTQoUF4pN0NDKTd9JEVJQ0FSLVNUQU5EQVJELUFOVElWSVJVUy1URVNULUZJTEUhJEgrSCo=')
chunk = f'{len(eicar):x}\r\n'.encode() + eicar + b'\r\n0\r\n\r\n'
s.sendall(f'REQMOD icap://127.0.0.1:1344/avscan ICAP/1.0\r\nHost: 127.0.0.1\r\nAllow: 204\r\nEncapsulated: req-hdr=0, req-body={len(http)}\r\n\r\n'.encode('latin1') + http + chunk)
print(s.recv(4096).decode('latin1'))
s.close()
"

# 3. Fail-Closed verifizieren (ClamAV gestoppt)
docker stop apex-clamav
python -c "
import socket
s = socket.create_connection(('127.0.0.1', 1344), timeout=5)
http = b'POST /ords/test HTTP/1.1\r\nHost: localhost\r\n\r\n'
body = b'Clean file while offline'
chunk = f'{len(body):x}\r\n'.encode() + body + b'\r\n0\r\n\r\n'
s.sendall(f'REQMOD icap://127.0.0.1:1344/avscan ICAP/1.0\r\nHost: 127.0.0.1\r\nAllow: 204\r\nEncapsulated: req-hdr=0, req-body={len(http)}\r\n\r\n'.encode('latin1') + http + chunk)
print(s.recv(4096).decode('latin1'))
s.close()
"
docker start apex-clamav
```
