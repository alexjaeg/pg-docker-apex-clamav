# Eigene Zertifikate / Custom Certificates (CA Trust Store)

[🇩🇪 Deutsch](#deutsch) | [🇬🇧 English](#english)

---

<a name="deutsch"></a>
## 🇩🇪 Deutsch

Lege in diesem Ordner alle zusätzlichen **Stamm- und Zwischenzertifikate (Root CA / Intermediate CA)** ab, denen die Container im Stack vertrauen sollen.

### Typische Anwendungsfälle:
1. **Corporate SSL/TLS Interception**:
   - Unternehmens-Proxys (z. B. Zscaler, BlueCoat, Fortinet, Sophos, Palo Alto), die HTTPS-Traffic aufbrechen und mit einer internen Firmen-CA neu signieren.
2. **Lokale & interne KI-Endpunkte (LiteLLM, Ollama, vLLM, Azure OpenAI)**:
   - APEX-Generative-AI-Dienste oder `APEX_WEB_SERVICE`, die mit internen HTTPS-Servern kommunizieren, welche selbstsignierte oder unternehmensinterne Zertifikate verwenden.
3. **Restriktive Firmennetze**:
   - Virendefinitions-Updates von ClamAV (`freshclam`) oder Downloads der APEX-Software über Firmen-Gateways.

### Unterstützte Formate:
- Dateiendungen: `.crt`, `.pem`, `.cer`
- Format: **PEM (Base64-kodiert)**, z. B.:
  ```text
  -----BEGIN CERTIFICATE-----
  MIIE...
  -----END CERTIFICATE-----
  ```

### Wie funktioniert die automatische Einbindung?
Beim Start jedes Containers werden alle Zertifikate aus diesem Ordner automatisch importiert:
- **Oracle Database 23ai & APEX**: System-Truststore (`update-ca-trust`) + Oracle Auto-Login Wallet (`orapki`).
- **ORDS (Java)**: System-Truststore + Java Keystore (`cacerts` via `keytool`).
- **C-ICAP**: Debian System-Truststore (`update-ca-certificates`).
- **ClamAV**: CA-Bundle `/etc/ssl/certs/ca-certificates.crt` für `freshclam`.
- **APEX-Downloader**: System-Truststore für den initialen Download via `curl`.

---

<a name="english"></a>
## 🇬🇧 English

Place any additional **Root CA or Intermediate CA certificates** into this directory to have all containers in the stack trust them.

### Common Use Cases:
1. **Corporate SSL/TLS Inspection**:
   - Enterprise interception proxies (e.g. Zscaler, Fortinet, BlueCoat) that terminate and re-sign outbound HTTPS traffic.
2. **Internal AI Endpoints (LiteLLM, Ollama, vLLM, Private OpenAI)**:
   - Oracle APEX Generative AI features or `APEX_WEB_SERVICE` calling internal HTTPS APIs using self-signed or enterprise CA certs.
3. **Restricted Networks**:
   - ClamAV signature updates (`freshclam`) or APEX installer downloads via corporate proxies.

### Supported Formats:
- Extensions: `.crt`, `.pem`, `.cer`
- Format: **PEM (Base64 encoded ASCII)**
