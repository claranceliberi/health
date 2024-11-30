#!/bin/bash

# Install required packages
sudo apt update
sudo apt install -y certbot python3-certbot-nginx nginx net-tools

# Create webroot directory
sudo mkdir -p /var/www/letsencrypt
sudo chown www-data:www-data /var/www/letsencrypt

# Configure nginx for certbot verification
sudo tee /etc/nginx/sites-available/letsencrypt <<EOF
server {
    listen 80;
    server_name claranceliberi.tech www.claranceliberi.tech health.claranceliberi.tech lb-01.claranceliberi.tech;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/letsencrypt /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Stop HAProxy temporarily
sudo systemctl stop haproxy

# Function to get certificate with retry
get_certificate() {
    local max_attempts=3
    local attempt=1
    local wait_time=30

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts to get certificate..."

        sudo certbot certonly --webroot \
            --webroot-path /var/www/letsencrypt \
            -d claranceliberi.tech \
            -d www.claranceliberi.tech \
            -d health.claranceliberi.tech \
            -d lb-01.claranceliberi.tech \
            --agree-tos \
            --expand \
            --non-interactive \
            --email liberintwari@gmail.com

        if [ $? -eq 0 ]; then
            echo "Certificate obtained successfully!"
            break
        else
            echo "Failed to get certificate. Waiting ${wait_time}s before retry..."
            sleep $wait_time
            wait_time=$((wait_time * 2))
            attempt=$((attempt + 1))
        fi
    done

    if [ $attempt -gt $max_attempts ]; then
        echo "Failed to get certificate after $max_attempts attempts"
        exit 1
    fi
}

# Create certificates directory if it doesn't exist
sudo mkdir -p /etc/haproxy/certs

# Get certificate
get_certificate

# Find the certificate directory
echo "Checking certificate directories..."
CERT_DIR=""
for domain in "www.claranceliberi.tech" "claranceliberi.tech"; do
    echo "Checking /etc/letsencrypt/live/$domain"
    if sudo test -d "/etc/letsencrypt/live/$domain"; then
        if sudo test -f "/etc/letsencrypt/live/$domain/fullchain.pem" && sudo test -f "/etc/letsencrypt/live/$domain/privkey.pem"; then
            CERT_DIR="/etc/letsencrypt/live/$domain"
            echo "Found valid certificate in: $CERT_DIR"
            break
        fi
    fi
done

if [ -z "$CERT_DIR" ]; then
    echo "No valid certificate directory found!"
    echo "Available directories:"
    sudo ls -l /etc/letsencrypt/live/
    exit 1
fi

echo "Using certificate from: $CERT_DIR"

# Generate DH parameters
echo "Generating DH parameters (this may take a while)..."
sudo openssl dhparam -out /etc/haproxy/dhparams.pem 2048

# Create a temporary directory with correct permissions
sudo mkdir -p /tmp/ssl_combine
sudo chmod 700 /tmp/ssl_combine

# Combine cert, key, and DH params for HAProxy
sudo bash -c "cat $CERT_DIR/fullchain.pem $CERT_DIR/privkey.pem /etc/haproxy/dhparams.pem > /tmp/ssl_combine/combined.pem"
sudo mv /tmp/ssl_combine/combined.pem /etc/haproxy/certs/www.claranceliberi.tech.pem

# Verify the combined certificate
if ! sudo openssl x509 -in /etc/haproxy/certs/www.claranceliberi.tech.pem -text -noout > /dev/null 2>&1; then
    echo "Invalid certificate generated!"
    exit 1
fi

echo "Certificate verified successfully"

# Set proper permissions
sudo chmod 600 /etc/haproxy/certs/www.claranceliberi.tech.pem
sudo chown haproxy:haproxy /etc/haproxy/certs/www.claranceliberi.tech.pem

# Clean up
sudo rm -rf /tmp/ssl_combine
sudo rm -f /etc/nginx/sites-enabled/letsencrypt
sudo nginx -t && sudo systemctl stop nginx

# Start HAProxy
if ! sudo systemctl start haproxy; then
    echo "HAProxy failed to start. Checking logs..."
    sudo journalctl -xe --no-pager | tail -n 50
    exit 1
fi

echo "HAProxy status:"
sudo systemctl status haproxy --no-pager

# Verify HAProxy is running
if ! sudo systemctl is-active --quiet haproxy; then
    echo "HAProxy is not running"
    exit 1
fi

# Show ports in use
echo "Checking ports in use:"
sudo netstat -tlpn | grep -E ':80|:443'

echo "SSL certificate successfully generated and HAProxy is running"
exit 0
```

And update `update_haproxy.sh`:

```bash
#!/bin/bash

# Stop nginx if it's running
sudo systemctl stop nginx

# Before applying the new configuration
if [ ! -f "/etc/haproxy/certs/www.claranceliberi.tech.pem" ]; then
    echo "SSL certificate not found!"
    exit 1
fi

# Verify certificate is valid
if ! sudo openssl x509 -in /etc/haproxy/certs/www.claranceliberi.tech.pem -text -noout > /dev/null 2>&1; then
    echo "Invalid SSL certificate"
    exit 1
fi

# Add global SSL settings to HAProxy config
sudo tee /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # SSL settings
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

# ... rest of your HAProxy configuration ...
EOF

# Test and restart HAProxy
echo "Testing HAProxy configuration..."
if sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
    sudo systemctl restart haproxy
    echo "HAProxy restarted successfully"
else
    echo "HAProxy configuration test failed"
    exit 1
fi

# Verify HAProxy is running
if ! sudo systemctl is-active --quiet haproxy; then
    echo "HAProxy failed to start"
    sudo systemctl status haproxy --no-pager
    exit 1
fi

echo "HAProxy configuration updated and service running"
