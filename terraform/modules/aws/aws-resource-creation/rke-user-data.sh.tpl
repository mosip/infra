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
echo "export NODE_INDEX=${index}" | sudo tee -a $ENV_FILE_PATH

# Explicit primary control plane selection logic
if [[ "${role}" == CONTROL-PLANE-NODE-* ]]; then
  echo "export K8S_ROLE=\"K8S-CONTROL-PLANE-NODE\"" | sudo tee -a $ENV_FILE_PATH
  
  # Determine if this is the primary control plane
  # Option 1: Always make NODE-1 primary (current default)
  if [[ "${role}" == "CONTROL-PLANE-NODE-1" ]]; then
    echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
    echo "This node is designated as PRIMARY CONTROL PLANE"
  else
    echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
    echo "This node is designated as SUBSEQUENT CONTROL PLANE"
  fi
  
  # Option 2: Use specific IP range for primary (uncomment to use)
  # if [[ "$INTERNAL_IP" == "10.0.1.10" ]]; then
  #   echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
  #   echo "This node is designated as PRIMARY CONTROL PLANE (by IP)"
  # else
  #   echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
  #   echo "This node is designated as SUBSEQUENT CONTROL PLANE (by IP)"
  # fi
  
  # Option 3: Use index to determine primary (uncomment to use)
  # if [[ "${index}" == "0" ]]; then
  #   echo "export IS_PRIMARY_CONTROL_PLANE=true" | sudo tee -a $ENV_FILE_PATH
  #   echo "This node is designated as PRIMARY CONTROL PLANE (by index)"
  # else
  #   echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
  #   echo "This node is designated as SUBSEQUENT CONTROL PLANE (by index)"
  # fi
  
elif [[ "${role}" == ETCD-NODE-* ]]; then
  echo "export K8S_ROLE=\"K8S-ETCD-NODE\"" | sudo tee -a $ENV_FILE_PATH
  echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
else
  echo "export K8S_ROLE=\"K8S-WORKER-NODE\"" | sudo tee -a $ENV_FILE_PATH
  echo "export IS_PRIMARY_CONTROL_PLANE=false" | sudo tee -a $ENV_FILE_PATH
fi

# Source the environment variables
source $ENV_FILE_PATH
#!/bin/bash
# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/k8s-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialized variable
set -o errtrace  # Trace ERR through 'time command' and other functions
set -o pipefail  # Trace ERR through pipes

# Set internal IP address
echo "Instance index: ${index}"

echo "nameserver 8.8.8.8 8.8.4.4" | sudo tee -a /run/systemd/resolve/stub-resolv.conf

echo "file /run/systemd/resolve/stub-resolv.conf"
cat /run/systemd/resolve/stub-resolv.conf

echo "file /etc/resolv.conf"
cat /etc/resolv.conf

export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
echo "export TOKEN=$TOKEN" | sudo tee -a $ENV_FILE_PATH
echo "export INTERNAL_IP=\"$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)\"" | sudo tee -a $ENV_FILE_PATH
echo "export NODE_NAME=${role}" | sudo tee -a $ENV_FILE_PATH
echo "export CLUSTER_DOMAIN=${cluster_domain}" | sudo tee -a $ENV_FILE_PATH

# Determine the role of the instance using pattern matching
if [[ "${role}" == CONTROL-PLANE-NODE-* ]]; then
  echo "export K8S_ROLE=\"K8S-CONTROL-PLANE-NODE\"" | sudo tee -a $ENV_FILE_PATH
elif [[ "${role}" == ETCD-NODE-* ]]; then
  echo "export K8S_ROLE=\"K8S-ETCD-NODE\"" | sudo tee -a $ENV_FILE_PATH
else
  echo "export K8S_ROLE=\"K8S-WORKER-NODE\"" | sudo tee -a $ENV_FILE_PATH
fi

# Source the environment variables
source $ENV_FILE_PATH