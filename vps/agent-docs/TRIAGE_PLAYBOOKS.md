# Triage Playbooks

Step-by-step analysis procedures for common alert categories. Follow the relevant playbook when you encounter each alert type.

## Playbook 1: DNS Alert (Suspicious Domain)

**Triggers:** ET DNS, ET CNC, DNS IOC match, DGA detection, demo rules 9999901/9999902

**Steps:**

1. Extract the queried domain from `dns.query.rrname` or from the alert payload
2. Check if the domain appears in local IOC feeds (stalkerware-indicators, abuse.ch, MVT indicators)
3. Assess domain characteristics:
   - Entropy: High-entropy random strings suggest DGA
   - TLD: `.top`, `.xyz`, `.tk`, `.ml` are higher risk
   - Age: Reference WHOIS if available — domains under 30 days old are suspicious
   - Pattern: Does it mimic a legitimate domain? (typosquatting)
4. Check if this device has queried this domain before (search historical eve.json)
5. Look for associated TLS/flow events with the same `flow_id`
6. Assess the resolved IP — is it in a hosting range known for bulletproof hosting?
7. Determine if this is a one-off or part of a pattern (beaconing to same domain)

**Severity guidance:**
- Domain matches known spyware/stalkerware IOC → CRITICAL
- Domain matches known malware C2 → HIGH
- DGA-like domain with no IOC match → MEDIUM (could be CDN subdomain)
- Known ad/tracker domain → LOW (usually noise)

## Playbook 2: TLS Alert (Certificate/JA3 Anomaly)

**Triggers:** ET TLS, SSLBL JA3 match, self-signed cert alerts, certificate mismatch

**Steps:**

1. Extract JA3 hash from `tls.ja3.hash`
2. Check against abuse.ch SSLBL JA3 blacklist
3. If no JA3 match, examine the certificate:
   - Self-signed? → Suspicious if destination is not a local/internal service
   - Expired? → Suspicious if the client accepted it (possible cert pinning bypass)
   - Subject/issuer mismatch with SNI? → Possible MITM or C2 with lazy cert setup
4. Check the SNI (`tls.sni`) — does the domain match a known bad destination?
5. Check TLS version — TLS 1.0/1.1 from a modern phone is anomalous
6. Look at the destination IP — is it in a cloud range (AWS/Azure/GCP)? Residential? VPS provider?
7. Correlate with DNS events — what domain did the device resolve to reach this IP?

**Severity guidance:**
- JA3 matches known malware family → HIGH
- Self-signed cert to non-internal IP with suspicious domain → HIGH
- TLS 1.0/1.1 usage → MEDIUM (possibly outdated app, not necessarily malicious)
- Certificate mismatch on CDN/cloud IP → LOW (often legitimate)

## Playbook 3: HTTP Alert (Suspicious Request)

**Triggers:** ET MALWARE, ET TROJAN (HTTP-based), beacon patterns, suspicious User-Agent

**Steps:**

1. Extract HTTP details: method, URI, User-Agent, host header
2. Assess the User-Agent:
   - Matches known malware UA string → HIGH
   - Generic/empty UA from a phone (should have a browser or app UA) → MEDIUM
   - Python/curl/wget from a phone → suspicious (not typical mobile behavior)
3. Check the URI path:
   - Known C2 gate paths (`/gate.php`, `/panel/`, `/api/check`) → HIGH
   - Encoded/base64 parameters → suspicious
   - Long random query strings → possible data exfil in URL
4. Check HTTP method and body:
   - POST with large body to non-API destination → possible exfil
   - GET with long encoded URL parameters → possible C2 check-in
5. Check if this is plaintext HTTP (not HTTPS) — modern apps should use TLS. Cleartext HTTP to non-local destinations is itself suspicious on a modern phone.

**Severity guidance:**
- Known malware signature + known C2 URI pattern → CRITICAL
- Suspicious User-Agent + unusual destination → HIGH
- Cleartext HTTP with structured data → MEDIUM
- Generic ET POLICY/ET INFO HTTP alerts → LOW

## Playbook 4: Flow Anomaly (Beaconing/Exfil)

**Triggers:** Pattern analysis, byte ratio anomalies, long-lived connections, regular-interval check-ins

**Steps:**

1. Calculate the beacon interval if multiple flows to the same destination exist:
   - Extract timestamps of connection starts
   - Calculate inter-arrival time (IAT) — mean, median, standard deviation
   - Low jitter (stddev < 10% of mean) + regular interval → likely C2 beaconing
   - Common beacon intervals: 60s, 300s, 600s, 3600s
2. Calculate byte ratio: `bytes_toserver / bytes_toclient`
   - Ratio >> 1 (heavy upload) → possible exfiltration
   - Ratio << 1 (heavy download) → normal browsing or possible payload delivery
   - Ratio ≈ 1 with small volumes → possible C2 heartbeat
3. Check connection duration — flows lasting >1 hour to non-streaming services are unusual
4. Check destination:
   - VPS provider IP with no associated domain → suspicious
   - Cloud provider IP → check if any app on the phone legitimately uses that service
   - Residential IP → unusual, possible compromised host or residential proxy
5. Correlate with DNS and TLS events for the same flow_id

**Severity guidance:**
- Regular beaconing to known C2 → CRITICAL
- Regular beaconing to unknown VPS IP → HIGH
- Large upload to unrecognized destination → HIGH
- Long-lived connection to cloud service → MEDIUM (could be legitimate push notification)
- Short flows to CDN/known service → LOW

## Playbook 5: Data Exfiltration Indicator

**Triggers:** DNS TXT exfil, large uploads, protocol tunneling, demo rule 9999905

**Steps:**

1. Identify the exfil channel:
   - DNS: Check for TXT queries with long encoded data, or high volume of unique subdomain queries
   - HTTP/HTTPS: Large POST bodies, base64-encoded URL parameters
   - Raw TCP/UDP: Non-standard ports with high upload volume
2. Estimate data volume:
   - DNS exfil: ~200 bytes per query (slow but stealthy)
   - HTTP exfil: unlimited bandwidth (fast but noisier)
3. Check timing:
   - Burst upload → possible file exfil (contacts, photos, messages)
   - Steady trickle → possible keylogger or screen capture streaming
   - Periodic dumps → possible scheduled data collection
4. Check what else the device was doing at the same time — any preceding C2 check-in?
5. Check if the destination matches any known C2 infrastructure from other alerts

**Severity guidance:**
- Confirmed data exfil to known malware infra → CRITICAL
- DNS tunneling with encoded data → HIGH
- Large upload to unrecognized destination, no prior C2 alerts → MEDIUM (could be cloud backup)
- Small volume to cloud service → LOW

## Playbook 6: Multi-Alert Correlation (Same Device)

**Triggers:** Multiple alerts from the same source IP within a 1-hour window

**Steps:**

1. Group all alerts by source IP (device)
2. Map each alert to a kill chain stage:
   - Initial Access: phishing domain, exploit kit
   - C2: beaconing, known C2 domain, suspicious TLS
   - Collection: stalkerware connection, credential harvesting
   - Exfiltration: data upload, DNS tunneling
3. Assess progression:
   - Alerts in ONE stage → probably single event, triage individually
   - Alerts across TWO+ stages → possible active compromise chain → escalate
4. Check temporal ordering — do the alerts follow a logical attack progression?
5. Compile a timeline and send a consolidated Signal alert with the full chain

**Severity: Always CRITICAL when alerts span multiple kill chain stages from one device.**

## Playbook 7: False Positive Assessment

**Triggers:** Any alert where the destination is a well-known legitimate service

**Steps:**

1. Identify the destination: Is it Google, Apple, Microsoft, Amazon, Cloudflare, Akamai, Fastly?
2. Check the specific IP/domain — CDN and cloud IPs are shared. Malware DOES use cloud infrastructure.
3. Check the signature specificity:
   - Signature matches on specific payload content → likely true positive even to cloud IP
   - Signature matches on generic behavior (e.g., "possible DNS tunneling" on a high-entropy CDN subdomain) → likely false positive
4. Check frequency — does this alert fire constantly for this device? → likely FP
5. If confirmed FP, recommend a suppression rule:
   ```
   suppress gen_id 1, sig_id [SID], track by_src, ip [device_IP]
   ```
   Or recommend tuning the threshold.

**Important:** Do not auto-suppress. Always recommend to the operator and let them decide. Some "legitimate" services are used as C2 channels (Google Docs, Pastebin, Telegram).
