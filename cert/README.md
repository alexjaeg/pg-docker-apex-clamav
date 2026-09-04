# Eigene Stamm- & Unternehmenszertifikate / Custom CA Certificates (`cert/`)

[🇩🇪 Deutsch](#deutsch) | [🇬🇧 English](#english)

---

<a name="deutsch"></a>
## 🇩🇪 Deutsch

Lege in diesem Ordner alle zusätzlichen **Stamm- und Zwischenzertifikate (Root CA / Intermediate CA)** ab, denen die Container im Stack vertrauen sollen.

### Typische Anwendungsfälle:
1. **Corporate SSL/TLS Interception (Zero-Trust / Firmen-Proxys)**:
   - Web-Gateways (z. B. Zscaler, Fortinet, BlueCoat, Sophos, Palo Alto), die ausgehenden HTTPS-Traffic aufbrechen und mit einer firmeninternen CA neu signieren.
2. **Interne KI-Endpunkte (LiteLLM, Ollama, vLLM, Azure OpenAI on-premise)**:
   - Oracle APEX Generative AI Services oder `APEX_WEB_SERVICE`, die über HTTPS mit internen KI-Modell-Gateways sprechen, die interne oder selbstsignierte Zertifikate verwenden.
   - Verhindert in Oracle Database den Fehler: `ORA-29024: Certificate validation failure`.
3. **ClamAV Signatur-Updates (`freshclam`)**:
   - Ermöglicht dem Virenscanner, Updates über restriktive Firmen-Proxys herunterzuladen.

### Unterstützte Formate:
- Dateiendungen: `.crt`, `.pem`, `.cer`
- Format: **PEM (Base64-kodiert)**:
  ```text
  -----BEGIN CERTIFICATE-----
  MIIE...
  -----END CERTIFICATE-----
  ```

---

<a name="english"></a>
## 🇬🇧 English

Place any additional **Root CA, Intermediate CA, or custom TLS certificates** into this directory.

### Supported Use Cases:
1. **Corporate SSL Inspection / Zero-Trust Proxies** (Zscaler, Fortinet, etc.)
2. **Internal AI Endpoints** (LiteLLM, Ollama, private LLM servers called by APEX Generative AI / `APEX_WEB_SERVICE`)
3. **ClamAV Signature Updates** (`freshclam`)
