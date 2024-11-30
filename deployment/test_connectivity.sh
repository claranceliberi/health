#!/bin/bash

WEB_SERVER_1="54.85.8.164"
WEB_SERVER_2="54.90.175.71"
LOAD_BALANCER="107.21.151.190"

# Function to test port connectivity
test_port() {
    local from=$1
    local to=$2
    local port=$3

    nc -zv -w5 $to $port 2>&1
    if [ $? -eq 0 ]; then
        echo "Success: Connection from $from to $to:$port is open"
    else
        echo "Failed: Connection from $from to $to:$port is blocked"
    fi
}

# Test connectivity from load balancer to web servers
echo "Testing connectivity from Load Balancer to Web Servers..."
test_port $LOAD_BALANCER $WEB_SERVER_1 5000
test_port $LOAD_BALANCER $WEB_SERVER_2 5000

# Test if web servers are actually listening on port 5000
echo -e "\nVerifying if web servers are listening on port 5000..."
for server in $WEB_SERVER_1 $WEB_SERVER_2; do
    # Use the same SSH authentication mechanism as deploy_all.sh
    SSH_AUTH_SOCK=$SSH_AUTH_SOCK ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "ubuntu@${server}" "sudo netstat -tlpn | grep :5000" || echo "Port 5000 not listening on $server"
done
