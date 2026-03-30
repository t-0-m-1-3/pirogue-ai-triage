# Suricata Configuration Changes for PiRogue AI Triage

PiRogue's default Suricata config needs several modifications for the triage daemon and demo rules to work. This documents every change.

## 1. Add failure-fatal: no

PiRogue's ruleset may contain rules incompatible with Suricata 6.0. Without this, a single broken rule prevents ALL rules from loading.

Add near the top of `/etc/suricata/suricata.yaml` (after the `%YAML` line):

```yaml
engine:
  rules:
    failure-fatal: no
```

## 2. Add file-based EVE logging

PiRogue's default EVE output writes to a unix socket (`/run/suricata.socket`) for the eve-collector. The triage daemon needs a regular file. Add a **second** eve-log block — do NOT remove the socket one (PiRogue needs it for Grafana).

Find the existing `eve-log` block and add the new one directly after it, at the same indentation level:

```yaml
  # Existing PiRogue eve-log (DO NOT REMOVE)
  - eve-log:
      enabled: yes
      filetype: unix_dgram
      filename: /run/suricata.socket
      level: Info
      metadata: yes
      pcap-file: false
      community-id: true
  # NEW: File-based eve-log for triage daemon
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      append: yes
      community-id: true
      types:
        - alert
        - dns
        - tls:
            extended: yes
        - flow
      community-id-seed: 0
```

### Critical: Only ONE types: block

If the config has a second `types:` block further down in the same eve-log section (commonly with `alert:` and `metadata:` sub-keys), the second one **silently overrides** the first. You'll only get alert events and nothing else. Delete any duplicate `types:` block.

## 3. Enable JA3 fingerprinting

Find `app-layer: protocols: tls:` (around line 555) and add or uncomment:

```yaml
      ja3-fingerprints: yes
```

## 4. Add demo rules to rule-files

Find the `rule-files:` section and add:

```yaml
rule-files:
  - suricata.rules
  - demo-rules.rules
```

Deploy the rules file to the **correct** directory:

```bash
# PiRogue uses /var/lib/suricata/rules/, NOT /etc/suricata/rules/
sudo cp demo-rules.rules /var/lib/suricata/rules/demo-rules.rules
```

Check your `default-rule-path` if unsure:

```bash
sudo grep "default-rule-path" /etc/suricata/suricata.yaml
```

## 5. Verify and restart

```bash
# Test config
sudo suricata -T -c /etc/suricata/suricata.yaml 2>&1 | tail -5

# Restart
sudo systemctl restart suricata

# Verify rules loaded
sudo grep "signatures processed" /var/log/suricata/suricata.log | tail -1

# Verify eve.json gets data (browse on phone, wait 10s)
sudo jq -c '.event_type' /var/log/suricata/eve.json | sort | uniq -c
# Should show: alert, dns, flow, tls
```

## Summary

| Change | Where | Why |
|--------|-------|-----|
| `failure-fatal: no` | Top of suricata.yaml | Broken rules won't block loading |
| Second `eve-log` block | `outputs:` section | Triage daemon needs file, not socket |
| `tls: extended: yes` | New eve-log types | Full TLS metadata including JA3 |
| `ja3-fingerprints: yes` | `app-layer.protocols.tls` | Generate JA3 hashes |
| `- demo-rules.rules` | `rule-files:` section | Load demo rules |
| Rules in `/var/lib/suricata/rules/` | File system | PiRogue's default-rule-path |
