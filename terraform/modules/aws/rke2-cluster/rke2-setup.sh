#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"

# Source environment variables (both from user-data and Terraform)
if [ -f "$ENV_FILE_PATH" ]; then
    set -a  # automatically export all variables
    . $ENV_FILE_PATH
    set +a  # stop automatically exporting
fi
env | grep -E 'K8S|RKE2|WORK|CONTROL|NODE_NAME|INTERNAL_IP|CLUSTER_DOMAIN'

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
#set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

# Install RKE2 only if not installed
if command -v rke2 >/dev/null 2>&1; then
    echo "✅ RKE2 already installed, skipping installation"
else
    echo "🚀 Installing RKE2 version: $INSTALL_RKE2_VERSION"
    curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=$INSTALL_RKE2_VERSION sh -
    echo "✅ RKE2 installation completed"

    echo "⏳ Waiting for RKE2 installation to settle..."
    sleep 10   # wait 10 seconds
fi

# Clone k8s-infra repository only if it doesn't exist
echo "Checking for k8s-infra repository..."
cd $WORK_DIR

# Configure git to trust the directory and handle ownership issues
# Run git config as ubuntu user, not sudo
git config --global --add safe.directory $WORK_DIR/k8s-infra || true
git config --global --add safe.directory '*' || true
echo "$(date): Git configuration completed"

# Only clone if directory doesn't exist
if [ ! -d "k8s-infra" ]; then
  echo "k8s-infra directory not found, cloning repository..."
  echo "Repository: $K8S_INFRA_REPO_URL"
  echo "Branch: $K8S_INFRA_BRANCH"
  
  # Simple clone with timeout
  timeout 600 git clone --depth 1 --branch $K8S_INFRA_BRANCH $K8S_INFRA_REPO_URL k8s-infra || {
    echo "❌ Git clone failed"
    echo "This might be due to network connectivity issues"
    exit 1
  }
  
  echo "✅ Git clone completed successfully"
  sudo chown -R ubuntu:ubuntu k8s-infra/
else
  echo "✅ k8s-infra directory already exists, skipping clone"
fi

# Ensure proper ownership
echo "$(date): Setting proper ownership for k8s-infra directory..."
sudo chown -R ubuntu:ubuntu k8s-infra/
echo "$(date): Ownership set successfully"

echo "$(date): Starting RKE2 configuration"

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
    echo "🔄 Giving RKE2 initial startup time (30 seconds)..."
    sleep 30  # Initial grace period for RKE2 to start properly
    
    TIMEOUT=300  # 5 minutes timeout - reduced from 10 minutes
    ELAPSED=30   # Start elapsed at 30 since we already waited
    WAIT_INTERVAL=15  # 15 seconds between checks (less frequent)
    STARTUP_DETECTED=false

    while [ $ELAPSED -lt $TIMEOUT ]; do
        SERVICE_STATE=$(sudo systemctl is-active $RKE2_SERVICE 2>/dev/null || echo "unknown")
        echo "⏳ RKE2 service state: $SERVICE_STATE (${ELAPSED}s elapsed)"
        
        case "$SERVICE_STATE" in
            "active")
                echo "✅ RKE2 service is active and running after ${ELAPSED} seconds"
                sudo systemctl status $RKE2_SERVICE --no-pager --lines=5 || true
                break
                ;;
            "activating")
                echo "🔄 RKE2 service is activating..."
                STARTUP_DETECTED=true
                # After 60 seconds of activating, check if it's functionally ready
                if [ $ELAPSED -ge 60 ]; then
                    echo "🔍 Checking if RKE2 is functionally ready despite activating state..."
                    if pgrep -f "rke2 server" >/dev/null 2>&1; then
                        echo "✅ RKE2 server process is running - considering service ready"
                        break
                    fi
                fi
                ;;
            "failed")
                echo "❌ RKE2 service failed to start after ${ELAPSED} seconds"
                sudo systemctl status $RKE2_SERVICE --no-pager --lines=10 || true
                echo "Recent service logs:"
                sudo journalctl -u $RKE2_SERVICE --no-pager --lines=20 --since="10 minutes ago" || true
                exit 1
                ;;
            *)
                if [ "$STARTUP_DETECTED" = "true" ]; then
                    echo "⏳ RKE2 service continuing startup process..."
                else
                    echo "⏳ RKE2 service is still starting... (state: $SERVICE_STATE)"
                fi
                ;;
        esac
        
        sleep $WAIT_INTERVAL
        ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    done

    # Final check - if we've detected startup and we're still not active, consider it successful enough
    if [ $ELAPSED -ge $TIMEOUT ]; then
        FINAL_STATE=$(sudo systemctl is-active $RKE2_SERVICE 2>/dev/null || echo "unknown")
        if [ "$FINAL_STATE" = "active" ] || [ "$FINAL_STATE" = "activating" ]; then
            echo "✅ RKE2 service is operational (state: $FINAL_STATE) after timeout period"
        else
            echo "⚠️ Timeout waiting for RKE2 service after ${TIMEOUT} seconds"
            sudo systemctl status $RKE2_SERVICE --no-pager || true
            echo "Final service state: $FINAL_STATE"
            echo "Checking if RKE2 processes are running..."
            if pgrep -f "rke2 server" >/dev/null 2>&1; then
                echo "✅ RKE2 server process is running - continuing deployment"
            else
                echo "❌ RKE2 server process not found - deployment failed"
                exit 1
            fi
        fi
    fi
fi

echo "Final RKE2 service status check:"
SERVICE_STATUS=$(sudo systemctl is-active $RKE2_SERVICE 2>/dev/null || echo "unknown")
echo "RKE2 service status: $SERVICE_STATUS"

# Check if RKE2 is functionally ready 
echo "Checking RKE2 functional readiness..."

# Only control plane nodes generate kubeconfig files
if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-* ]]; then
    echo "Control plane node detected - waiting for kubeconfig generation..."
    KUBECONFIG_WAIT_TIMEOUT=300  # 3 minutes for kubeconfig to appear
    KUBECONFIG_ELAPSED=0

    while [ $KUBECONFIG_ELAPSED -lt $KUBECONFIG_WAIT_TIMEOUT ]; do
        if [[ -f "/etc/rancher/rke2/rke2.yaml" ]] || [[ -f "/var/lib/rancher/rke2/server/cred/admin.kubeconfig" ]]; then
            echo "✅ RKE2 kubeconfig found - cluster is functionally ready"
            break
        else
            echo "⏳ Waiting for RKE2 kubeconfig... (${KUBECONFIG_ELAPSED}s elapsed)"
            sleep 10
            KUBECONFIG_ELAPSED=$((KUBECONFIG_ELAPSED + 10))
        fi
    done

    if [ $KUBECONFIG_ELAPSED -ge $KUBECONFIG_WAIT_TIMEOUT ]; then
        echo "⚠️ Kubeconfig not found after ${KUBECONFIG_WAIT_TIMEOUT} seconds"
        echo "RKE2 may still be initializing. Current status:"
        sudo systemctl status $RKE2_SERVICE --no-pager --lines=5 || true
        
        # Check if RKE2 process is running as final validation
        if pgrep -f "rke2 server" >/dev/null 2>&1; then
            echo "✅ RKE2 server process detected - proceeding with deployment"
        else
            echo "❌ RKE2 server process not found"
            exit 1
        fi
    fi
else
    echo "Worker/ETCD node detected - skipping kubeconfig wait (agents don't generate kubeconfig)"
    echo "✅ Agent node is functionally ready when service is active"
fi

# Setup kubectl only for control plane nodes
if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-* ]]; then
    echo "Setting up kubectl for control plane node..."
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
else
    echo "Worker/ETCD node - skipping kubectl setup (only control plane nodes need kubectl access)"
fi

echo "🎉 RKE2 setup script completed successfully!"
echo "RKE2 service status: $(sudo systemctl is-active $RKE2_SERVICE 2>/dev/null || echo 'unknown')"
echo "Setup completed at: $(date)"
exit 0
