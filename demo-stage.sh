#!/usr/bin/env bash
# =============================================================================
# demo-stage.sh — tmux layout for live conference demo
# =============================================================================
# Run this on your NixOS laptop before walking on stage.
# It SSHes into the VPS and sets up a 4-pane view:
#
#   ┌─────────────────────┬─────────────────────┐
#   │                     │                     │
#   │  VPS Interactive    │  eve.json alerts    │
#   │  (SSH shell)        │  (live tail)        │
#   │                     │                     │
#   ├─────────────────────┼─────────────────────┤
#   │                     │                     │
#   │  Triage Daemon Log  │  Signal-cli Log     │
#   │  (live output)      │  (send confirmations)│
#   │                     │                     │
#   └─────────────────────┴─────────────────────┘
#
# Usage:
#   chmod +x demo-stage.sh
#   ./demo-stage.sh
#
# Prerequisites:
#   - SSH key auth to VPS (no password prompts on stage!)
#   - tmux installed
#   - Triage daemon already running on VPS as a service
#   - Font size in terminal set to 18-20pt for audience visibility
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION — Edit these before the talk
# ---------------------------------------------------------------------------

VPS_HOST="pirogue.ofpanalytics.com"
VPS_USER="pirogue"                             # or your sudo user
SSH_KEY="$HOME/.ssh/id_ed25519_sk"             # dedicated key for demo
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

EVE_JSON="/var/log/suricata/eve.json"
TRIAGE_LOG="/var/log/pirogue-triage/triage.log"

SESSION_NAME="pirogue-demo"
FONT_NOTE="Set your terminal font to 18-20pt for audience visibility"

# ---------------------------------------------------------------------------
# Color config for the demo (makes the terminal output pop on projector)
# ---------------------------------------------------------------------------

# ANSI color codes for the header banners
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  PiRogue Demo Stage Layout                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Check tmux
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}ERROR: tmux not found. Add it to your shell.nix.${NC}"
    exit 1
fi

# Check SSH connectivity
echo -e "${YELLOW}Testing SSH connection to ${VPS_HOST}...${NC}"
if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${VPS_USER}@${VPS_HOST}" "echo OK" 2>/dev/null; then
    echo -e "${GREEN}SSH connection OK${NC}"
else
    echo -e "${RED}ERROR: Cannot SSH to ${VPS_HOST}. Check your config.${NC}"
    exit 1
fi

# Check VPS services
echo -e "${YELLOW}Checking VPS services...${NC}"
ssh ${SSH_OPTS} -i "${SSH_KEY}" "${VPS_USER}@${VPS_HOST}" bash -s << 'REMOTE_CHECK'
    ok=true
    for svc in suricata pirogue-triage; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "  ✓ $svc is running"
        else
            echo "  ✗ $svc is NOT running"
            ok=false
        fi
    done
    if command -v signal-cli &>/dev/null; then
        echo "  ✓ signal-cli is available"
    else
        echo "  ✗ signal-cli NOT found"
        ok=false
    fi
    if [ "$ok" = false ]; then
        exit 1
    fi
REMOTE_CHECK

if [ $? -ne 0 ]; then
    echo -e "${RED}WARNING: Some VPS services are not running. Fix before going on stage.${NC}"
    echo -e "${YELLOW}Continue anyway? (y/n)${NC}"
    read -r answer
    [[ "$answer" != "y" ]] && exit 1
fi

echo -e "${GREEN}All checks passed.${NC}"
echo ""
echo -e "${YELLOW}$FONT_NOTE${NC}"
echo ""
echo -e "Press ${GREEN}Enter${NC} to launch the demo layout..."
read -r

# ---------------------------------------------------------------------------
# Kill existing session if any
# ---------------------------------------------------------------------------

tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Build the layout
# ---------------------------------------------------------------------------

SSH_CMD="ssh ${SSH_OPTS} -i ${SSH_KEY} ${VPS_USER}@${VPS_HOST}"

# Create session with first pane (top-left: interactive SSH)
tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50

# Top-left pane: Interactive SSH shell
# This is where you'll run ad-hoc commands during the demo
tmux send-keys -t "$SESSION_NAME" \
    "${SSH_CMD} -t 'echo -e \"\\033[1;36m=== VPS INTERACTIVE ===${NC}\\033[0m\"; exec bash -l'" Enter

# Create top-right pane: eve.json alert tail
tmux split-window -h -t "$SESSION_NAME"
tmux send-keys -t "$SESSION_NAME" \
    "${SSH_CMD} -t 'echo -e \"\\033[1;33m=== SURICATA ALERTS ===${NC}\\033[0m\"; tail -f ${EVE_JSON} | jq --unbuffered -c \"select(.event_type==\\\"alert\\\") | {timestamp, src_ip, dest_ip, alert: {signature, signature_id, severity}}\"'" Enter

# Create bottom-left pane: Triage daemon log
tmux split-window -v -t "$SESSION_NAME.0"
tmux send-keys -t "$SESSION_NAME" \
    "${SSH_CMD} -t 'echo -e \"\\033[1;32m=== AI TRIAGE DAEMON ===${NC}\\033[0m\"; tail -f ${TRIAGE_LOG}'" Enter

# Create bottom-right pane: signal-cli send log / general monitor
tmux split-window -v -t "$SESSION_NAME.1"
tmux send-keys -t "$SESSION_NAME" \
    "${SSH_CMD} -t 'echo -e \"\\033[1;35m=== SIGNAL ALERTS ===${NC}\\033[0m\"; journalctl -u pirogue-triage -f --no-hostname | grep --line-buffered -i signal'" Enter

# Even out the panes
tmux select-layout -t "$SESSION_NAME" tiled

# Focus on top-left pane (interactive)
tmux select-pane -t "$SESSION_NAME.0"

# ---------------------------------------------------------------------------
# Attach
# ---------------------------------------------------------------------------

echo -e "${GREEN}Demo layout ready. Attaching to tmux session...${NC}"
tmux attach-session -t "$SESSION_NAME"
