# Mobile Threat Intelligence Reference

## Known Mobile Spyware Families

### Nation-State / Commercial Spyware

| Family | Vendor | Network Indicators | Notes |
|--------|--------|-------------------|-------|
| Pegasus | NSO Group | Domain patterns vary per deployment; uses zero-click exploits; traffic often routed through anonymizing infrastructure; known to use AWS, Azure, OVH ranges | Most sophisticated. Can compromise iOS/Android without user interaction. Check MVT IOC lists. |
| Predator | Cytrox/Intellexa | Typosquatted domains mimicking legitimate services; one-click links via SMS/WhatsApp; infrastructure rotates frequently | Targets journalists and political figures. Often delivered via shortened URLs. |
| Hermit | RCS Lab | Known C2 domains documented by Lookout/Google TAG; masquerades as carrier or messaging apps; requests excessive permissions | Used by government clients. Delivered via ISP-level injection or social engineering. |
| FinFisher/FinSpy | Gamma Group | Connects to dedicated C2 infrastructure; uses certificate pinning; may use DNS tunneling for exfil | Legacy commercial spyware, still deployed in some regions. |
| Candiru | Candiru Ltd | Uses domains mimicking NGOs, news outlets, and activist organizations; infrastructure documented by Citizen Lab | Targets civil society. Domain names often reference human rights topics. |

### Commercial Stalkerware

These are consumer-grade surveillance apps. Lower sophistication but extremely common in domestic abuse scenarios.

| Family | Network Pattern |
|--------|----------------|
| mSpy | Connections to mspy.com, mspyonline.com; regular HTTP/HTTPS check-ins |
| FlexiSpy | Connections to flexispy.com infrastructure; uses custom binary protocol on non-standard ports in older versions |
| Cocospy | Connections to cocospy.com, minspy.com; newer variants use generic cloud infrastructure |
| Spyic | Connections to spyic.com; shares infrastructure with Cocospy family |
| KidsGuard Pro | Connections to clevguard.com, kidsguardpro.com; poses as system utility |
| TheTruthSpy | Connections to thetruthspy.com, copy9.com; poor OPSEC, has been breached multiple times |
| Cerberus | cerberusapp.com; marketed as anti-theft but commonly abused as stalkerware |

**Key indicator:** Any phone connecting to stalkerware control panels is likely compromised. Treat as HIGH severity regardless of Suricata rule severity.

### Mobile Banking Trojans / RATs

| Family | Network Pattern | Target |
|--------|----------------|--------|
| Vultur | Screen streaming over RTMP/custom protocol; uses ngrok/Cloudflare tunnels for C2 | Banking apps |
| Hook | Evolved from Ermac; uses WebSocket-based C2; DGA for domain generation | Banking + crypto wallets |
| GoldDigger | Vietnamese banking trojan; communicates over HTTPS to rotating infrastructure | Vietnamese bank apps |
| Anatsa/TeaBot | Dropper from Play Store; C2 over HTTPS with obfuscated JSON payloads | European banking apps |
| SharkBot | Uses DGA; auto-transfer system (ATS) to steal funds directly; domain patterns documented | Banking apps |
| Xenomorph | MaaS model; uses Telegram bots for C2; overlay attacks | Banking apps |

## Network Indicators Cheat Sheet

### Suspicious DNS Patterns

- **DGA (Domain Generation Algorithm)**: High-entropy domain names, random-looking strings, often under .com/.net/.org. Examples: `a8f3k2m9.com`, `xn7b4q2w.net`
- **DNS tunneling**: Very long subdomain labels (>30 chars), high query volume to a single domain, TXT record queries with encoded data
- **Fast flux**: Same domain resolving to many different IPs across short time windows
- **Newly registered domains**: Domains less than 30 days old contacting from a phone (requires external enrichment)
- **Suspicious TLDs for mobile**: `.top`, `.xyz`, `.tk`, `.ml`, `.ga`, `.cf` — commonly used by commodity malware

### Suspicious TLS Patterns

- **Self-signed certificates** to non-internal destinations
- **Certificate subject mismatch**: SNI doesn't match the certificate CN/SAN
- **Expired certificates** that the client accepts anyway
- **TLS 1.0 or 1.1** from a modern phone (should be 1.2+ for everything)
- **Known malicious JA3 hashes**: Cross-reference with ja3er.com or abuse.ch JA3 feed
- **Missing SNI**: TLS connections without Server Name Indication (uncommon for legitimate mobile apps)

### Suspicious Flow Patterns

- **Beaconing**: Regular-interval connections (e.g., every 60s, 300s, 3600s) to the same destination. Calculate inter-arrival time jitter — C2 often has low jitter.
- **Large upload, small download**: Potential data exfiltration. Normal mobile browsing is download-heavy.
- **Long-lived connections**: TCP connections lasting hours to non-streaming services
- **Non-standard ports**: Connections to high ports (>10000) on non-CDN infrastructure
- **Geographic anomalies**: Connections to countries the user has no relationship with (requires GeoIP enrichment)

## IOC Feed Sources

These are feeds the VPS should be pulling automatically via cron. When triaging, check if the destination IP/domain appears in any of these:

| Feed | URL | Type | Update Frequency |
|------|-----|------|-----------------|
| abuse.ch URLhaus | `https://urlhaus.abuse.ch/downloads/json_recent/` | Malware distribution URLs | Every 5 min |
| abuse.ch ThreatFox | `https://threatfox.abuse.ch/export/json/recent/` | IOCs (IP, domain, hash) | Every 10 min |
| abuse.ch SSLBL | `https://sslbl.abuse.ch/blacklist/ja3_fingerprints.csv` | Malicious JA3 hashes | Daily |
| Stalkerware IOCs | `https://raw.githubusercontent.com/Te-k/stalkerware-indicators/master/ioc.csv` | Stalkerware domains/IPs | Weekly |
| Phishing.Database | `https://raw.githubusercontent.com/mitchellkrogza/Phishing.Database/master/phishing-domains-ACTIVE.txt` | Active phishing domains | Daily |
| CertStream (suspicious issuance) | `https://certstream.calidog.io/` | Real-time CT log monitoring | Streaming |
| MVT IOCs | `https://github.com/mvt-project/mvt-indicators` | Pegasus/Predator/spyware IOCs | As published |

## Attribution Confidence Levels

When associating alerts with threat actors or malware families, explicitly state your confidence:

- **HIGH confidence**: Signature name directly references the family (e.g., "ET MALWARE Cobalt Strike Beacon"), or domain/IP matches a published IOC from a reputable source (Citizen Lab, Google TAG, ESET, Kaspersky, Amnesty Tech)
- **MEDIUM confidence**: Behavioral pattern matches known TTP (e.g., beaconing interval matches Cobalt Strike defaults), or JA3 hash matches known malware fingerprint
- **LOW confidence**: Generic signature fired, destination is suspicious but not in known IOC lists, pattern is anomalous but could be legitimate

**Never claim HIGH confidence attribution from behavioral patterns alone.** A beaconing pattern might match Cobalt Strike but could also be a legitimate app with a keep-alive mechanism.
