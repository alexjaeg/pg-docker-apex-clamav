# Testanleitung & Verifikation: Eigene Zertifikate (Corporate CA & LiteLLM)

[🇩🇪 Deutsch](#deutsch) | [🇬🇧 English](#english)

---

<a name="deutsch"></a>
## 🇩🇪 Deutsch

Diese Dokumentation beschreibt, wie du die Einbindung eigener Zertifikate (Corporate Root CAs, SSL-Interception-Proxys oder selbstsignierte Zertifikate von z. B. LiteLLM / Ollama) testest und verifizierst.

---

## 🎯 Das Problem in Unternehmensnetzwerken

In vielen Firmenumgebungen tritt eines oder mehrere der folgenden Szenarien auf:
1. **Corporate SSL/TLS Interception**:
   - Web-Gateways (Zscaler, Fortinet, BlueCoat, Sophos) brechen ausgehenden HTTPS-Traffic auf und signieren ihn mit einer unternehmensinternen Root-CA neu.
   - Ohne diese Root-CA schlagen Downloads (APEX-Downloader, ClamAV-Signatur-Updates via `freshclam`) mit SSL-Fehlern fehl.
2. **KI-Anbindung in Oracle APEX (z. B. LiteLLM / Ollama / Private LLM)**:
   - Oracle APEX Generative AI Services und `APEX_WEB_SERVICE` kommunizieren über HTTPS mit internen KI-Gateways (wie LiteLLM).
   - Verwenden diese interne oder selbstsignierte Zertifikate, bricht Oracle Database mit folgendem Fehler ab:
     ```text
     ORA-29273: HTTP request failed
     ORA-29024: Certificate validation failure
     ```
3. **ORDS / Java REST-Verbindungen**:
   - Java wirft ohne das CA-Zertifikat den bekannten Fehler:
     ```text
     PKIX path building failed: SunCertPathBuilderException: unable to find valid certification path to requested target
     ```

---

## 🛠️ Wie die automatische Lösung funktioniert

Alle Zertifikate (`.crt`, `.pem`, `.cer`), die du in den Ordner [`cert/`](../cert/) legst, werden beim Start automatisch in alle Container eingebunden:

| Container | Verwendete Technologie | Ziel-Truststore |
| :--- | :--- | :--- |
| **`db` (Oracle 23ai & APEX)** | Shared CA Bundle | `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem` |
| **`ords` (Java & Web)** | `keytool` & `update-ca-trust` | `$JAVA_HOME/lib/security/cacerts` & OS-Truststore |
| **`clamav` (Virenscanner)** | Alpine OpenSSL Bundle | `/etc/ssl/certs/ca-certificates.crt` |
| **`c-icap`** | `update-ca-certificates` | `/usr/local/share/ca-certificates/` |
| **`apex-download`** | `update-ca-certificates` | System-Truststore für `curl` |

---

## 🧪 Praktische Testmöglichkeiten

### Testfall 1: Verifikation in Oracle Database (APEX / LiteLLM Simulation)

Wir testen die Zertifikatsvalidierung in Oracle Database 23ai anhand eines selbstsignierten Endpunkts (z. B. `self-signed.badssl.com` oder dein lokaler LiteLLM-Server):

#### Schritt 1: Ausgangszustand testen (Schlägt fehl)
Führe folgenden SQL-Befehl in der Datenbank aus:

```powershell
@"
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT utl_http.request('https://self-signed.badssl.com') FROM dual;
exit;
"@ | docker exec -i apex-oracle-db sqlplus -s / as sysdba
```

**Erwartetes Ergebnis**:
```text
ORA-29273: HTTP request failed
ORA-29024: Certificate validation failure
```
*(Die Datenbank verweigert die Verbindung, da sie dem Zertifikat nicht vertraut.)*

---

#### Schritt 2: Zertifikat in den Ordner `cert/` ablegen
Hole das Zertifikat des Endpunkts und speichere es im Ordner `cert/`:

```powershell
# Beispiel: Zertifikat von badssl.com holen und als PEM ablegen
docker run --rm debian:12.9-slim bash -c "
apt-get update -qq && apt-get install -y -qq openssl >/dev/null
openssl s_client -showcerts -connect self-signed.badssl.com:443 </dev/null 2>/dev/null | openssl x509 -outform PEM
" > cert/badssl-selfsigned.crt
```

*(Für dein eigenes Firmenzertifikat oder LiteLLM kopierst du einfach deine `my-company-ca.crt` oder `litellm.crt` in den Ordner `cert/`.)*

---

#### Schritt 3: Stack neu starten
```powershell
docker compose up -d
```

---

#### Schritt 4: Erneut testen (Erfolgreich!)
Führe die Abfrage erneut aus:

```powershell
@"
ALTER SESSION SET CONTAINER = FREEPDB1;
SELECT utl_http.request('https://self-signed.badssl.com') FROM dual;
exit;
"@ | docker exec -i apex-oracle-db sqlplus -s / as sysdba
```

**Erwartetes Ergebnis**:
Die HTML-Antwort wird **sofort und fehlerfrei** zurückgegeben! Kein `ORA-29024` mehr!

---

### Testfall 2: Verifikation im Java Keystore von ORDS

Prüfe, ob ORDS das Zertifikat automatisch in den Java-Keystore importiert hat:

```powershell
docker exec apex-ords keytool -list -keystore /opt/graalvm-ee-java17-21.3.10/lib/security/cacerts -storepass changeit | Select-String "custom-"
```

**Erwartete Ausgabe**:
```text
custom-badssl-selfsigned-crt, 02.09.2026, trustedCertEntry,
```
*(Das Zertifikat ist als vertrauenswürdiges CA-Zertifikat in Java hinterlegt.)*

---

### Testfall 3: Verifikation in ClamAV (Freshclam)

Prüfe die Logs von ClamAV beim Start:

```powershell
docker compose logs clamav
```

**Erwartete Ausgabe**:
```text
[ClamAV] Found 1 custom certificate(s) in /cert. Importing into CA bundle...
[ClamAV] Appending badssl-selfsigned.crt to /etc/ssl/certs/ca-certificates.crt...
[ClamAV] CA bundle updated successfully.
```

---

<a name="english"></a>
## 🇬🇧 English

This guide describes how to verify custom SSL/TLS certificates (Corporate Root CAs, SSL interception proxies, or internal self-signed endpoints such as LiteLLM / Ollama).

### How It Works
Any `.crt`, `.pem`, or `.cer` files placed into [`cert/`](../cert/) are mounted and automatically imported into all container trust stores upon startup.

### Quick Verification Steps

#### 1. Test Oracle DB & APEX HTTPS Calls
```bash
# Test call before adding certificate (fails with ORA-29024)
echo "SELECT utl_http.request('https://self-signed.badssl.com') FROM dual;" | docker exec -i apex-oracle-db sqlplus -s sys/Welcome12345!1@localhost:1521/freepdb1 as sysdba

# Copy certificate to ./cert/
cp my-ca.crt cert/

# Restart stack
docker compose up -d

# Re-run call (succeeds without errors!)
echo "SELECT utl_http.request('https://self-signed.badssl.com') FROM dual;" | docker exec -i apex-oracle-db sqlplus -s sys/Welcome12345!1@localhost:1521/freepdb1 as sysdba
```

#### 2. Verify ORDS Java Keystore
```bash
docker exec apex-ords keytool -list -keystore /opt/graalvm-ee-java17-21.3.10/lib/security/cacerts -storepass changeit | grep custom-
```

#### 3. Verify ClamAV Bundle
```bash
docker compose logs clamav | grep -E 'ClamAV.*cert'
```
