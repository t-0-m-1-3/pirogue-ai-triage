#!/usr/bin/env bash
# =============================================================================
# setup-demo-user.sh — Create the demo-site service user on the PiRogue VPS
# =============================================================================
# Run as root: sudo bash setup-demo-user.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

USERNAME="demo-site"
WEB_ROOT="/var/www/isitransomware.org"
SSL_DIR="/etc/ssl/cloudflare"
LOG_DIR="/var/log/nginx"

# Create system user (no login, no home dir needed)
if id "$USERNAME" &>/dev/null; then
    log "User $USERNAME already exists"
else
    useradd \
        --system \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --comment "isitransomware.org demo site" \
        "$USERNAME"
    log "Created system user: $USERNAME"
fi

# Add to www-data group so nginx can serve files owned by this user
usermod -aG www-data "$USERNAME"
log "Added $USERNAME to www-data group"

# Create web root
mkdir -p "$WEB_ROOT"
chown "$USERNAME":www-data "$WEB_ROOT"
chmod 755 "$WEB_ROOT"
log "Created web root: $WEB_ROOT (owned by $USERNAME:www-data)"

# Create SSL dir for Cloudflare origin cert
mkdir -p "$SSL_DIR"
chown root:root "$SSL_DIR"
chmod 750 "$SSL_DIR"
log "Created SSL dir: $SSL_DIR"

# Ensure nginx log dir exists with correct perms
mkdir -p "$LOG_DIR"
chown www-data:adm "$LOG_DIR"
log "Verified log dir: $LOG_DIR"

echo ""
log "Done. Next steps:"
echo "  1. Copy index.html:  sudo -u $USERNAME cp www/index.html $WEB_ROOT/"
echo "  2. Add origin cert:  sudo nano $SSL_DIR/isitransomware.org.pem"
echo "  3. Add private key:  sudo nano $SSL_DIR/isitransomware.org.key"
echo "     Then:             sudo chmod 600 $SSL_DIR/isitransomware.org.key"
echo "  4. Deploy nginx cfg: sudo cp isitransomware.org.conf /etc/nginx/sites-available/"
echo "     Link it:          sudo ln -sf /etc/nginx/sites-available/isitransomware.org /etc/nginx/sites-enabled/"
echo "  5. Test + reload:    sudo nginx -t && sudo systemctl reload nginx"
