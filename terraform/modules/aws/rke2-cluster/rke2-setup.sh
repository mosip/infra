#!/bin/bash

# Ensure non-interactive mode
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Disable interactive prompts for git and ssh
export GIT_TERMINAL_PROMPT=0
export SSH_BATCH_MODE=yes

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
#set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes


echo "Installing RKE2"
RKE2_EXISTENCE=$( which rke2 || true)
if [[ -z $RKE2_EXISTENCE ]]; then
  # Install RKE2 non-interactively
  export DEBIAN_FRONTEND=noninteractive
  curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="$INSTALL_RKE2_VERSION" sh -
fi

cd $WORK_DIR

# Clone repository with timeout and non-interactive settings - sparse checkout for RKE2 only
echo "Cloning k8s-infra repository (RKE2 directory only)..."
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

if [ ! -d "k8s-infra" ]; then
  echo "Performing sparse checkout for RKE2 directory only..."
  timeout 300 bash -c '
    git clone --no-checkout --depth 1 --single-branch -b '"$K8S_INFRA_BRANCH"' '"$K8S_INFRA_REPO_URL"' &&
    cd k8s-infra &&
    git sparse-checkout init --cone &&
    git sparse-checkout set k8-cluster/on-prem/rke2 &&
    git checkout
  ' || {
    echo "Sparse checkout failed, trying full clone as fallback..."
    rm -rf k8s-infra 2>/dev/null || true
    timeout 300 git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH --depth 1 --single-branch || {
      echo "Git clone failed or timed out, but continuing..."
    }
  }
else
  echo "k8s-infra directory already exists, skipping clone"
fi

# Verify the RKE2 directory exists
if [ ! -d "k8s-infra/k8-cluster/on-prem/rke2" ]; then
  echo "ERROR: RKE2 configuration directory not found after clone"
  echo "Available directories in k8s-infra:"
  find k8s-infra -type d 2>/dev/null | head -20 || echo "No directories found"
  exit 1
else
  echo "RKE2 configuration directory found successfully"
  ls -la k8s-infra/k8-cluster/on-prem/rke2/
fi

mkdir -p $RKE2_CONFIG_DIR
chown -R 1000:1000 $RKE2_CONFIG_DIR

cd $RKE2_LOCATION || {
  echo "ERROR: RKE2_LOCATION directory not found: $RKE2_LOCATION"
  echo "Available directories:"
  find /home/ubuntu -name "*rke2*" -type d 2>/dev/null || echo "No RKE2 directories found"
  echo "Contents of k8s-infra directory:"
  find /home/ubuntu/k8s-infra -name "*rke2*" -type d 2>/dev/null || echo "RKE2 directory not found in k8s-infra"
  exit 1
}

if [[ -f "$RKE2_CONFIG_DIR/config.yaml" ]]; then
  echo "RKE CONFIG file exists \"$RKE2_CONFIG_DIR/config.yaml\""
  exit 0
fi

# Determine the role of the instance using pattern matching
sleep 30
source $ENV_FILE_PATH
if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-1 ]]; then
  echo "PRIMARY CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  cp rke2-server-control-plane-primary.conf.template $RKE2_CONFIG_DIR/config.yaml
  export RKE2_SERVICE="rke2-server" | sudo tee -a $ENV_FILE_PATH

elif [[ "$NODE_NAME" == CONTROL-PLANE-NODE-* ]]; then
  echo "SUBSEQUENT CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  cp rke2-server-control-plane.subsequent.conf.template $RKE2_CONFIG_DIR/config.yaml
  export RKE2_SERVICE="rke2-server" | sudo tee -a $ENV_FILE_PATH

elif [[ "$NODE_NAME" == ETCD-NODE-* ]]; then
  echo "ETCD NODE"
  cp rke2-etcd-agents.conf.template $RKE2_CONFIG_DIR/config.yaml
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

else
  echo "WORKER NODE"
  cp rke2-agents.conf.template $RKE2_CONFIG_DIR/config.yaml
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

fi

cd $RKE2_CONFIG_DIR

sed -i "s/<configure-some-token-here>/$K8S_TOKEN/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-name>/${NODE_NAME}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-internal-ip>/${INTERNAL_IP}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<primary-server-ip>/${CONTROL_PLANE_NODE_1}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<cluster-name>/${CLUSTER_DOMAIN}/g" $RKE2_CONFIG_DIR/config.yaml


source $ENV_FILE_PATH
cat $ENV_FILE_PATH

echo "Enabling and starting RKE2 service: $RKE2_SERVICE"
sudo systemctl enable $RKE2_SERVICE || {
  echo "Failed to enable $RKE2_SERVICE, but continuing..."
}

# Start RKE2 service with timeout protection
timeout 600 sudo systemctl start $RKE2_SERVICE || {
  echo "RKE2 service start timed out or failed, checking status..."
  sudo systemctl status $RKE2_SERVICE --no-pager || true
  sudo journalctl -u $RKE2_SERVICE --no-pager -n 50 || true
}

echo "Waiting for RKE2 to initialize..."
sleep 120

# Check if RKE2 started successfully
if sudo systemctl is-active $RKE2_SERVICE --quiet; then
  echo "RKE2 service is running successfully"
else
  echo "RKE2 service is not running, checking logs..."
  sudo systemctl status $RKE2_SERVICE --no-pager || true
fi

if [[ -f "$RKE2_CONFIG_DIR/rke2.yaml" ]]; then
  echo "RKE2 kubeconfig found, setting up kubectl..."
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl || {
    echo "Failed to copy kubectl binary, but continuing..."
  }
  
  mkdir -p /home/ubuntu/.kube/
  
  # Create kubeconfig with proper error handling
  if cat "$RKE2_CONFIG_DIR/rke2.yaml" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" > /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml; then
    echo "Successfully created kubeconfig file"
  else
    echo "Failed to create kubeconfig file, but continuing..."
  fi
  
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/* 2>/dev/null || true
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml 2>/dev/null || true
  sudo chmod +x /bin/kubectl 2>/dev/null || true
  
  echo "RKE2 setup completed successfully"
else
  echo "WARNING: RKE2 kubeconfig not found at $RKE2_CONFIG_DIR/rke2.yaml"
  echo "Checking RKE2 service status..."
  sudo systemctl status $RKE2_SERVICE --no-pager || true
  echo "RKE2 setup may have failed, but script completed"
fi

echo "RKE2 setup script finished at $(date)"
