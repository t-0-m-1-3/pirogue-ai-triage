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
WEB_ROOT="/var/www/your-demo-domain.com"
SSL_DIR="/etc/ssl/cloudflare"

if id "$USERNAME" &>/dev/null; then
    log "User $USERNAME already exists"
else
    useradd --system --no-create-home --shell /usr/sbin/nologin \
        --comment "your-demo-domain.com demo site" "$USERNAME"
    log "Created system user: $USERNAME"
fi

usermod -aG www-data "$USERNAME"
log "Added $USERNAME to www-data group"

mkdir -p "$WEB_ROOT"
chown "$USERNAME":www-data "$WEB_ROOT"
chmod 755 "$WEB_ROOT"
log "Created web root: $WEB_ROOT"

mkdir -p "$SSL_DIR"
chown root:root "$SSL_DIR"
chmod 750 "$SSL_DIR"
log "Created SSL dir: $SSL_DIR"

echo ""
log "Done. Next steps:"
echo "  1. Copy landing page:  sudo cp www/index.html $WEB_ROOT/"
echo "  2. Add origin cert:    sudo nano $SSL_DIR/your-demo-domain.com.pem"
echo "  3. Add private key:    sudo nano $SSL_DIR/your-demo-domain.com.key"
echo "     Fix permissions:    sudo chown root:root $SSL_DIR/*"
echo "                         sudo chmod 600 $SSL_DIR/your-demo-domain.com.key"
echo "  4. Edit nginx config:  Replace YOUR_VPS_IP in your-demo-domain.com.conf"
echo "  5. Deploy nginx cfg:   sudo cp your-demo-domain.com.conf /etc/nginx/sites-available/"
echo "     Link it:            sudo ln -sf /etc/nginx/sites-available/your-demo-domain.com /etc/nginx/sites-enabled/"
echo "  6. Test + restart:     sudo nginx -t && sudo systemctl restart nginx"
