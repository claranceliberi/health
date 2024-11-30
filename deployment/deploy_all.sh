# Define server details
WEB_SERVER_1="ubuntu@54.85.8.164"
WEB_SERVER_2="ubuntu@54.90.175.71"
LOAD_BALANCER="ubuntu@107.21.151.190"

# Create a temporary script to echo the passphrase
create_askpass_script() {
    cat > /tmp/askpass.sh <<EOF
#!/bin/bash
echo "betty"
EOF
    chmod +x /tmp/askpass.sh
}

# Function to handle SSH key
setup_ssh() {
    # Start ssh-agent
    eval $(ssh-agent -s)

    # Create and use askpass script
    create_askpass_script
    export SSH_ASKPASS="/tmp/askpass.sh"
    export SSH_ASKPASS_REQUIRE=force

    # Add the key
    ssh-add ~/.ssh/school < /dev/null

    # Create known_hosts if it doesn't exist
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts

    # Add host keys to known_hosts
    ssh-keyscan -H 54.85.8.164 >> ~/.ssh/known_hosts 2>/dev/null
    ssh-keyscan -H 54.90.175.71 >> ~/.ssh/known_hosts 2>/dev/null
    ssh-keyscan -H 107.21.151.190 >> ~/.ssh/known_hosts 2>/dev/null
}

# Function to copy and execute script
deploy_script() {
    local server=$1
    local script=$2

    echo "Deploying $script to $server..."
    scp "${script}" "${server}:/tmp/"
    ssh "${server}" "bash /tmp/$(basename ${script})"
}

# Setup SSH
setup_ssh

# First, update SSL certificate
echo "Updating SSL certificate..."
deploy_script "$LOAD_BALANCER" "update_ssl.sh"

# After SSL certificate update
if ! ssh "$LOAD_BALANCER" "test -f /etc/haproxy/certs/www.claranceliberi.tech.pem"; then
    echo "SSL certificate not generated. Stopping deployment."
    exit 1
fi

# After SSL certificate update in deploy_all.sh
echo "Verifying SSL and HAProxy setup..."
if ! ssh "$LOAD_BALANCER" "curl -k https://localhost:443 >/dev/null 2>&1"; then
    echo "HTTPS connection test failed"
    exit 1
fi

echo "SSL and HAProxy verification successful"


# Deploy to web servers
echo "Deploying to Web Server 1..."
deploy_script "$WEB_SERVER_1" "deploy_health.sh"

echo "Deploying to Web Server 2..."
deploy_script "$WEB_SERVER_2" "deploy_health.sh"

# After web server deployments
for server in "$WEB_SERVER_1" "$WEB_SERVER_2"; do
    if ! ssh "$server" "test -d /var/www/health/dist"; then
        echo "Application not deployed correctly on $server. Stopping deployment."
        exit 1
    fi
done

# Update load balancer configuration
echo "Updating Load Balancer configuration..."
deploy_script "$LOAD_BALANCER" "update_haproxy.sh"

# Test connectivity
echo "Testing connectivity..."
deploy_script "$LOAD_BALANCER" "test_connectivity.sh"

echo "Deployment completed!"

# Final verification
echo "Verifying SSL setup..."
if ! ssh "$LOAD_BALANCER" "test -f /etc/haproxy/certs/www.claranceliberi.tech.pem && systemctl is-active --quiet haproxy"; then
    echo "SSL certificate not generated or HAProxy not running. Stopping deployment."
    exit 1
fi

# Cleanup
rm -f /tmp/askpass.sh
ssh-agent -k
