#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Set commands for error handling - MATCHING WORKING CONFIG
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

# Source environment and display relevant variables - MATCHING WORKING CONFIG
source $ENV_FILE_PATH
env | grep -E 'K8S|RKE2|WORK|CONTROL'

echo "=== RKE2 Setup Script Started at $(date) ==="
echo "Log file: $LOG_FILE"


echo "=== Installing RKE2 ==="
# MATCHING WORKING CONFIG - Simple and reliable
RKE2_EXISTENCE=$( which rke2 || true)
if [[ -z $RKE2_EXISTENCE ]]; then
    echo "RKE2 not found, installing..."
    curl -sfL https://get.rke2.io | sh -
else
    echo "RKE2 already installed at: $RKE2_EXISTENCE"
fi

echo "=== Setting up workspace ==="
cd "$WORK_DIR" || {
    echo "Failed to change to work directory $WORK_DIR"
    exit 1
}

# MATCHING WORKING CONFIG - Simple git clone
git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH || true

echo "=== Setting up RKE2 configuration directory ==="
mkdir -p "$RKE2_CONFIG_DIR" || {
    echo "Failed to create RKE2 config directory"
    exit 1
}
chown -R 1000:1000 "$RKE2_CONFIG_DIR" || echo "Warning: Failed to change ownership of RKE2 config directory"

cd "$RKE2_LOCATION" || {
    echo "Failed to change to RKE2 location $RKE2_LOCATION"
    exit 1
}

echo "=== Checking for existing RKE2 configuration ==="
if [[ -f "$RKE2_CONFIG_DIR/config.yaml" ]]; then
    echo "RKE CONFIG file already exists at \"$RKE2_CONFIG_DIR/config.yaml\""
    echo "Skipping configuration setup"
    exit 0
fi

echo "=== Determining node role and configuring RKE2 ==="
# MATCHING WORKING CONFIG - Simple approach
sleep 30
source $ENV_FILE_PATH

# Determine the role of the instance using pattern matching
if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-1 ]]; then
    echo "Configuring as PRIMARY CONTROL PLANE NODE"
    RKE2_SERVICE="rke2-server"
    cp rke2-server-control-plane-primary.conf.template "$RKE2_CONFIG_DIR/config.yaml" || {
        echo "Failed to copy primary control plane config template"
        exit 1
    }
    echo "RKE2_SERVICE=rke2-server" | sudo tee -a "$ENV_FILE_PATH" >/dev/null

elif [[ "$NODE_NAME" == CONTROL-PLANE-NODE-* ]]; then
    echo "Configuring as SUBSEQUENT CONTROL PLANE NODE"
    RKE2_SERVICE="rke2-server"
    cp rke2-server-control-plane.subsequent.conf.template "$RKE2_CONFIG_DIR/config.yaml" || {
        echo "Failed to copy subsequent control plane config template"
        exit 1
    }
    echo "RKE2_SERVICE=rke2-server" | sudo tee -a "$ENV_FILE_PATH" >/dev/null

elif [[ "$NODE_NAME" == ETCD-NODE-* ]]; then
    echo "Configuring as ETCD NODE"
    cp rke2-etcd-agents.conf.template "$RKE2_CONFIG_DIR/config.yaml" || {
        echo "Failed to copy ETCD config template"
        exit 1
    }
    RKE2_SERVICE="rke2-agent"
    echo "RKE2_SERVICE=rke2-agent" | sudo tee -a "$ENV_FILE_PATH" >/dev/null

else
    echo "Configuring as WORKER NODE"
    cp rke2-agents.conf.template "$RKE2_CONFIG_DIR/config.yaml" || {
        echo "Failed to copy worker node config template"
        exit 1
    }
    RKE2_SERVICE="rke2-agent"
    echo "RKE2_SERVICE=rke2-agent" | sudo tee -a "$ENV_FILE_PATH" >/dev/null
fi

echo "=== Customizing RKE2 configuration ==="
cd "$RKE2_CONFIG_DIR" || exit 1

# Ensure we have all required variables with fallbacks
if [[ -z "${INTERNAL_IP:-}" ]]; then
    echo "Warning: INTERNAL_IP not set, getting from metadata..."
    INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "127.0.0.1")
    echo "Using INTERNAL_IP: $INTERNAL_IP"
fi

if [[ -z "${CLUSTER_DOMAIN:-}" ]]; then
    echo "Warning: CLUSTER_DOMAIN not set, using default..."
    if [[ -n "${K8S_CLUSTER_PRIVATE_IPS_STR:-}" ]]; then
        CLUSTER_DOMAIN=$(echo "$K8S_CLUSTER_PRIVATE_IPS_STR" | cut -d'-' -f1 | cut -d'=' -f1)
        echo "Extracted CLUSTER_DOMAIN from cluster IPs: $CLUSTER_DOMAIN"
    else
        CLUSTER_DOMAIN="default"
        echo "Using default CLUSTER_DOMAIN: $CLUSTER_DOMAIN"
    fi
fi

echo "Configuration values:"
echo "  NODE_NAME: $NODE_NAME"
echo "  INTERNAL_IP: $INTERNAL_IP"
echo "  CLUSTER_DOMAIN: $CLUSTER_DOMAIN"
echo "  K8S_TOKEN: ${K8S_TOKEN:0:8}..."
echo "  CONTROL_PLANE_NODE_1: $CONTROL_PLANE_NODE_1"

# Apply configuration substitutions
sed -i "s/<configure-some-token-here>/$K8S_TOKEN/g" "$RKE2_CONFIG_DIR/config.yaml"
sed -i "s/<node-name>/${NODE_NAME}/g" "$RKE2_CONFIG_DIR/config.yaml"
sed -i "s/<node-internal-ip>/${INTERNAL_IP}/g" "$RKE2_CONFIG_DIR/config.yaml"
sed -i "s/<primary-server-ip>/${CONTROL_PLANE_NODE_1}/g" "$RKE2_CONFIG_DIR/config.yaml"
sed -i "s/<cluster-name>/${CLUSTER_DOMAIN}/g" "$RKE2_CONFIG_DIR/config.yaml"

echo "=== Final environment check ==="
source_env_safely
cat "$ENV_FILE_PATH" | grep -E 'K8S|RKE2|CLUSTER|NODE|RANCHER' || echo "No matching environment variables"

echo "=== Starting RKE2 service ==="
sudo systemctl enable "$RKE2_SERVICE"
sudo systemctl start "$RKE2_SERVICE"

echo "=== Waiting for service to stabilize ==="
sleep 120

echo "=== Setting up kubectl configuration ==="
sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl
mkdir -p /home/ubuntu/.kube/

cat /etc/rancher/rke2/rke2.yaml | \
    sed "s/127.0.0.1/${INTERNAL_IP}/g" | \
    sed "s/default/${CLUSTER_DOMAIN}/g" > \
    "/home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml"

sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/*
sudo chmod -R 444 /home/ubuntu/.kube/*.yaml
sudo chmod +x /bin/kubectl

echo "=== Setup completed successfully ==="
