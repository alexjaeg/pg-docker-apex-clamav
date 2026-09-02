# Testanleitung & Log-Verifikation (ClamAV & C-ICAP)

Diese Dokumentation beschreibt Schritt für Schritt, wie du Dateiuploads testen kannst und **in Echtzeit in den Logs nachverfolgst**, dass jede Datei durch **C-ICAP** und **ClamAV** geprüft wurde.

---

## 📊 Wo und wie sehe ich die Prüfungen in den Logs?

Jeder Dateiupload in Oracle APEX durchläuft die Kette:
$$\text{Browser} \longrightarrow \text{ORDS} \overset{\text{ICAP}}{\longrightarrow} \text{C-ICAP} \overset{\text{TCP INSTREAM}}{\longrightarrow} \text{ClamAV}$$

Du kannst die Prüfung an drei Stellen lückenlos nachvollziehen:

### 1. ClamAV Daemon Log (Direkter Scan-Beweis)
Im ClamAV-Container ist `LogClean=yes` und `LogVerbose=yes` aktiviert. ClamAV protokolliert **jeden einzelnen Stream-Scan**:

```bash
docker compose logs -f clamav
```

* **Saubere Datei**:
  ```text
  Wed Sep 2 20:26:49 2026 -> instream(172.18.0.4@45644): OK
  ```
  *(Bedeutet: C-ICAP hat die Bytes über TCP gestreamt und ClamAV hat sie als sauber freigegeben.)*
* **Virendatei (EICAR)**:
  ```text
  Wed Sep 2 20:26:55 2026 -> instream(172.18.0.4@58154): Eicar-Test-Signature FOUND
  ```

---

### 2. C-ICAP Server Log (Detaillierte Analyse)
Im C-ICAP Container siehst du die Verbindung zu ClamAV und die Entscheidung:

```bash
docker exec -it apex-c-icap tail -f /var/log/c-icap/server.log
```

* **Saubere Datei**:
  ```text
  DEBUG Connected to Clamd (clamav:3310)
  DEBUG Responding with allow 204
  ```
* **Virendatei (EICAR)**:
  ```text
  DEBUG Connected to Clamd (clamav:3310)
  LOG Virus found in (null) ending download [stream: Eicar-Test-Signature FOUND]
  LOG Virus found, sending redirection header / error page.
  ```
* **ClamAV ist offline (Fail-Closed Test)**:
  ```text
  ERROR Can't connect to Clamd daemon. Enforcing FAIL-CLOSED.
  LOG Virus found, sending redirection header / error page.
  ```

---

### 3. C-ICAP Access Log (Kompakte Transaktionsübersicht)
Das Access-Log listet jeden HTTP/ICAP-Vorgang kompakt auf:

```bash
docker exec -it apex-c-icap tail -f /var/log/c-icap/access.log
```

* **Code `204`**: Datei geprüft und sauber (keine Modifikation nötig, Upload erlaubt).
* **Code `200`**: Datei abgefangen und durch Block-Seite / `X-Infection-Found` ersetzt (Upload blockiert).

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
2. Lade eine Datei hoch (z. B. in einer APEX-Applikation oder über den SQL Workshop).
3. **Beobachtung in den Logs**:
   * ClamAV meldet: `instream(...): OK`
   * C-ICAP meldet: `RESPMOD ... 204`
   * Der Upload wird in APEX erfolgreich abgeschlossen.

---

### Test 2: Upload der EICAR-Testvirendatei (Blockiert)
1. Erstelle eine Datei `eicar.txt` mit folgendem Standard-Teststring:
   ```text
   X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
   ```
2. Versuche, diese Datei in APEX hochzuladen.
3. **Beobachtung in den Logs**:
   * ClamAV meldet: `instream(...): Eicar-Test-Signature FOUND`
   * C-ICAP generiert den Header:
     `X-Infection-Found: Type=0; Resolution=2; Threat=Eicar-Test-Signature;`
   * ORDS fängt den Header ab und wirft `InfectedFileException`.
   * **In APEX**: Der Upload bricht mit einem Fehler ab. Die Datei wird **nicht** in der Datenbank gespeichert!

---

### Test 3: Fail-Closed Test (ClamAV ausgeschaltet)
1. Stoppe den ClamAV-Container:
   ```powershell
   docker compose stop clamav
   ```
2. Versuche nun, eine **völlig harmlose, saubere Datei** in APEX hochzuladen.
3. **Ergebnis**:
   * C-ICAP erkennt den Verbindungsausfall zu ClamAV sofort.
   * C-ICAP erzwingt den Fail-Closed-Schutz und generiert:
     `X-Infection-Found: Type=0; Resolution=2; Threat=ClamAV-Scanner-Offline;`
   * ORDS erkennt die Bedrohungsmeldung und bricht den Upload sofort ab.
   * **Der Upload ist unmöglich, solange ClamAV nicht läuft!**
4. Starte ClamAV wieder:
   ```powershell
   docker compose start clamav
   ```
   Sobald ClamAV wieder läuft, funktionieren reguläre Uploads wieder.

---

## ⚡ Schneller Kommandozeilen-Test (Ohne Browser)

Du kannst alle drei Tests auch direkt per Befehl gegen C-ICAP ausführen:

```powershell
# 1. Saubere Datei prüfen
docker exec apex-c-icap c-icap-client -i 127.0.0.1 -p 1344 -s "AVSCAN" -f /etc/c-icap/c-icap.conf

# 2. EICAR-Virus prüfen
docker exec apex-c-icap sh -c "echo 'WDVPIVAlQEFQWzRcUFpYNTQoUF4pN0NDKTd9JEVJQ0FSLVNUQU5EQVJELUFOVElWSVJVUy1URVNULUZJTEUhJEgrSCo=' | base64 -d > /tmp/eicar.com && c-icap-client -i 127.0.0.1 -p 1344 -s 'AVSCAN' -f /tmp/eicar.com"

# 3. ClamAV stoppen und Fail-Closed verifizieren
docker stop apex-clamav
docker exec apex-c-icap c-icap-client -i 127.0.0.1 -p 1344 -s "AVSCAN" -f /etc/c-icap/c-icap.conf
docker start apex-clamav
```
