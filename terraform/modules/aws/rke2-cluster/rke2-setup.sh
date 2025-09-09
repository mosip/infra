#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"

# Create a robust environment sourcing function
source_env_safely() {
    if [[ -f "$ENV_FILE_PATH" ]]; then
        source "$ENV_FILE_PATH" || {
            echo "Warning: Failed to source environment file"
            return 1
        }
    else
        echo "Warning: Environment file not found at $ENV_FILE_PATH"
        return 1
    fi
}

# Source environment and display relevant variables
source_env_safely
env | grep -E 'K8S|RKE2|WORK|CONTROL|RANCHER' || echo "No matching environment variables found"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# More relaxed error handling for better script resilience
set -o pipefail  # trace ERR through pipes only

# Function to handle errors gracefully
handle_error() {
    local exit_code=$?
    local line_number=$1
    echo "Error occurred on line $line_number (exit code: $exit_code)"
    echo "Continuing execution..."
    return 0
}

# Set up error trap
trap 'handle_error $LINENO' ERR

echo "=== RKE2 Setup Script Started at $(date) ==="
echo "Log file: $LOG_FILE"


echo "=== Installing RKE2 ==="
RKE2_EXISTENCE=$(which rke2 2>/dev/null || echo "not_found")
if [[ "$RKE2_EXISTENCE" == "not_found" ]]; then
    echo "RKE2 not found, installing..."
    curl -sfL https://get.rke2.io | sh - || {
        echo "Failed to install RKE2, but continuing..."
        sleep 10
    }
else
    echo "RKE2 already installed at: $RKE2_EXISTENCE"
fi

echo "=== Setting up workspace ==="
cd "$WORK_DIR" || {
    echo "Failed to change to work directory $WORK_DIR"
    exit 1
}

# Clone repository with retry logic
if [[ ! -d "k8s-infra" ]]; then
    echo "Cloning K8s infrastructure repository..."
    for i in {1..3}; do
        if git clone "$K8S_INFRA_REPO_URL" -b "$K8S_INFRA_BRANCH"; then
            echo "Successfully cloned repository"
            break
        else
            echo "Clone attempt $i failed, retrying in 10 seconds..."
            sleep 10
        fi
    done
else
    echo "K8s infrastructure repository already exists"
fi

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
# Re-source environment variables after potential updates
source_env_safely

# Wait for environment to be stable
sleep 30

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
sudo systemctl enable "$RKE2_SERVICE" || {
    echo "Failed to enable $RKE2_SERVICE"
    exit 1
}

sudo systemctl start "$RKE2_SERVICE" || {
    echo "Failed to start $RKE2_SERVICE"
    exit 1
}

echo "=== Waiting for RKE2 to initialize (5 minutes) ==="
sleep 300

echo "=== Setting up kubectl configuration ==="
if [[ -f "/etc/rancher/rke2/rke2.yaml" ]]; then
    sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl || echo "Warning: Failed to copy kubectl binary"
    mkdir -p /home/ubuntu/.kube/
    
    # Create kubeconfig with proper server IP
    cat "/etc/rancher/rke2/rke2.yaml" | \
        sed "s/127.0.0.1/${INTERNAL_IP}/g" | \
        sed "s/default/${CLUSTER_DOMAIN}/g" > \
        "/home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml"
    
    sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/* || echo "Warning: Failed to change ownership"
    sudo chmod -R 444 /home/ubuntu/.kube/*.yaml || echo "Warning: Failed to set permissions"
    sudo chmod +x /bin/kubectl || echo "Warning: Failed to make kubectl executable"
    
    echo "Kubectl configuration completed"
else
    echo "Warning: RKE2 config file not found at /etc/rancher/rke2/rke2.yaml"
fi

echo "=== Checking Rancher import configuration ==="
if [[ "${ENABLE_RANCHER_IMPORT:-false}" == "true" ]] && [[ -n "${RANCHER_IMPORT_URL:-}" ]]; then
    echo "Rancher import is enabled, executing import command..."
    echo "Import URL: $RANCHER_IMPORT_URL"
    
    # Wait a bit more for cluster to be fully ready
    sleep 60
    
    # Execute the rancher import command
    eval "$RANCHER_IMPORT_URL" || {
        echo "Warning: Rancher import failed, but continuing..."
    }
    
    echo "Rancher import completed"
else
    echo "Rancher import is disabled or URL not provided - skipping"
fi

echo "=== RKE2 Setup Script Completed Successfully at $(date) ==="
echo "Check logs at: $LOG_FILE"
