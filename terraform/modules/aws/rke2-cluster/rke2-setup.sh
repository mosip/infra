#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
source $ENV_FILE_PATH
env | grep -E 'K8S|RKE2|WORK|CONTROL'

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

# Install RKE2
echo "Installing RKE2"
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=$INSTALL_RKE2_VERSION sh -

# Clone k8s-infra repository with timeout protection
echo "Cloning k8s-infra repository (shallow clone for faster download)..."
cd $WORK_DIR

# Configure git to trust the directory and handle ownership issues
sudo git config --global --add safe.directory $WORK_DIR/k8s-infra || true
sudo git config --global --add safe.directory '*' || true

# Remove existing directory if present to avoid conflicts
if [ -d "k8s-infra" ]; then
  echo "Removing existing k8s-infra directory..."
  sudo rm -rf k8s-infra
fi

echo "Starting git clone with 5-minute timeout..."
timeout 300 git clone --depth 1 --branch $K8S_INFRA_BRANCH $K8S_INFRA_REPO_URL k8s-infra && echo "Git clone completed successfully" || {
  echo "Git clone failed or timed out"
  exit 1
}

echo "Successfully cloned/updated k8s-infra repository"
sudo chown -R ubuntu:ubuntu k8s-infra/

# Create and configure RKE2 config directory
echo "Created and configured RKE2 config directory: $RKE2_CONFIG_DIR"
sudo mkdir -p $RKE2_CONFIG_DIR

# Verify repository structure
echo "Verifying k8s-infra directory structure:"
ls -la k8s-infra/

echo "Checking for k8-cluster directory:"
ls -la k8s-infra/k8-cluster/

# Change to RKE2 location
echo "Changed to RKE2 location: $RKE2_LOCATION"
cd $RKE2_LOCATION

echo "Contents of RKE2 location:"
ls -la

# Determine the role of the instance using pattern matching
echo "Determining node role based on NODE_NAME: $NODE_NAME"
echo "Available template files in current directory:"
ls -la *.template || echo "No template files found"
echo "Current working directory: $(pwd)"

echo "Sourcing environment file: $ENV_FILE_PATH"
source $ENV_FILE_PATH || echo "Warning: Could not source $ENV_FILE_PATH"
echo "Environment sourced successfully"
if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-1 ]]; then
  echo "✅ Detected PRIMARY CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  echo "📁 Copying template: rke2-server-control-plane-primary.conf.template"
  if [[ -f "rke2-server-control-plane-primary.conf.template" ]]; then
    echo "📋 Template file found, copying..."
    cp rke2-server-control-plane-primary.conf.template $RKE2_CONFIG_DIR/config.yaml
    echo "✅ Template copied successfully"
  else
    echo "❌ ERROR: Template file rke2-server-control-plane-primary.conf.template not found!"
    exit 1
  fi
  echo "💾 Writing service type to environment file..."
  echo "RKE2_SERVICE=rke2-server" | sudo tee -a $ENV_FILE_PATH
  export RKE2_SERVICE="rke2-server"
  echo "✅ Service configuration completed"

elif [[ "$NODE_NAME" == CONTROL-PLANE-NODE-* ]]; then
  echo "SUBSEQUENT CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  echo "Copying template: rke2-server-control-plane.subsequent.conf.template"
  if [[ -f "rke2-server-control-plane.subsequent.conf.template" ]]; then
    cp rke2-server-control-plane.subsequent.conf.template $RKE2_CONFIG_DIR/config.yaml
    echo "Template copied successfully"
  else
    echo "ERROR: Template file rke2-server-control-plane.subsequent.conf.template not found!"
    exit 1
  fi
  echo "RKE2_SERVICE=rke2-server" | sudo tee -a $ENV_FILE_PATH
  export RKE2_SERVICE="rke2-server"

elif [[ "$NODE_NAME" == ETCD-NODE-* ]]; then
  echo "ETCD NODE"
  echo "Copying template: rke2-etcd-agents.conf.template"
  if [[ -f "rke2-etcd-agents.conf.template" ]]; then
    cp rke2-etcd-agents.conf.template $RKE2_CONFIG_DIR/config.yaml
    echo "Template copied successfully"
  else
    echo "ERROR: Template file rke2-etcd-agents.conf.template not found!"
    exit 1
  fi
  RKE2_SERVICE=rke2-agent
  echo "RKE2_SERVICE=rke2-agent" | sudo tee -a $ENV_FILE_PATH
  export RKE2_SERVICE="rke2-agent"

else
  echo "WORKER AGENT NODE"
  echo "Copying template: rke2-agents.conf.template"
  if [[ -f "rke2-agents.conf.template" ]]; then
    cp rke2-agents.conf.template $RKE2_CONFIG_DIR/config.yaml
    echo "Template copied successfully"
  else
    echo "ERROR: Template file rke2-agents.conf.template not found!"
    exit 1
  fi
  RKE2_SERVICE=rke2-agent
  echo "RKE2_SERVICE=rke2-agent" | sudo tee -a $ENV_FILE_PATH
  export RKE2_SERVICE="rke2-agent"

fi

echo "Template configuration completed for node type: $NODE_NAME"
echo "Service type set to: $RKE2_SERVICE"

echo "Changing to RKE2 config directory: $RKE2_CONFIG_DIR"
cd $RKE2_CONFIG_DIR

echo "Configuring RKE2 config.yaml with cluster settings..."
sed -i "s/<configure-some-token-here>/$K8S_TOKEN/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-name>/${NODE_NAME}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-internal-ip>/${INTERNAL_IP}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<primary-server-ip>/${CONTROL_PLANE_NODE_1}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<cluster-name>/${CLUSTER_DOMAIN}/g" $RKE2_CONFIG_DIR/config.yaml

echo "Configuration complete. Final config file:"
cat $RKE2_CONFIG_DIR/config.yaml

echo "Environment variables:"
env | sort
cat $ENV_FILE_PATH

echo "Enabling and starting RKE2 service: $RKE2_SERVICE"
sudo systemctl enable $RKE2_SERVICE || echo "Failed to enable $RKE2_SERVICE"

echo "Checking current RKE2 service status..."
if sudo systemctl is-active --quiet $RKE2_SERVICE; then
    echo "✅ RKE2 service is already active and running"
    sudo systemctl status $RKE2_SERVICE --no-pager --lines=5 || true
    echo "Skipping startup wait - service is already operational"
elif sudo systemctl is-failed --quiet $RKE2_SERVICE; then
    echo "⚠️ RKE2 service was in failed state - attempting restart"
    sudo systemctl reset-failed $RKE2_SERVICE || true
    sudo systemctl start $RKE2_SERVICE &
    START_PID=$!
    echo "RKE2 service restart initiated (PID: $START_PID)"
    NEED_TO_WAIT=true
else
    echo "Starting RKE2 service..."
    sudo systemctl start $RKE2_SERVICE &
    START_PID=$!
    echo "RKE2 service start command initiated (PID: $START_PID)"
    NEED_TO_WAIT=true
fi

if [ "${NEED_TO_WAIT:-false}" = "true" ]; then
    echo "Waiting for RKE2 service to become active..."
    TIMEOUT=300  # 5 minutes timeout
    ELAPSED=0
    WAIT_INTERVAL=5  # 5 seconds between checks

    while [ $ELAPSED -lt $TIMEOUT ]; do
        if sudo systemctl is-active --quiet $RKE2_SERVICE; then
            echo "✅ RKE2 service is active and running after ${ELAPSED} seconds"
            sudo systemctl status $RKE2_SERVICE --no-pager --lines=5 || true
            break
        elif sudo systemctl is-failed --quiet $RKE2_SERVICE; then
            echo "❌ RKE2 service failed to start after ${ELAPSED} seconds"
            sudo systemctl status $RKE2_SERVICE --no-pager --lines=10 || true
            echo "Recent service logs:"
            sudo journalctl -u $RKE2_SERVICE --no-pager --lines=20 --since="10 minutes ago" || true
            exit 1
        else
            echo "⏳ RKE2 service is still starting... (${ELAPSED}s elapsed)"
            sleep $WAIT_INTERVAL
            ELAPSED=$((ELAPSED + WAIT_INTERVAL))
        fi
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️ Timeout waiting for RKE2 service to become active after ${TIMEOUT} seconds"
        sudo systemctl status $RKE2_SERVICE --no-pager || true
        echo "Service may still be starting - check manually with: sudo systemctl status $RKE2_SERVICE"
        exit 1
    fi
fi

echo "Final RKE2 service status check:"
sudo systemctl is-active $RKE2_SERVICE && echo "✅ RKE2 service is active" || echo "⚠️ RKE2 service status unknown"

# Wait for kubeconfig and kubectl to be available
KUBECONFIG_PATHS=(
  "/etc/rancher/rke2/rke2.yaml"
  "/var/lib/rancher/rke2/server/cred/admin.kubeconfig"
)

KUBECONFIG_FOUND=""
for path in "${KUBECONFIG_PATHS[@]}"; do
  if [[ -f "$path" ]]; then
    echo "Found kubeconfig at: $path"
    KUBECONFIG_FOUND="$path"
    break
  else
    echo "Kubeconfig not found at: $path"
  fi
done

if [[ -n "$KUBECONFIG_FOUND" ]] && [[ -f "/var/lib/rancher/rke2/bin/kubectl" ]]; then
  echo "Setting up kubectl and kubeconfig files..."
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl || echo "Failed to copy kubectl binary"
  mkdir -p /home/ubuntu/.kube/
  cat "$KUBECONFIG_FOUND" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" | tee /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/* || true
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml || true
  sudo chmod +x /bin/kubectl || true
  echo "✅ Kubectl and kubeconfig setup completed"
else
  echo "⚠️  Kubectl setup skipped - kubeconfig or kubectl binary not found yet"
  echo "This is normal for initial startup - RKE2 may still be initializing"
fi

echo "🎉 RKE2 setup script completed successfully!"
echo "RKE2 service status: $(sudo systemctl is-active $RKE2_SERVICE 2>/dev/null || echo 'unknown')"
echo "Setup completed at: $(date)"
exit 0