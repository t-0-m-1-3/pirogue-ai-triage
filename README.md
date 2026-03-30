# Hunting in Your Pocket

**AI-Augmented Mobile Threat Detection with PiRogue Tool Suite**

Continuous mobile threat monitoring using open-source tools on a single VPS. Suricata IDS detects threats in phone traffic tunneled through WireGuard, a Claude agent triages and enriches alerts in real time, and signal-cli delivers encrypted notifications to your phone via Signal.

Presented at [Conference Name] 2026 by [Your Name].

---

## Architecture

```
┌──────────┐     WireGuard      ┌──────────────────────────────────────────┐
│  Phone   │ ─────────────────► │  Debian VPS                              │
│(any OS)  │   all traffic      │                                          │
└──────────┘   tunneled         │  ┌──────────┐    ┌───────────────────┐   │
                                │  │ Suricata  │───►│ pirogue-triage    │   │
                                │  │ IDS + DPI │    │ daemon            │   │
                                │  └──────────┘    │                   │   │
                                │                  │  eve.json watcher │   │
                                │  ┌──────────┐    │  deduplication    │   │
                                │  │ PiRogue  │    │  Claude API call  │   │
                                │  │ Suite    │    │  alert formatting │   │
                                │  └──────────┘    └────────┬──────────┘   │
                                │                           │              │
                                │                  ┌────────▼──────────┐   │
                                │                  │ signal-cli        │   │
                                │                  │ (encrypted alert) │   │
                                │                  └────────┬──────────┘   │
                                └───────────────────────────┼──────────────┘
                                                            │
                                                   ┌────────▼──────────┐
                                                   │  Your Phone       │
                                                   │  Signal notification
                                                   └───────────────────┘
```

## What You Need

- A **Debian 12 VPS** ($5–10/month — Hetzner, Vultr, Linode, DigitalOcean all work)
- **PiRogue Tool Suite** installed on the VPS ([installation guide](https://pts-project.org/docs/prologue/introduction/))
- A **phone** with the WireGuard app (iOS or Android)
- A **Signal account** for receiving alerts
- An **Anthropic API key** for Claude-powered triage ([console.anthropic.com](https://console.anthropic.com))
- A **domain** you control, pointed at the VPS via Cloudflare (for the demo site)

## Repository Structure

```
pirogue-ai-triage/
├── CLAUDE.md                      # Claude agent instructions for VPS
├── README.md                      # This file
├── .envrc                         # direnv config (auto-loads nix shell + secrets)
├── .gitignore
│
├── agent-docs/                    # Reference docs for the Claude agent
│   ├── SKILL.md                   # Agent role, triage framework, behavioral rules
│   ├── EVE_JSON_REFERENCE.md      # Suricata event field reference
│   ├── MOBILE_THREAT_INTEL.md     # Spyware families, stalkerware, IOC feeds
│   ├── MITRE_MOBILE_REFERENCE.md  # ATT&CK Mobile network-detectable techniques
│   ├── TRIAGE_PLAYBOOKS.md        # Step-by-step analysis for alert categories
│   ├── VPS_OPERATIONS.md          # Commands, paths, jq queries
│   └── JA3_REFERENCE.md           # TLS fingerprint analysis and known hashes
│
├── vps/                           # Deploy on the VPS
│   ├── deploy-vps.sh              # One-shot installer script
│   ├── pirogue-triage-daemon.py   # Main triage daemon
│   ├── config.toml                # Daemon configuration
│   ├── pirogue-triage.service     # systemd unit file
│   └── demo-rules.rules          # Suricata rules for demo/testing
│
├── demo-site/                     # Demo domain site + infrastructure
│   ├── CLOUDFLARE_SETUP.md        # Full Cloudflare + DNS + SSL setup guide
│   ├── SURICATA_CONFIG.md         # Suricata configuration changes required
│   ├── setup-demo-user.sh         # Create demo-site service user
│   ├── your-demo-domain.conf      # nginx config (rename to your domain)
│   └── www/
│       └── index.html             # Landing page
│
└── laptop/                        # Presenter tools (NixOS)
    ├── shell.nix                  # Nix shell with all demo dependencies
    ├── demo-stage.sh              # tmux 4-pane stage layout
    ├── demo-trigger.sh            # Fire test alerts through the tunnel
    └── sops-direnv-setup.md       # sops-nix + direnv setup guide
```

---

## ⚠️ Customize Before Deploying

This repo ships with placeholder values that **must** be changed before use. Search-and-replace these across all files:

| Placeholder | Replace with | Files affected |
|-------------|-------------|----------------|
| `your-demo-domain.com` | Your actual domain (e.g., `isitransomware.org`) | `vps/demo-rules.rules`, `demo-site/*`, `laptop/demo-trigger.sh` |
| `YOUR_VPS_IP` | Your VPS public IP address | `demo-site/your-demo-domain.conf` |
| `10.8.0.1` | Your WireGuard gateway IP (if different) | `demo-site/your-demo-domain.conf`, `vps/demo-rules.rules` |
| `+1YOURNUMBER` | Your Signal number in international format | `vps/config.toml`, any manual commands |
| `+1XXXXXXXXXX` | Signal recipient number | `vps/config.toml` |
| `sk-ant-...` | Your Anthropic API key | `/etc/pirogue-triage/env` on VPS |
| `[you]` | Your GitHub username | `README.md`, `demo-site/www/index.html`, `vps/pirogue-triage.service` |
| `[Your Name]` | Your name | `README.md` |
| `[Conference Name]` | Conference name | `README.md` |
| `your-demo-domain.conf` | Rename to match your domain | `demo-site/` |

Quick one-liner to replace the domain everywhere:

```bash
find . -type f -not -path "./.git/*" -exec sed -i 's/your-demo-domain\.com/youractualdomain.com/g' {} +
mv demo-site/your-demo-domain.conf demo-site/youractualdomain.conf
```

---

## Quick Start

### 1. Install PiRogue Tool Suite

Follow the [PiRogue VPS installation guide](https://pts-project.org/docs/prologue/introduction/). You should have Suricata running and at least one phone tunneled through WireGuard before proceeding.

### 2. Install signal-cli (native build, no Java required)

```bash
VERSION=$(curl -Ls -o /dev/null -w %{url_effective} \
  https://github.com/AsamK/signal-cli/releases/latest | sed -e 's/^.*\/v//')
curl -L -O "https://github.com/AsamK/signal-cli/releases/download/v${VERSION}/signal-cli-${VERSION}-Linux-native.tar.gz"
sudo tar xf signal-cli-${VERSION}-Linux-native.tar.gz -C /opt
sudo ln -sf /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli
signal-cli --version
```

### 3. Link signal-cli to your Signal account

```bash
signal-cli link -n "pirogue-vps"
```

A QR code will appear in the terminal. Open Signal on your phone → Settings → Linked Devices → scan it.

Test it:

```bash
signal-cli -a +1YOURNUMBER send -m "PiRogue alerting online" +1YOURNUMBER
```

### 4. Deploy the triage daemon

```bash
git clone https://github.com/[you]/pirogue-ai-triage.git
cd pirogue-ai-triage

# Copy files to the VPS (if cloning locally)
scp -r vps/* agent-docs/ CLAUDE.md root@your-vps:~/pirogue-triage-deploy/

# On the VPS:
cd ~/pirogue-triage-deploy
sudo bash deploy-vps.sh
```

### 5. Configure

```bash
# Set your Anthropic API key
echo 'ANTHROPIC_API_KEY=sk-ant-your-key-here' | sudo tee /etc/pirogue-triage/env

# Edit config with your Signal number
sudo nano /etc/pirogue-triage/config.toml
```

In `config.toml`, set:
- `signal_account` — your Signal number in international format (+1XXXXXXXXXX)
- `signal_recipients` — who receives alerts (can be the same number)
- `demo_mode` — set `true` for verbose logging during testing

### 6. Deploy agent docs

Copy `CLAUDE.md` and the `agent-docs/` directory to wherever your Claude agent reads its context from. If using Claude Code, place them in the project root:

```bash
# On the VPS, in your Claude agent's project directory
cp ~/pirogue-triage-deploy/CLAUDE.md ./
cp -r ~/pirogue-triage-deploy/agent-docs/ ./agent-docs/
```

### 7. Start and test

```bash
# Start the triage daemon
sudo systemctl start pirogue-triage
sudo journalctl -u pirogue-triage -f

# In another terminal, deploy and test demo rules
sudo cp demo-rules.rules /etc/suricata/rules/
# Add "demo-rules.rules" to /etc/suricata/suricata.yaml under rule-files
sudo suricatasc -c reload-rules

# Fire a test alert (from the phone or through the tunnel)
# Option A: Open a browser on the phone and go to your-demo-domain.com
# Option B: Run the trigger script through the tunnel
./demo-trigger.sh dns
```

You should see the alert flow through the triage daemon log and receive a Signal notification within seconds.

## Demo Rules

Five custom Suricata rules (SID 9999901–9999905) are included for testing and live demos:

| SID | Trigger | How to fire it |
|-----|---------|---------------|
| 9999901 | DNS C2 domain | Open browser → navigate to `your-demo-domain.com` |
| 9999902 | Stalkerware domain | Browse to `tracker.your-demo-domain.com` |
| 9999903 | JA3 fingerprint | `curl --tlsv1.2 --ciphers ECDHE-RSA-AES128-GCM-SHA256 `curl` with forced cipher through WireGuard (see rule comments)` |
| 9999904 | HTTP beacon UA | `curl -A "Mozilla/5.0 (compatible; BabyShark/2.0)" `curl -A "BabyShark/2.0" http://your-demo-domain.com/gate.php`` |
| 9999905 | DNS TXT exfil | ``dig TXT exfil-test.your-demo-domain.com`` |

**Before using:** See the **Customize Before Deploying** section above for all values you need to change.

## Claude Agent Docs

The `agent-docs/` directory contains reference material for a Claude agent performing security triage on this VPS. These are not documentation for humans (though they're human-readable) — they're structured context that makes the agent significantly better at analyzing Suricata alerts.

| Doc | Purpose |
|-----|---------|
| **SKILL.md** | Agent role definition, triage framework, alert format, behavioral rules |
| **EVE_JSON_REFERENCE.md** | Field-level reference for every eve.json event type |
| **MOBILE_THREAT_INTEL.md** | Known spyware, stalkerware, mobile RATs, IOC feed URLs |
| **MITRE_MOBILE_REFERENCE.md** | Network-detectable ATT&CK Mobile techniques |
| **TRIAGE_PLAYBOOKS.md** | Step-by-step playbooks for 7 common alert categories |
| **VPS_OPERATIONS.md** | Commands, file paths, jq queries for investigation |
| **JA3_REFERENCE.md** | TLS fingerprint analysis reference and known-bad hashes |

## Cost

Running this architecture costs roughly $5–15/month total:

- **VPS**: $5–10/month (2GB RAM, 1-2 vCPU is sufficient)
- **Claude API**: ~$0.01–0.03 per triaged alert (at personal scale, usually <$1/month)
- **Signal**: Free
- **Everything else**: Free and open source

## Troubleshooting

**signal-cli: `UnsupportedClassVersionError`**
You installed the JVM build instead of the native build. Download the `*-Linux-native.tar.gz` release instead. See step 2 above.

**signal-cli: `Authorization failed`**
The linked device expired or was removed. Re-link: `signal-cli link -n "pirogue-vps"` and scan the QR code again.

**No alerts firing**
Check that Suricata is running (`systemctl status suricata`), that your demo rules are loaded (`grep 9999901 /etc/suricata/rules/demo-rules.rules`), and that the phone's traffic is actually routing through WireGuard (`wg show` should show recent handshake).

**Triage daemon not sending alerts**
Check `journalctl -u pirogue-triage -f`. Common issues: API key not set in `/etc/pirogue-triage/env`, signal-cli not linked, `signal_account` not configured in `config.toml`.

## License

MIT. Use it, modify it, deploy it for anyone you want to protect.

## Acknowledgments

- [PiRogue Tool Suite](https://pts-project.org/) by Defensive Lab Agency
- [signal-cli](https://github.com/AsamK/signal-cli) by AsamK
- [Suricata](https://suricata.io/) by OISF
- [MVT](https://github.com/mvt-project/mvt) by Amnesty International Security Lab
- [Stalkerware Indicators](https://github.com/Te-k/stalkerware-indicators) by Te-k
