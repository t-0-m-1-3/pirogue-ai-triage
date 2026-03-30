# JA3/JA4 Fingerprint Reference

## What JA3 Is

JA3 hashes the TLS Client Hello parameters (TLS version, cipher suites, extensions, elliptic curves, elliptic curve point formats) into an MD5 hash. Same software with same TLS configuration produces the same JA3 hash regardless of destination.

**Formula:** `MD5(TLSVersion,Ciphers,Extensions,EllipticCurves,EllipticCurvePointFormats)`

## Why It Matters for Mobile Triage

- Legitimate mobile apps (Chrome, Safari, Signal) have known, stable JA3 hashes
- Malware and implants often have distinct JA3 hashes due to custom TLS stacks or specific cipher preferences
- A phone producing an unexpected JA3 hash may be running a hidden process with its own TLS implementation
- JA3 survives certificate rotation — even if C2 domains change, the client fingerprint stays the same

## Known Malicious JA3 Hashes

These are well-documented hashes. Cross-reference with the abuse.ch SSLBL JA3 feed for the latest list.

**Note:** JA3 hashes can be shared between malicious and legitimate software. A JA3 match is a MEDIUM confidence indicator unless paired with other IOCs.

### Common Malware JA3 Hashes

| JA3 Hash | Associated With | Notes |
|----------|----------------|-------|
| `a0e9f5d64349fb13191bc781f81f42e1` | Cobalt Strike (default) | Very well-known; frequently rotated in newer deployments |
| `72a589da586844d7f0818ce684948eea` | Cobalt Strike (Java) | Java-based Cobalt Strike stager |
| `e7d705a3286e19ea42f587b344ee6865` | Metasploit Meterpreter | Default Meterpreter HTTPS handler |
| `51c64c77e60f3980eea90869b68c58a8` | TrickBot | Banking trojan, also used as loader |
| `6734f37431670b3ab4292b8f60f29984` | AsyncRAT | Common remote access trojan |
| `3b5074b1b5d032e5620f69f9f700ff0e` | Emotet | Loader malware |

### Legitimate Mobile JA3 Hashes (Baseline)

Knowing what normal looks like helps identify anomalies:

| JA3 Hash | Client | Platform |
|----------|--------|----------|
| Varies by version | Chrome (Android) | Changes with each Chrome release |
| Varies by version | Safari (iOS) | Tied to iOS version |
| Varies by version | Signal app | Updates with each app release |

**Important:** Legitimate app JA3 hashes change with updates. Don't hardcode them as "known good." Instead, establish a baseline for each monitored device and flag NEW hashes that appear.

## JA3S (Server Fingerprint)

JA3S fingerprints the server's TLS response (Server Hello). Useful for identifying C2 infrastructure:

- Same C2 server will have the same JA3S hash even if it changes domains/IPs
- A JA3S hash that matches a known C2 framework is a strong indicator

## JA4+ (Next Generation)

JA4 is the successor to JA3, designed to be more robust and specific:

- **JA4**: TLS client fingerprint (replaces JA3)
- **JA4S**: TLS server fingerprint (replaces JA3S)
- **JA4H**: HTTP client fingerprint
- **JA4X**: X.509 certificate fingerprint
- **JA4T**: TCP client fingerprint

Suricata support for JA4 is available in newer versions. If the VPS runs Suricata 7.0+, JA4 may be available in eve.json under `tls.ja4`.

## Triage Workflow for JA3 Alerts

1. Extract the JA3 hash from the alert or TLS event
2. Check against abuse.ch SSLBL: `https://sslbl.abuse.ch/ja3-fingerprints/`
3. If no match, check if this JA3 hash is new for this device:
   ```bash
   jq -c 'select(.event_type=="tls" and .src_ip=="DEVICE_IP") | .tls.ja3.hash' \
     /var/log/suricata/eve.json | sort | uniq -c | sort -rn
   ```
4. If the hash is new and not attributable to a known app/browser update, escalate
5. Check what destination the hash was used for — a new JA3 to a known-good service (Google, Apple) is likely an app update; a new JA3 to an unknown VPS IP is suspicious

## Building JA3 Baseline Per Device

Run this periodically to establish what's normal for each phone:

```bash
# Generate JA3 baseline for a device
jq -r 'select(.event_type=="tls" and .src_ip=="10.66.0.2") | [.tls.ja3.hash, .tls.sni] | @tsv' \
  /var/log/suricata/eve.json | sort | uniq -c | sort -rn | head -30
```

Output shows: `count  ja3_hash  sni` — the top JA3+SNI combinations are your baseline. Anything outside this set is worth investigating.
