# MITRE ATT&CK Mobile Techniques Reference

Use these technique IDs when mapping alerts to ATT&CK. Focus on techniques that have **network-visible indicators** — these are what Suricata and flow analysis can actually detect.

## Network-Detectable Techniques

### Initial Access

| ID | Technique | What to look for in traffic |
|----|-----------|-----------------------------|
| T1660 | Phishing | DNS queries to typosquatted domains, newly registered domains, URL shortener redirects to credential harvesting pages |
| T1456 | Drive-By Compromise | Connections to known exploit kit domains, JavaScript redirector chains visible in HTTP traffic |
| T1474.001 | Supply Chain (app store) | Post-install C2 callbacks from apps that were recently installed (correlate timing with new connections) |

### Command and Control

| ID | Technique | What to look for in traffic |
|----|-----------|-----------------------------|
| T1071 | Application Layer Protocol | C2 over HTTP/HTTPS/DNS — look for beaconing patterns, unusual User-Agents, POST-heavy traffic to single domains |
| T1071.001 | Web Protocols | HTTP/HTTPS C2 — structured beacon responses, encoded payloads in URL parameters or POST bodies |
| T1071.004 | DNS | DNS-based C2 — TXT queries with encoded data, high-entropy subdomain labels, abnormal query volume to single domain |
| T1573 | Encrypted Channel | TLS to non-standard ports, self-signed certs, known malicious JA3 hashes, certificate pinning bypass attempts |
| T1573.002 | Asymmetric Cryptography | Custom TLS implementations with unusual cipher suites, non-standard key exchange |
| T1571 | Non-Standard Port | HTTPS on ports other than 443, HTTP on non-80 ports, especially high ports (>8000) |
| T1572 | Protocol Tunneling | DNS tunneling (long subdomain labels), ICMP tunneling, HTTP CONNECT to unusual destinations |
| T1090 | Proxy | Connections through known proxy/anonymizer infrastructure (Tor, VPN services, residential proxies) |
| T1102 | Web Service | C2 via legitimate platforms (Telegram API, Discord webhooks, Google Docs, Pastebin, GitHub raw) |

### Collection

| ID | Technique | What to look for in traffic |
|----|-----------|-----------------------------|
| T1429 | Audio Capture | Large upload volumes from a device that should be idle; streaming protocols (RTMP) to unknown destinations |
| T1512 | Video Capture | Same as audio but higher bandwidth; RTMP/RTSP streams |
| T1430 | Location Tracking | Connections to stalkerware control panels; periodic small POST requests containing GPS-sized payloads |
| T1636.001 | Contact List | Bulk data upload events shortly after app installation |
| T1636.002 | Call Log | Similar to contact list exfil — small structured data uploads |
| T1636.003 | SMS Messages | Periodic uploads to known stalkerware/spyware infrastructure |
| T1636.004 | Photos/Media | Large upload volumes to non-standard cloud destinations |
| T1417 | Input Capture (Keylogging) | Frequent small uploads (keystroke buffers) to C2; may use WebSocket for real-time streaming |

### Exfiltration

| ID | Technique | What to look for in traffic |
|----|-----------|-----------------------------|
| T1048 | Exfiltration Over Alternative Protocol | Data leaving via DNS TXT records, ICMP payloads, or non-HTTP protocols |
| T1048.003 | Over Unencrypted Protocol | Cleartext data transfer (HTTP POST with structured data, FTP uploads) |
| T1646 | Exfiltration Over C2 Channel | Upload spikes to known C2 destinations — most common mobile exfil pattern |
| T1567 | Exfiltration to Cloud Storage | Uploads to cloud storage APIs (S3, GCS, Azure Blob, Dropbox, Google Drive) from unexpected apps |

### Defense Evasion

| ID | Technique | What to look for in traffic |
|----|-----------|-----------------------------|
| T1521 | Encrypted/Obfuscated Data | High-entropy payloads in HTTP traffic, base64-encoded POST bodies to non-API destinations |
| T1617 | Hooking | Connections to package repositories or update servers that don't match the device OS |
| T1630.002 | Indicator Removal (File Deletion) | Not directly network-visible, but C2 commands to "clean up" may be visible in decoded C2 traffic |

## Mapping Rules to ATT&CK

When Suricata fires a rule, map it to ATT&CK using these heuristics:

1. **Check rule metadata first.** Many ET rules include `metadata: mitre_tactic ..., mitre_technique ...` fields. Use these directly.
2. **Parse the signature name.** Keywords in the name often map directly:
   - "CnC", "C2", "Beacon" → T1071 (Application Layer Protocol)
   - "DNS Tunnel" → T1071.004 (DNS)
   - "Exfil" → T1048 (Exfiltration Over Alternative Protocol)
   - "Phish" → T1660 (Phishing)
   - "Credential" → T1417 (Input Capture) or T1660 (Phishing)
3. **Consider the protocol.** DNS alert → likely T1071.004. TLS alert → likely T1573. HTTP alert → likely T1071.001.
4. **Don't force a mapping.** If the technique isn't clear, omit the MITRE reference rather than guessing wrong. An incorrect mapping is worse than none.

## Kill Chain Positioning

When multiple alerts fire from the same device in a short window, try to map them to kill chain stages to assess how far an attack has progressed:

```
Initial Access → Execution → Persistence → C2 Established → Collection → Exfiltration
     (early)                                                              (late/critical)
```

- Alerts in **early stages** (DNS to phishing domains) → warn but don't panic
- Alerts in **C2 stage** (beaconing, known C2 infrastructure) → HIGH priority, device likely compromised
- Alerts in **collection/exfil stage** (large uploads, DNS tunneling) → CRITICAL, active data theft

If you see alerts spanning multiple kill chain stages from the same device, escalate to CRITICAL regardless of individual alert severity — this suggests an active, progressing compromise.
