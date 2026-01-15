#!/bin/bash
set -e

echo "Enter domain name (example: api.example.com):"
read DOMAIN

echo "Enter email for SSL certificate:"
read SSL_EMAIL

echo "🔹 Updating system..."
apt update -y

echo "🔹 Installing Nginx & Certbot..."
apt install -y nginx certbot

echo "🔹 Stopping services using port 80..."
systemctl stop nginx || true
fuser -k 80/tcp || true

echo "🔹 Obtaining SSL certificate (standalone mode)..."
certbot certonly \
  --standalone \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  -m "$SSL_EMAIL"

echo "🔹 Creating HTTPS-only NGINX config..."

NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

cat > "$NGINX_CONF" <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:80;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

echo "🔹 Enabling NGINX config..."
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo "🔹 Testing and starting NGINX..."
nginx -t
systemctl start nginx
systemctl enable nginx

echo "🔹 Enabling auto-renew..."
systemctl enable certbot.timer
systemctl start certbot.timer

echo ""
echo "✅ HTTPS ENABLED SUCCESSFULLY"
echo "🔐 https://$DOMAIN"
echo "➡️  HTTPS → App on port 80"
echo ""
