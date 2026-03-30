#!/usr/bin/env bash
# =============================================================================
# deploy-vps.sh — Deploy triage daemon + signal-cli on the PiRogue VPS
# =============================================================================
#
# Run on the VPS AFTER PiRogue is already installed and running.
#
# Usage:
#   scp -r vps/* demo-site/ agent-docs/ CLAUDE.md user@vps:~/pirogue-deploy/
#   ssh user@vps
#   cd ~/pirogue-deploy
#   sudo bash deploy-vps.sh
#
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

# ---------------------------------------------------------------------------
# 1. Install system dependencies (NO Java — native signal-cli doesn't need it)
# ---------------------------------------------------------------------------
log "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip jq curl nginx

# ---------------------------------------------------------------------------
# 2. Install Python dependencies
# ---------------------------------------------------------------------------
log "Installing Python packages..."
pip3 install --break-system-packages httpx

# ---------------------------------------------------------------------------
# 3. Install signal-cli (NATIVE build — no Java dependency)
# ---------------------------------------------------------------------------
if command -v signal-cli &>/dev/null; then
    log "signal-cli already installed: $(signal-cli --version 2>&1 | head -1)"
else
    log "Installing signal-cli (native build — no Java required)..."
    SIGNAL_CLI_VERSION=$(curl -Ls -o /dev/null -w '%{url_effective}' \
        https://github.com/AsamK/signal-cli/releases/latest | sed -e 's/^.*\/v//')
    log "Latest version: ${SIGNAL_CLI_VERSION}"

    curl -L -o /tmp/signal-cli-native.tar.gz \
        "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux-native.tar.gz"
    rm -rf /opt/signal-cli /opt/signal-cli-*
    tar xf /tmp/signal-cli-native.tar.gz -C /opt/
    ln -sf /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli
    rm /tmp/signal-cli-native.tar.gz
    log "signal-cli installed: $(signal-cli --version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
# 4. Deploy triage daemon
# ---------------------------------------------------------------------------
log "Deploying triage daemon..."

mkdir -p /opt/pirogue-triage
mkdir -p /etc/pirogue-triage
mkdir -p /var/log/pirogue-triage
mkdir -p /var/lib/pirogue-triage

cp pirogue-triage-daemon.py /opt/pirogue-triage/
chmod 755 /opt/pirogue-triage/pirogue-triage-daemon.py

# Config (don't overwrite if exists)
if [ ! -f /etc/pirogue-triage/config.toml ]; then
    cp config.toml /etc/pirogue-triage/config.toml
    log "Config deployed to /etc/pirogue-triage/config.toml"
    warn "EDIT THIS FILE with your Signal number: sudo nano /etc/pirogue-triage/config.toml"
else
    log "Config already exists — not overwriting"
fi

# Env file for API key
if [ ! -f /etc/pirogue-triage/env ]; then
    echo "# Set your Anthropic API key here" > /etc/pirogue-triage/env
    echo "ANTHROPIC_API_KEY=" >> /etc/pirogue-triage/env
    chmod 600 /etc/pirogue-triage/env
    warn "SET YOUR API KEY: sudo nano /etc/pirogue-triage/env"
fi

# Fix ownership — daemon runs as pirogue user (must match signal-cli link user)
chown -R pirogue:pirogue /var/log/pirogue-triage
chown -R pirogue:pirogue /var/lib/pirogue-triage
chown root:pirogue /etc/pirogue-triage/config.toml
chown root:pirogue /etc/pirogue-triage/env
chmod 640 /etc/pirogue-triage/config.toml
chmod 640 /etc/pirogue-triage/env

# ---------------------------------------------------------------------------
# 5. Deploy systemd service
# ---------------------------------------------------------------------------
log "Installing systemd service..."
cp pirogue-triage.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable pirogue-triage
log "Service installed and enabled (not started yet)"

# ---------------------------------------------------------------------------
# 6. Deploy demo rules
# ---------------------------------------------------------------------------
# PiRogue uses /var/lib/suricata/rules/ as default-rule-path (NOT /etc/suricata/rules/)
RULES_DIR="/var/lib/suricata/rules"
if [ -f demo-rules.rules ] && [ -d "$RULES_DIR" ]; then
    cp demo-rules.rules "$RULES_DIR/"
    log "Demo Suricata rules deployed to ${RULES_DIR}/demo-rules.rules"
    warn "Add '  - demo-rules.rules' under rule-files: in /etc/suricata/suricata.yaml"
    warn "See demo-site/SURICATA_CONFIG.md for all required Suricata config changes"
else
    warn "demo-rules.rules or ${RULES_DIR} not found — skipping"
fi

# ---------------------------------------------------------------------------
# 7. Deploy agent docs (for Claude agent context)
# ---------------------------------------------------------------------------
AGENT_DIR="/home/pirogue/pirogue-ops"
if [ -d "$AGENT_DIR" ]; then
    cp -r ../agent-docs "$AGENT_DIR/" 2>/dev/null || true
    cp ../CLAUDE.md "$AGENT_DIR/" 2>/dev/null || true
    chown -R pirogue:pirogue "$AGENT_DIR/agent-docs" "$AGENT_DIR/CLAUDE.md" 2>/dev/null || true
    log "Agent docs deployed to ${AGENT_DIR}/agent-docs/"
else
    warn "Agent project dir not found at ${AGENT_DIR} — copy agent-docs/ and CLAUDE.md manually"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Deployment complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Link signal-cli (as the pirogue user):"
echo "     sudo -u pirogue signal-cli link -n \"pirogue-vps\""
echo "     (Scan the QR code with Signal on your phone)"
echo ""
echo "  2. Receive pending messages to sync encryption:"
echo "     sudo -u pirogue signal-cli -a +1YOURNUMBER receive"
echo ""
echo "  3. Set your Anthropic API key:"
echo "     echo 'ANTHROPIC_API_KEY=sk-ant-...' | sudo tee /etc/pirogue-triage/env"
echo ""
echo "  4. Edit the config with your Signal number:"
echo "     sudo nano /etc/pirogue-triage/config.toml"
echo ""
echo "  5. Apply Suricata config changes (see demo-site/SURICATA_CONFIG.md):"
echo "     - Add failure-fatal: no"
echo "     - Add second eve-log block (filetype: regular)"
echo "     - Enable ja3-fingerprints: yes"
echo "     - Add demo-rules.rules to rule-files"
echo ""
echo "  6. Restart services:"
echo "     sudo systemctl restart suricata"
echo "     sudo systemctl start pirogue-triage"
echo "     sudo journalctl -u pirogue-triage -f"
echo ""
