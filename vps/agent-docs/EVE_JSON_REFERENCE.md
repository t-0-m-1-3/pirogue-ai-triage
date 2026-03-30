# Suricata eve.json Field Reference

## Event Types

The `event_type` field determines the schema. Key types for mobile triage:

### alert

Signature match. This is your primary triage input.

```json
{
  "timestamp": "2026-03-23T14:22:01.123456+0000",
  "event_type": "alert",
  "src_ip": "10.66.0.2",
  "src_port": 48372,
  "dest_ip": "93.184.216.34",
  "dest_port": 443,
  "proto": "TCP",
  "alert": {
    "action": "allowed",
    "gid": 1,
    "signature_id": 2024897,
    "rev": 3,
    "signature": "ET MALWARE Possible BabyShark CnC Beacon",
    "category": "A Network Trojan was Detected",
    "severity": 1,
    "metadata": {
      "mitre_tactic": ["command-and-control"],
      "mitre_technique": ["T1071"]
    }
  },
  "tls": { ... },
  "flow_id": 1234567890,
  "pcap_cnt": 42
}
```

**Key fields:**
- `alert.severity`: 1 = highest, 2 = medium, 3 = lowest (Suricata inverts the intuitive scale)
- `alert.signature`: Human-readable rule name. Parse this for threat intel context.
- `alert.metadata`: May contain MITRE mappings, deployment tags, affected products
- `alert.action`: "allowed" or "blocked" depending on IPS mode

### dns

All DNS queries and responses from monitored devices.

```json
{
  "event_type": "dns",
  "src_ip": "10.66.0.2",
  "dest_ip": "10.66.0.1",
  "dns": {
    "type": "query",
    "id": 12345,
    "rrname": "api.example.com",
    "rrtype": "A",
    "tx_id": 0
  }
}
```

**For responses:**
```json
{
  "dns": {
    "type": "answer",
    "id": 12345,
    "rrname": "api.example.com",
    "rrtype": "A",
    "rdata": "93.184.216.34",
    "ttl": 300
  }
}
```

**Triage value:** DNS is the single highest-value telemetry source for mobile threats. Watch for:
- DGA patterns (high entropy domain names, randomized subdomains)
- Known bad domains (C2 infrastructure, stalkerware control panels)
- Unusual TLDs (.top, .xyz, .tk for commodity malware)
- DNS over HTTPS bypass attempts (queries to doh.* domains)
- TXT record queries (potential data exfiltration channel)
- Rapid unique subdomain queries (DNS tunneling / beaconing)

### tls

TLS handshake metadata — captured WITHOUT decryption.

```json
{
  "event_type": "tls",
  "src_ip": "10.66.0.2",
  "dest_ip": "93.184.216.34",
  "tls": {
    "subject": "CN=*.example.com",
    "issuerdn": "CN=Let's Encrypt Authority X3, O=Let's Encrypt",
    "serial": "03:AB:CD:...",
    "fingerprint": "ab:cd:ef:...",
    "sni": "api.example.com",
    "version": "TLS 1.3",
    "notbefore": "2026-01-01T00:00:00",
    "notafter": "2026-04-01T00:00:00",
    "ja3": {
      "hash": "e7d705a3286e19ea42f587b344ee6865",
      "string": "771,4866-4867-4865-49196-49200...",
    },
    "ja3s": {
      "hash": "f4e1b3b8f7a2c9d0e5f6a7b8c9d0e1f2",
      "string": "771,4866,0-43-51"
    }
  }
}
```

**Key fields:**
- `tls.sni`: Server Name Indication — the domain the client is connecting to. This is visible even with TLS 1.3.
- `tls.ja3.hash`: Client TLS fingerprint. Different software produces different JA3 hashes. Known malware families have known JA3 hashes.
- `tls.ja3s.hash`: Server TLS fingerprint. Useful for identifying C2 infrastructure.
- `tls.subject` / `tls.issuerdn`: Certificate details. Self-signed certs to unusual destinations are suspicious.
- `tls.version`: TLS 1.0/1.1 connections from a modern phone are anomalous and worth flagging.

### flow

Connection-level metadata after a flow completes.

```json
{
  "event_type": "flow",
  "src_ip": "10.66.0.2",
  "dest_ip": "93.184.216.34",
  "dest_port": 443,
  "proto": "TCP",
  "flow": {
    "pkts_toserver": 15,
    "pkts_toclient": 22,
    "bytes_toserver": 1432,
    "bytes_toclient": 28576,
    "start": "2026-03-23T14:22:01.000000+0000",
    "end": "2026-03-23T14:22:03.500000+0000",
    "age": 2,
    "state": "closed",
    "reason": "timeout"
  }
}
```

**Triage value:** Look for:
- High `bytes_toserver` with low `bytes_toclient` → possible data exfiltration
- Long-lived connections (high `age`) to unusual destinations → possible C2 keep-alive
- Many short flows to the same destination in rapid succession → beaconing pattern
- Flows to unusual ports (non-80/443) → potential covert channel

## Correlating Events

Events share `flow_id` — use this to correlate an alert with its DNS query, TLS handshake, and flow metadata for full context. Example workflow:

1. Alert fires on flow_id 1234567890
2. Find the DNS event with the same flow_id to see what domain was queried
3. Find the TLS event to get JA3 hash and certificate details
4. Find the flow event to see data volumes and duration

## Suricata Rule Prefixes

Common signature name prefixes and what they mean:

| Prefix | Source | Relevance |
|--------|--------|-----------|
| `ET MALWARE` | Emerging Threats | Known malware communication |
| `ET TROJAN` | Emerging Threats | Trojan-specific signatures |
| `ET DNS` | Emerging Threats | Suspicious DNS patterns |
| `ET CNC` | Emerging Threats | Command and control infrastructure |
| `ET POLICY` | Emerging Threats | Policy violations (not necessarily malicious) |
| `ET INFO` | Emerging Threats | Informational (low priority) |
| `ET HUNTING` | Emerging Threats | Threat hunting signatures (noisy by design) |
| `SURICATA` | Built-in | Protocol anomalies, decoder errors |
| `GPL` | Community (Snort-derived) | Older community signatures |
| `PIROGUE-DEMO` | Custom | Demo/test rules (SID 9999xxx) |

**Priority guidance:** `ET MALWARE` and `ET TROJAN` alerts are almost always worth triaging. `ET POLICY` and `ET INFO` are usually noise. `ET HUNTING` signatures fire frequently and are designed for analyst review, not automated alerting — consider suppressing these from Signal notifications unless the operator explicitly wants them.
