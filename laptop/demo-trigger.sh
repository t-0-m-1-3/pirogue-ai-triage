#!/usr/bin/env bash
# =============================================================================
# demo-trigger.sh — Fire demo Suricata rules against your-demo-domain.com
# =============================================================================
#
# Usage:
#   ./demo-trigger.sh dns        # Trigger 1: DNS C2 domain (PRIMARY - use this on stage)
#   ./demo-trigger.sh stalker    # Trigger 2: Stalkerware subdomain
#   ./demo-trigger.sh ja3        # Trigger 3: JA3 fingerprint match
#   ./demo-trigger.sh beacon     # Trigger 4: HTTP C2 beacon user-agent
#   ./demo-trigger.sh exfil      # Trigger 5: DNS TXT exfiltration
#   ./demo-trigger.sh all        # Fire all triggers in sequence (for pre-talk testing)
#
# Run through the WireGuard tunnel so Suricata sees the traffic.
# =============================================================================

set -euo pipefail

DEMO_DOMAIN="your-demo-domain.com"
STALKER_DOMAIN="tracker.your-demo-domain.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

trigger_dns() {
    echo -e "${CYAN}[Trigger 1] DNS C2 Domain Resolution${NC}"
    echo -e "  Resolving ${YELLOW}${DEMO_DOMAIN}${NC}..."
    if command -v dig &>/dev/null; then
        dig "$DEMO_DOMAIN" +short 2>&1 || true
    elif command -v nslookup &>/dev/null; then
        nslookup "$DEMO_DOMAIN" 2>&1 || true
    else
        curl -s -o /dev/null --connect-timeout 5 "http://${DEMO_DOMAIN}/" 2>&1 || true
    fi
    echo -e "${GREEN}  ✓ DNS query sent — check eve.json for SID 9999901${NC}"
}

trigger_stalker() {
    echo -e "${CYAN}[Trigger 2] Stalkerware Subdomain Resolution${NC}"
    echo -e "  Resolving ${YELLOW}${STALKER_DOMAIN}${NC}..."
    if command -v dig &>/dev/null; then
        dig "$STALKER_DOMAIN" +short 2>&1 || true
    elif command -v nslookup &>/dev/null; then
        nslookup "$STALKER_DOMAIN" 2>&1 || true
    else
        curl -s -o /dev/null --connect-timeout 5 "http://${STALKER_DOMAIN}/" 2>&1 || true
    fi
    echo -e "${GREEN}  ✓ DNS query sent — check eve.json for SID 9999902${NC}"
}

trigger_ja3() {
    echo -e "${CYAN}[Trigger 3] JA3 Fingerprint Match${NC}"
    echo -e "  Sending TLS request with forced cipher suite..."
    curl -s -o /dev/null \
        --tlsv1.2 --tls-max 1.2 \
        --ciphers ECDHE-RSA-AES128-GCM-SHA256 \
        --connect-timeout 10 \
        "https://${DEMO_DOMAIN}/beacon" 2>&1 || true
    echo -e "${GREEN}  ✓ TLS handshake sent — check eve.json for SID 9999903${NC}"
    echo -e "${YELLOW}  NOTE: JA3 hash in the rule must match your observed hash.${NC}"
    echo -e "${YELLOW}  First run? Capture it: jq 'select(.event_type==\"tls\") | .tls.ja3.hash' eve.json | tail -5${NC}"
}

trigger_beacon() {
    echo -e "${CYAN}[Trigger 4] HTTP C2 Beacon (Suspicious User-Agent)${NC}"
    echo -e "  Sending HTTP request with malicious UA string..."
    # Plain HTTP so Suricata can inspect the User-Agent header
    curl -s -o /dev/null \
        -A "Mozilla/5.0 (compatible; BabyShark/2.0)" \
        --connect-timeout 10 \
        "http://${DEMO_DOMAIN}/gate.php" 2>&1 || true
    echo -e "${GREEN}  ✓ HTTP request sent — check eve.json for SID 9999904${NC}"
}

trigger_exfil() {
    echo -e "${CYAN}[Trigger 5] DNS TXT Exfiltration Simulation${NC}"
    echo -e "  Sending DNS TXT query..."
    if command -v dig &>/dev/null; then
        dig TXT "exfil-test.${DEMO_DOMAIN}" +short 2>&1 || true
    elif command -v nslookup &>/dev/null; then
        nslookup -type=TXT "exfil-test.${DEMO_DOMAIN}" 2>&1 || true
    else
        echo -e "${RED}  No DNS tool available (need dig or nslookup)${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ DNS TXT query sent — check eve.json for SID 9999905${NC}"
}

trigger_all() {
    echo -e "${CYAN}Firing all demo triggers with 10s gaps...${NC}"
    echo ""
    trigger_dns
    echo ""; echo -e "${YELLOW}  Waiting 10s...${NC}"; sleep 10
    trigger_stalker
    echo ""; echo -e "${YELLOW}  Waiting 10s...${NC}"; sleep 10
    trigger_ja3
    echo ""; echo -e "${YELLOW}  Waiting 10s...${NC}"; sleep 10
    trigger_beacon
    echo ""; echo -e "${YELLOW}  Waiting 10s...${NC}"; sleep 10
    trigger_exfil
    echo ""
    echo -e "${GREEN}All triggers fired.${NC}"
}

show_help() {
    echo "Usage: $0 <trigger>"
    echo ""
    echo "Domain: ${DEMO_DOMAIN}"
    echo ""
    echo "Triggers:"
    echo "  dns        DNS C2 domain resolution (SID 9999901) — PRIMARY DEMO"
    echo "  stalker    Stalkerware subdomain (SID 9999902)"
    echo "  ja3        JA3 fingerprint match (SID 9999903)"
    echo "  beacon     HTTP beacon user-agent (SID 9999904)"
    echo "  exfil      DNS TXT exfiltration (SID 9999905)"
    echo "  all        Fire all triggers with 10s gaps"
}

case "${1:-help}" in
    dns)     trigger_dns ;;
    stalker) trigger_stalker ;;
    ja3)     trigger_ja3 ;;
    beacon)  trigger_beacon ;;
    exfil)   trigger_exfil ;;
    all)     trigger_all ;;
    *)       show_help ;;
esac
