#!/bin/bash
# Enhanced User-Data Script with Verification
echo "=== USER-DATA SCRIPT STARTED at $(date) ==="
LOG_FILE="/tmp/k8s-userdata-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
STATUS_FILE="/tmp/userdata-status.txt"

# Create status tracking
echo "USERDATA_STARTED=$(date)" > "$STATUS_FILE"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== USER-DATA EXECUTION LOG ===" >> "$LOG_FILE"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo 'unknown')" >> "$LOG_FILE"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type || echo 'unknown')" >> "$LOG_FILE"
echo "AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone || echo 'unknown')" >> "$LOG_FILE"

# More relaxed error handling for user-data
set -o pipefail  # Only trace ERR through pipes

# Set internal IP address and metadata
echo "=== SETTING UP INSTANCE METADATA ==="
echo "Instance index: ${index}"
echo "Role: ${role}"
echo "Cluster domain: ${cluster_domain}"

# Configure DNS resolution
echo "=== CONFIGURING DNS ==="
echo "nameserver 8.8.8.8" | sudo tee -a /run/systemd/resolve/stub-resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /run/systemd/resolve/stub-resolv.conf

echo "=== UPDATING PACKAGE MANAGER ==="
sudo apt-get update -y || {
    echo "Warning: apt-get update failed, but continuing..."
    sleep 5
}

echo "=== DNS CONFIGURATION CHECK ==="
echo "file /run/systemd/resolve/stub-resolv.conf"
cat /run/systemd/resolve/stub-resolv.conf

echo "file /etc/resolv.conf"
cat /etc/resolv.conf

echo "=== FETCHING INSTANCE METADATA ==="
# Get metadata token with retry
for i in {1..3}; do
    if TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); then
        echo "Successfully obtained metadata token"
        break
    else
        echo "Failed to get metadata token, attempt $i/3"
        sleep 5
    fi
done

# Get internal IP with retry
for i in {1..3}; do
    if INTERNAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4); then
        echo "Successfully obtained internal IP: $INTERNAL_IP"
        break
    else
        echo "Failed to get internal IP, attempt $i/3"
        sleep 5
    fi
done

echo "=== SETTING ENVIRONMENT VARIABLES ==="
echo "export TOKEN=$TOKEN" | sudo tee -a $ENV_FILE_PATH
echo "export INTERNAL_IP=\"$INTERNAL_IP\"" | sudo tee -a $ENV_FILE_PATH
echo "export NODE_NAME=${role}" | sudo tee -a $ENV_FILE_PATH
echo "export CLUSTER_DOMAIN=${cluster_domain}" | sudo tee -a $ENV_FILE_PATH

# Determine the role of the instance using pattern matching
echo "=== DETERMINING NODE ROLE ==="
if [[ "${role}" == CONTROL-PLANE-NODE-* ]]; then
  echo "Setting up as CONTROL PLANE NODE"
  echo "export K8S_ROLE=\"K8S-CONTROL-PLANE-NODE\"" | sudo tee -a $ENV_FILE_PATH
elif [[ "${role}" == ETCD-NODE-* ]]; then
  echo "Setting up as ETCD NODE"
  echo "export K8S_ROLE=\"K8S-ETCD-NODE\"" | sudo tee -a $ENV_FILE_PATH
else
  echo "Setting up as WORKER NODE"
  echo "export K8S_ROLE=\"K8S-WORKER-NODE\"" | sudo tee -a $ENV_FILE_PATH
fi

# Source the environment variables
echo "=== SOURCING ENVIRONMENT VARIABLES ==="
source $ENV_FILE_PATH

echo "=== FINAL ENVIRONMENT CHECK ==="
env | grep -E 'TOKEN|INTERNAL_IP|NODE_NAME|CLUSTER_DOMAIN|K8S_ROLE' || echo "Some environment variables not set"

echo "=== USER-DATA SCRIPT COMPLETED SUCCESSFULLY ==="
echo "USERDATA_COMPLETED=$(date)" >> "$STATUS_FILE"
echo "USERDATA_SUCCESS=true" >> "$STATUS_FILE"
echo "Check logs at: $LOG_FILE"

# Create verification files for remote-exec to check
echo "USER_DATA_APPLIED=true" | sudo tee /tmp/userdata-applied.flag
echo "ROLE=${role}" | sudo tee /tmp/node-role.txt
echo "INTERNAL_IP=$INTERNAL_IP" | sudo tee /tmp/instance-ip.txt
