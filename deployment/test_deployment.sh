#!/bin/bash
# test_deployment.sh

# Test web servers directly
for server in "54.85.8.164" "54.90.175.71"; do
    echo "Testing server $server..."
    curl -v http://${server}:5000
done

# Test through HAProxy
echo "Testing through HAProxy..."
curl -v --header "Host: health.claranceliberi.tech" http://107.21.151.190

# Test HTTPS
echo "Testing HTTPS..."
curl -v -k https://health.claranceliberi.tech
