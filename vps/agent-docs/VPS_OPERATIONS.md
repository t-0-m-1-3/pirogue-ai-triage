# VPS Operations Reference

Commands and paths for investigating alerts, managing services, and operating PiRogue.

## Service Management

```bash
# Check all PiRogue-related services
systemctl status suricata pirogue-* pirogue-triage

# Restart Suricata (after rule changes)
systemctl restart suricata

# Reload Suricata rules without restart (preferred)
suricatasc -c reload-rules

# View triage daemon logs
journalctl -u pirogue-triage -f --no-hostname

# Restart triage daemon
systemctl restart pirogue-triage
```

## Key File Paths

| Path | Contents |
|------|----------|
| `/var/log/suricata/eve.json` | Primary Suricata event log (alerts, DNS, TLS, flow) |
| `/var/log/suricata/fast.log` | One-line-per-alert summary log |
| `/var/log/suricata/stats.log` | Suricata performance counters |
| `/var/log/pirogue-triage/triage.log` | AI triage daemon log |
| `/etc/suricata/suricata.yaml` | Suricata main configuration |
| `/etc/suricata/rules/` | Suricata rule files directory |
| `/etc/suricata/rules/demo-rules.rules` | Demo rules for conference |
| `/etc/pirogue-triage/config.toml` | Triage daemon configuration |
| `/etc/pirogue-triage/env` | API key (ANTHROPIC_API_KEY) |
| `/var/lib/pirogue/pcaps/` | Stored PCAP files (if retention enabled) |
| `/var/log/unbound/query.log` | DNS query log (if Unbound logging enabled) |
| `/etc/wireguard/wg0.conf` | WireGuard tunnel configuration |

## Querying eve.json

### Recent alerts
```bash
# Last 10 alerts
tail -100 /var/log/suricata/eve.json | jq -c 'select(.event_type=="alert")' | tail -10

# Alerts in the last 5 minutes
jq -c 'select(.event_type=="alert")' /var/log/suricata/eve.json | \
  awk -v cutoff="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" '$0 ~ cutoff {found=1} found'

# Live alert stream (for monitoring)
tail -f /var/log/suricata/eve.json | jq --unbuffered 'select(.event_type=="alert")'
```

### Filter by SID
```bash
# All alerts for a specific SID
jq -c 'select(.event_type=="alert" and .alert.signature_id==9999901)' /var/log/suricata/eve.json
```

### Filter by source IP (device)
```bash
# All events from a specific phone
jq -c 'select(.src_ip=="10.66.0.2")' /var/log/suricata/eve.json | tail -50

# All alerts from a specific phone
jq -c 'select(.event_type=="alert" and .src_ip=="10.66.0.2")' /var/log/suricata/eve.json
```

### DNS queries from a device
```bash
# All DNS queries from a device
jq -c 'select(.event_type=="dns" and .src_ip=="10.66.0.2" and .dns.type=="query") | .dns.rrname' \
  /var/log/suricata/eve.json | sort -u

# DNS queries to a specific domain
jq -c 'select(.event_type=="dns" and .dns.rrname=="suspicious.example.com")' \
  /var/log/suricata/eve.json
```

### TLS metadata
```bash
# TLS connections with JA3 hashes from a device
jq -c 'select(.event_type=="tls" and .src_ip=="10.66.0.2") | {sni: .tls.sni, ja3: .tls.ja3.hash, subject: .tls.subject}' \
  /var/log/suricata/eve.json | sort -u

# Find all connections with a specific JA3 hash
jq -c 'select(.event_type=="tls" and .tls.ja3.hash=="e7d705a3286e19ea42f587b344ee6865")' \
  /var/log/suricata/eve.json
```

### Flow analysis
```bash
# Top destinations by byte volume from a device (upload-heavy = possible exfil)
jq -c 'select(.event_type=="flow" and .src_ip=="10.66.0.2") | {dest: .dest_ip, port: .dest_port, up: .flow.bytes_toserver, down: .flow.bytes_toclient}' \
  /var/log/suricata/eve.json | sort -t: -k4 -rn | head -20

# Long-lived flows (>300 seconds)
jq -c 'select(.event_type=="flow" and .flow.age > 300) | {src: .src_ip, dest: .dest_ip, port: .dest_port, age: .flow.age, up: .flow.bytes_toserver}' \
  /var/log/suricata/eve.json
```

### Correlate by flow_id
```bash
# Get all events for a specific flow
FLOW_ID="1234567890"
jq -c "select(.flow_id==$FLOW_ID)" /var/log/suricata/eve.json
```

## WireGuard Status

```bash
# Show connected peers (phones)
wg show

# Show peer details with last handshake time
wg show wg0 dump | awk '{print "Peer:", $1, "Endpoint:", $3, "Last handshake:", strftime("%Y-%m-%d %H:%M:%S", $5)}'
```

## Signal Operations

```bash
# Send a test message
signal-cli -a +1YOURNUMBER send -m "Test alert" +1RECIPIENT

# Send from stdin (useful for piping)
echo "Alert text" | signal-cli -a +1YOURNUMBER send --message-from-stdin +1RECIPIENT

# Receive pending messages (required periodically to keep encryption working)
signal-cli -a +1YOURNUMBER receive

# List linked devices
signal-cli -a +1YOURNUMBER listDevices
```

## PCAP Analysis

```bash
# Quick packet count for a capture
tcpdump -r /var/lib/pirogue/pcaps/capture.pcap -c 0 2>&1 | tail -1

# Extract DNS queries from PCAP
tcpdump -r capture.pcap -n port 53 2>/dev/null | head -50

# Extract HTTP requests from PCAP
tcpdump -r capture.pcap -A -n 'tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)' 2>/dev/null | grep -E "^(GET|POST|Host:)"

# Convert to JSON for analysis (with tshark if available)
tshark -r capture.pcap -T json -c 100
```

## Suricata Rule Management

```bash
# List all loaded rules
suricatasc -c "ruleset-stats"

# Check if a specific SID is loaded
grep "sid:9999901" /etc/suricata/rules/*.rules

# Add a suppression (stop alerting on a noisy rule for a specific source)
echo 'suppress gen_id 1, sig_id 2024897, track by_src, ip 10.66.0.2' >> /etc/suricata/threshold.config
suricatasc -c reload-rules

# Add a threshold (only alert once per interval)
echo 'threshold gen_id 1, sig_id 2024897, type threshold, track by_src, count 1, seconds 600' >> /etc/suricata/threshold.config
suricatasc -c reload-rules
```

## System Health

```bash
# Disk usage (PCAPs and logs are the primary consumers)
df -h /var/log /var/lib/pirogue

# Suricata resource usage
systemctl status suricata | grep -E "(Memory|CPU)"

# Check for dropped packets (indicates Suricata can't keep up)
jq 'select(.event_type=="stats") | .stats.capture.kernel_drops' /var/log/suricata/eve.json | tail -5

# Network throughput on WireGuard interface
cat /proc/net/dev | grep wg0
```
