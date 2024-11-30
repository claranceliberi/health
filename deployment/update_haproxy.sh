#!/bin/bash

# Stop any services that might be using port 80/443
sudo systemctl stop nginx || true

# Before applying the new configuration
if [ ! -f "/etc/haproxy/certs/www.claranceliberi.tech.pem" ]; then
    echo "SSL certificate not found!"
    exit 1
fi

# Create new HAProxy configuration
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
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend liberi-frontend-http
    bind *:80
    mode http
    option forwardfor
    option http-server-close
    http-request redirect scheme https code 301 unless { ssl_fc }
    default_backend liberi-backend

frontend liberi-frontend-https
    bind *:443 ssl crt /etc/haproxy/certs/www.claranceliberi.tech.pem
    mode http
    option forwardfor
    option http-server-close

    # ACL for health subdomain
    acl is_health hdr(host) -i health.claranceliberi.tech

    # Route based on domain
    use_backend health-backend if is_health
    default_backend liberi-backend

backend liberi-backend
    mode http
    balance roundrobin
    server web-01 54.85.8.164:80 check
    server web-02 54.90.175.71:80 check

backend health-backend
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200
    default-server inter 3s fall 3 rise 2
    server web-01 54.85.8.164:5000 check
    server web-02 54.90.175.71:5000 check
EOF

# Test configuration
if ! sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
    echo "HAProxy configuration test failed"
    exit 1
fi

# Restart HAProxy
sudo systemctl restart haproxy

# Verify HAProxy is running
if ! sudo systemctl is-active --quiet haproxy; then
    echo "HAProxy failed to start"
    sudo systemctl status haproxy --no-pager
    sudo journalctl -xe --no-pager | tail -n 50
    exit 1
fi

echo "HAProxy configuration updated and service running"

# Show ports in use
echo "Checking ports in use:"
sudo netstat -tlpn | grep -E ':80|:443'
