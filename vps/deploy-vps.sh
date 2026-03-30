#!/usr/bin/env bash
# =============================================================================
# deploy-vps.sh — Deploy triage daemon + signal-cli on the PiRogue VPS
# =============================================================================
#
# Run this on the Debian VPS AFTER PiRogue is already installed and running.
# It installs signal-cli, the triage daemon, and sets up the systemd service.
#
# Usage:
#   scp deploy-vps.sh pirogue-triage-daemon.py config.toml pirogue-triage.service user@vps:~/
#   ssh user@vps
#   sudo bash deploy-vps.sh
#
# After running, you still need to:
#   1. Link signal-cli: sudo -u pirogue-triage signal-cli link -n "pirogue-vps"
#   2. Set your API key: echo 'ANTHROPIC_API_KEY=sk-ant-...' | sudo tee /etc/pirogue-triage/env
#   3. Edit config: sudo nano /etc/pirogue-triage/config.toml
#   4. Start the service: sudo systemctl start pirogue-triage
#
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Must be root
[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

# ---------------------------------------------------------------------------
# 1. Install system dependencies
# ---------------------------------------------------------------------------
log "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip jq curl

# ---------------------------------------------------------------------------
# 2. Install Python dependencies
# ---------------------------------------------------------------------------
log "Installing Python packages..."
pip3 install --break-system-packages httpx

# ---------------------------------------------------------------------------
# 3. Install signal-cli
# ---------------------------------------------------------------------------
if command -v signal-cli &>/dev/null; then
    log "signal-cli already installed: $(signal-cli --version 2>&1 | head -1)"
else
    log "Installing signal-cli (native build — no Java required)..."
    SIGNAL_CLI_VERSION=$(curl -Ls -o /dev/null -w '%{url_effective}' \
        https://github.com/AsamK/signal-cli/releases/latest | sed -e 's/^.*\/v//')
    log "Latest version: ${SIGNAL_CLI_VERSION}"

    # Use the native Linux build (GraalVM-compiled, no JVM dependency)
    curl -L -o /tmp/signal-cli-native.tar.gz \
        "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux-native.tar.gz"
    # Remove old installations if present
    rm -rf /opt/signal-cli /opt/signal-cli-*
    tar xf /tmp/signal-cli-native.tar.gz -C /opt/
    ln -sf /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli
    rm /tmp/signal-cli-native.tar.gz
    log "signal-cli installed: $(signal-cli --version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
# 4. Create service user
# ---------------------------------------------------------------------------
if id pirogue-triage &>/dev/null; then
    log "User pirogue-triage already exists"
else
    log "Creating pirogue-triage service user..."
    useradd --system --create-home --shell /usr/sbin/nologin pirogue-triage
    # Add to suricata group so it can read eve.json
    usermod -aG suricata pirogue-triage 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 5. Deploy triage daemon
# ---------------------------------------------------------------------------
log "Deploying triage daemon..."

# Create directories
mkdir -p /opt/pirogue-triage
mkdir -p /etc/pirogue-triage
mkdir -p /var/log/pirogue-triage
mkdir -p /var/lib/pirogue-triage

# Copy files
cp pirogue-triage-daemon.py /opt/pirogue-triage/
chmod 755 /opt/pirogue-triage/pirogue-triage-daemon.py

# Config (don't overwrite if exists)
if [ ! -f /etc/pirogue-triage/config.toml ]; then
    cp config.toml /etc/pirogue-triage/config.toml
    log "Config deployed to /etc/pirogue-triage/config.toml"
    warn "EDIT THIS FILE: sudo nano /etc/pirogue-triage/config.toml"
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

# Fix ownership
chown -R pirogue-triage:pirogue-triage /var/log/pirogue-triage
chown -R pirogue-triage:pirogue-triage /var/lib/pirogue-triage
chown -R root:pirogue-triage /etc/pirogue-triage
chmod 640 /etc/pirogue-triage/config.toml
chmod 640 /etc/pirogue-triage/env

# ---------------------------------------------------------------------------
# 6. Deploy systemd service
# ---------------------------------------------------------------------------
log "Installing systemd service..."
cp pirogue-triage.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable pirogue-triage
log "Service installed and enabled (not started yet)"

# ---------------------------------------------------------------------------
# 7. Deploy demo rules (optional)
# ---------------------------------------------------------------------------
if [ -f demo-rules.rules ]; then
    SURICATA_RULES_DIR="/etc/suricata/rules"
    if [ -d "$SURICATA_RULES_DIR" ]; then
        cp demo-rules.rules "$SURICATA_RULES_DIR/"
        log "Demo Suricata rules deployed to ${SURICATA_RULES_DIR}/demo-rules.rules"
        warn "Add 'demo-rules.rules' to suricata.yaml under rule-files, then:"
        warn "  suricatasc -c reload-rules"
    else
        warn "Suricata rules dir not found at ${SURICATA_RULES_DIR} — skipping demo rules"
    fi
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
echo "  1. Link signal-cli to your Signal account:"
echo "     sudo -u pirogue-triage signal-cli link -n \"pirogue-vps\""
echo "     (Scan the QR code with Signal on your phone)"
echo ""
echo "  2. Set your Anthropic API key:"
echo "     echo 'ANTHROPIC_API_KEY=sk-ant-your-key-here' | sudo tee /etc/pirogue-triage/env"
echo ""
echo "  3. Edit the config with your Signal number:"
echo "     sudo nano /etc/pirogue-triage/config.toml"
echo ""
echo "  4. Test signal-cli:"
echo "     sudo -u pirogue-triage signal-cli -a +1YOURNUMBER send -m 'test' +1YOURNUMBER"
echo ""
echo "  5. Start the service:"
echo "     sudo systemctl start pirogue-triage"
echo "     sudo journalctl -u pirogue-triage -f"
echo ""
echo "  6. If using demo rules, add to suricata.yaml and reload:"
echo "     suricatasc -c reload-rules"
echo ""
