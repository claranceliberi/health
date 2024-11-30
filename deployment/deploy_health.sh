#!/bin/bash

# Update system and install basic dependencies
sudo apt update
sudo apt install -y nginx git curl net-tools build-essential

# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Install Node.js 20 and set it as default
nvm install 20
nvm use 20
nvm alias default 20

# Verify Node.js version
node --version
npm --version

# Clean up existing installation if present
cd /var/www
sudo rm -rf health
sudo git clone https://github.com/claranceliberi/health
sudo chown -R ubuntu:ubuntu /var/www/health

# Install dependencies and build
cd /var/www/health
npm cache clean --force
npm install
NODE_ENV=production npm run build

# Ensure dist directory exists
if [ ! -d "dist" ]; then
    echo "Build failed - dist directory not created"
    exit 1
fi

# Create nginx configuration
sudo tee /etc/nginx/sites-available/health.claranceliberi.tech <<EOF
server {
    listen 5000;
    server_name health.claranceliberi.tech;

    root /var/www/health/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/health.claranceliberi.tech /etc/nginx/sites-enabled/

# Remove default nginx site if it exists
sudo rm -f /etc/nginx/sites-enabled/default

# Set proper permissions
sudo chown -R www-data:www-data /var/www/health/dist

# Configure firewall
sudo ufw allow 5000/tcp
sudo ufw --force enable
sudo ufw status

# Also add explicit nginx port listening
sudo sed -i 's/listen 80 default_server;/listen 5000 default_server;/' /etc/nginx/sites-available/default

# Verify UFW status and rules
echo "Verifying firewall rules..."
sudo ufw status | grep 5000 || echo "Warning: Port 5000 might not be properly configured in UFW"

# Verify that nginx is actually listening on port 5000
netstat -tlpn | grep :5000 || echo "Warning: Nothing is listening on port 5000"

# Verify nginx configuration and restart
sudo nginx -t
sudo systemctl restart nginx

# Add service status check
if ! sudo systemctl is-active --quiet nginx; then
    echo "Nginx failed to start"
    sudo systemctl status nginx
    exit 1
fi

# Verify port 5000 is actually listening
if ! netstat -tlpn | grep :5000; then
    echo "Port 5000 is not listening"
    exit 1
fi
