# Cloudflare + Demo Site Setup for your-demo-domain.com

## Overview

This sets up your-demo-domain.com pointed at your PiRogue VPS through Cloudflare,
serving a demo landing page and fake C2 endpoints that your Suricata rules
trigger on during the conference talk.

**Important for the demo:** The phone's DNS queries to your-demo-domain.com need
to be visible to Suricata on the VPS. Since the phone's traffic routes through
WireGuard, Suricata sees the DNS queries BEFORE they reach Cloudflare. This
means the DNS trigger (rule 9999901) works regardless of Cloudflare's proxy
status. The HTTP beacon rule (9999904) requires the request to actually reach
your nginx, so Cloudflare just needs to forward traffic to your origin.

---

## Step 1: Add Domain to Cloudflare

1. Log in to [dash.cloudflare.com](https://dash.cloudflare.com)
2. Click **Add a site** → enter `your-demo-domain.com`
3. Select the **Free** plan
4. Cloudflare will scan existing DNS records — clear any that don't apply
5. Cloudflare gives you two nameservers (e.g., `ada.ns.cloudflare.com`, `ben.ns.cloudflare.com`)
6. Go to your domain registrar and **update nameservers** to the Cloudflare pair
7. Back in Cloudflare, click **Done, check nameservers**
8. Wait for propagation (usually 5–30 minutes, can take up to 24h)

Verify:
```bash
dig NS your-demo-domain.com +short
# Should return the Cloudflare nameservers
```

---

## Step 2: Configure DNS Records

In Cloudflare dashboard → **DNS** → **Records**, add:

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `your-demo-domain.com` | `YOUR_VPS_IP` | Proxied (orange cloud) | Auto |
| A | `www` | `YOUR_VPS_IP` | Proxied (orange cloud) | Auto |
| A | `tracker` | `YOUR_VPS_IP` | Proxied (orange cloud) | Auto |

**Note on proxy status:** For the live demo, the DNS trigger (SID 9999901) fires
on the DNS query itself, which Suricata sees in the WireGuard tunnel before
Cloudflare is involved. So proxy on/off doesn't affect the primary demo trigger.
Keep it proxied for DDoS protection on your VPS.

For the DNS TXT exfil demo (SID 9999905), you need a wildcard or the specific
subdomain. Add:

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `exfil-test` | `YOUR_VPS_IP` | DNS only (gray cloud) | Auto |

The `exfil-test` subdomain should be **DNS only** (gray cloud) because the
Suricata rule triggers on the DNS TXT query, and proxying would hide the
query type from your resolver.

Verify:
```bash
dig your-demo-domain.com +short
# Should return a Cloudflare IP (proxied) or your VPS IP (DNS only)

dig tracker.your-demo-domain.com +short
# Same

dig exfil-test.your-demo-domain.com +short
# Should return your VPS IP directly (gray cloud)
```

---

## Step 3: SSL/TLS Configuration

In Cloudflare dashboard → **SSL/TLS**:

1. Set encryption mode to **Full (strict)**
2. Go to **Origin Server** → **Create Certificate**
3. Options:
   - Generate private key and CSR with Cloudflare: **RSA (2048)**
   - Hostnames: `your-demo-domain.com`, `*.your-demo-domain.com`
   - Certificate validity: **15 years** (it's a demo domain)
4. Click **Create**
5. Cloudflare shows the **Origin Certificate** and **Private Key**
6. **Copy both** — you won't see the private key again

On the VPS, save the certificate and key:

```bash
sudo mkdir -p /etc/ssl/cloudflare

# Paste the origin certificate
sudo nano /etc/ssl/cloudflare/your-demo-domain.com.pem
# Paste the full certificate (-----BEGIN CERTIFICATE----- ... -----END CERTIFICATE-----)

# Paste the private key
sudo nano /etc/ssl/cloudflare/your-demo-domain.com.key
# Paste the full key (-----BEGIN PRIVATE KEY----- ... -----END PRIVATE KEY-----)

# Lock down permissions
sudo chmod 600 /etc/ssl/cloudflare/your-demo-domain.com.key
sudo chmod 644 /etc/ssl/cloudflare/your-demo-domain.com.pem
```

---

## Step 4: Cloudflare Security Settings

In Cloudflare dashboard → **Security**:

1. **WAF**: Leave default rules enabled — they won't interfere with demo traffic
2. **Bot Management**: Not needed on free plan
3. **Under Attack Mode**: Leave OFF (would add a challenge page in front of your demo)

In **Speed** → **Optimization**:

1. **Auto Minify**: OFF for HTML (so the landing page source stays readable if anyone views it)
2. **Brotli**: ON (fine, doesn't affect the demo)

In **Caching**:

1. **Caching Level**: Standard
2. For testing, you can **purge cache** if you update the landing page

---

## Step 5: Deploy the Demo Site on the VPS

```bash
# Install nginx if not present
sudo apt install -y nginx

# Create web root
sudo mkdir -p /var/www/your-demo-domain.com

# Copy the landing page
sudo cp www/index.html /var/www/your-demo-domain.com/index.html

# Deploy nginx config
sudo cp your-demo-domain.com.conf /etc/nginx/sites-available/your-demo-domain.com
sudo ln -sf /etc/nginx/sites-available/your-demo-domain.com /etc/nginx/sites-enabled/

# Remove default site if it conflicts on port 80
sudo rm -f /etc/nginx/sites-enabled/default

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

Verify locally on the VPS:
```bash
curl -s http://localhost/health
# Should return: ok

curl -s http://localhost/ | head -5
# Should return the HTML of the landing page
```

Verify externally (after DNS propagates):
```bash
curl -s https://your-demo-domain.com/health
# Should return: ok

curl -s http://your-demo-domain.com/gate.php
# Should return: {"status":"ok","id":"demo","ts":"..."}
```

---

## Step 6: Deploy Updated Suricata Rules

```bash
# Copy the updated rules (with your-demo-domain.com)
sudo cp demo-rules.rules /etc/suricata/rules/demo-rules.rules

# Make sure demo-rules.rules is listed in suricata.yaml
sudo grep -q "demo-rules.rules" /etc/suricata/suricata.yaml || \
  echo "  - demo-rules.rules" | sudo tee -a /etc/suricata/suricata.yaml

# Reload rules
sudo suricatasc -c reload-rules

# Verify rule is loaded
sudo suricatasc -c "ruleset-stats" | grep -i loaded
```

---

## Step 7: Full End-to-End Test

With a phone connected via WireGuard:

```bash
# On the VPS, start watching alerts
tail -f /var/log/suricata/eve.json | jq --unbuffered 'select(.event_type=="alert")'

# On the phone (or via demo-trigger.sh through tunnel):
# 1. Open browser → navigate to your-demo-domain.com
#    → Should fire SID 9999901 (DNS C2 domain)
#
# 2. In Termux: curl -A "Mozilla/5.0 (compatible; BabyShark/2.0)" http://your-demo-domain.com/gate.php
#    → Should fire SID 9999904 (HTTP beacon UA)
#
# 3. In Termux: dig TXT exfil-test.your-demo-domain.com
#    → Should fire SID 9999905 (DNS TXT exfil)
```

Check that the triage daemon picks them up:
```bash
sudo journalctl -u pirogue-triage -f --no-hostname
```

Check that Signal notifications arrive on your phone.

---

## Timing Expectations

| Step | Expected time |
|------|--------------|
| Phone opens browser → DNS query visible in eve.json | < 1 second |
| Suricata alert fires | < 1 second |
| Triage daemon detects alert | < 2 seconds |
| Claude API triage response | 2–5 seconds |
| Signal notification arrives on phone | 1–3 seconds |
| **Total: trigger → notification** | **5–12 seconds** |

---

## Troubleshooting

**nginx won't start: "address already in use"**
Another service (Apache, PiRogue dashboard) is using port 80/443. Check with
`sudo ss -tlnp | grep -E ':80|:443'` and either stop the conflicting service
or adjust nginx to listen on different ports.

**curl works locally but not externally**
DNS hasn't propagated yet. Check `dig your-demo-domain.com` — if it still shows
old nameservers, wait. You can also test by curling the VPS IP directly with
a Host header: `curl -H "Host: your-demo-domain.com" http://YOUR_VPS_IP/health`

**HTTPS returns Cloudflare 526 error**
The origin certificate isn't configured correctly. Verify the cert files exist
at `/etc/ssl/cloudflare/` and that nginx can read them. Check `sudo nginx -t`
for specific errors.

**Suricata doesn't fire on DNS queries**
Make sure the phone is using the VPS's DNS resolver (through WireGuard), not
a local or DoH resolver. Check WireGuard config on the phone — DNS should be
set to the VPS's WireGuard IP (e.g., 10.8.0.1). Also verify the rules are
loaded: `sudo suricatasc -c "ruleset-stats"`

**HTTP beacon rule (9999904) doesn't fire**
This rule requires plain HTTP (port 80), not HTTPS. If Cloudflare is forcing
HTTPS redirects, the request never reaches your origin over HTTP. In Cloudflare
→ **SSL/TLS** → **Edge Certificates** → turn OFF **Always Use HTTPS** for
testing. Alternatively, the phone can send the curl command directly to the
VPS IP over HTTP bypassing Cloudflare entirely (it still goes through WireGuard
so Suricata sees it).
