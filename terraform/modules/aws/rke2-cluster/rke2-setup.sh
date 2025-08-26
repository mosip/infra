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
# set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable (commented out - too strict)
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

# Add error handler
trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Validate required environment variables
echo "Validating required environment variables..."
required_vars=("WORK_DIR" "K8S_INFRA_REPO_URL" "K8S_INFRA_BRANCH" "RKE2_CONFIG_DIR" "RKE2_LOCATION" "NODE_NAME" "K8S_TOKEN" "INTERNAL_IP" "CONTROL_PLANE_NODE_1" "CLUSTER_DOMAIN")

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    else
        echo "$var is set"
    fi
done

echo "All required environment variables are present"


echo "Installing RKE2"
RKE2_EXISTENCE=$( which rke2 2>/dev/null || echo "")
if [[ -z "$RKE2_EXISTENCE" ]]; then
  echo "RKE2 not found, installing..."
  curl -sfL https://get.rke2.io | sh -
  echo "RKE2 installation completed"
else
  echo "RKE2 already installed at: $RKE2_EXISTENCE"
fi

cd $WORK_DIR
echo "Cloning K8S infrastructure repository..."
if [ -d "k8s-infra" ]; then
  echo "k8s-infra directory already exists, updating..."
  cd k8s-infra
  git pull origin $K8S_INFRA_BRANCH || echo "Warning: git pull failed, continuing with existing files"
  cd $WORK_DIR
else
  git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH || {
    echo "Warning: git clone failed, but continuing..."
  }
fi

mkdir -p $RKE2_CONFIG_DIR
chown -R 1000:1000 $RKE2_CONFIG_DIR

cd $RKE2_LOCATION

if [[ -f "$RKE2_CONFIG_DIR/config.yaml" ]]; then
  echo "RKE CONFIG file exists \"$RKE2_CONFIG_DIR/config.yaml\""
  echo "RKE2 setup already completed, exiting successfully"
  exit 0
fi

# Determine the role of the instance using pattern matching
sleep 30
source $ENV_FILE_PATH
echo "Node name: $NODE_NAME"
echo "Current directory: $(pwd)"
echo "Files in current directory:"
ls -la

if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-1 ]]; then
  echo "PRIMARY CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  echo "Looking for primary control plane config template..."
  ls -la rke2-server-control-plane-primary.conf.template 2>/dev/null || echo "Template file not found!"
  if cp rke2-server-control-plane-primary.conf.template $RKE2_CONFIG_DIR/config.yaml; then
    echo "Successfully copied primary control plane config template"
  else
    echo "Error: Failed to copy primary control plane config template"
    exit 1
  fi
  export RKE2_SERVICE="rke2-server" | sudo tee -a $ENV_FILE_PATH

elif [[ "$NODE_NAME" == CONTROL-PLANE-NODE-* ]]; then
  echo "SUBSEQUENT CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  if cp rke2-server-control-plane.subsequent.conf.template $RKE2_CONFIG_DIR/config.yaml; then
    echo "Successfully copied subsequent control plane config template"
  else
    echo "Error: Failed to copy subsequent control plane config template"
    exit 1
  fi
  export RKE2_SERVICE="rke2-server" | sudo tee -a $ENV_FILE_PATH

elif [[ "$NODE_NAME" == ETCD-NODE-* ]]; then
  echo "ETCD NODE"
  if cp rke2-etcd-agents.conf.template $RKE2_CONFIG_DIR/config.yaml; then
    echo "Successfully copied ETCD config template"
  else
    echo "Error: Failed to copy ETCD config template"
    exit 1
  fi
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

else
  echo "WORKER NODE"
  if cp rke2-agents.conf.template $RKE2_CONFIG_DIR/config.yaml; then
    echo "Successfully copied worker config template"
  else
    echo "Error: Failed to copy worker config template"
    exit 1
  fi
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

fi

cd $RKE2_CONFIG_DIR

echo "Configuring RKE2 config file with cluster-specific values..."
sed -i "s/<configure-some-token-here>/$K8S_TOKEN/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-name>/${NODE_NAME}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-internal-ip>/${INTERNAL_IP}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<primary-server-ip>/${CONTROL_PLANE_NODE_1}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<cluster-name>/${CLUSTER_DOMAIN}/g" $RKE2_CONFIG_DIR/config.yaml

echo "Configuration file after substitutions:"
cat $RKE2_CONFIG_DIR/config.yaml

echo "Environment variables:"
source $ENV_FILE_PATH
cat $ENV_FILE_PATH

echo "Starting RKE2 service: $RKE2_SERVICE"

sudo systemctl enable $RKE2_SERVICE
sudo systemctl start $RKE2_SERVICE

echo "Waiting for RKE2 service to be ready..."
# Wait for service with timeout and status checks
for i in {1..30}; do
    echo "Checking RKE2 service status (attempt $i/30)..."
    if sudo systemctl is-active --quiet $RKE2_SERVICE; then
        echo "RKE2 service is running successfully"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo "Error: RKE2 service failed to start within 5 minutes"
        echo "Service status:"
        sudo systemctl status $RKE2_SERVICE || true
        echo "Service logs:"
        sudo journalctl -u $RKE2_SERVICE --no-pager -n 50 || true
        exit 1
    fi
    
    echo "Service not ready yet, waiting 10 seconds..."
    sleep 10
done

# Additional wait for RKE2 to fully initialize
echo "Waiting additional time for RKE2 to fully initialize..."
sleep 60

if [[ -f "$RKE2_CONFIG_DIR/rke2.yaml" ]]; then
  echo "RKE2 kubeconfig found, setting up kubectl access..."
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl
  mkdir -p /home/ubuntu/.kube/
  cat "$RKE2_CONFIG_DIR/rke2.yaml" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" | tee -a /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/*
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml
  sudo chmod +x /bin/kubectl
  echo "Kubectl access configured successfully"
else
  echo "Warning: RKE2 kubeconfig not found at $RKE2_CONFIG_DIR/rke2.yaml"
  echo "RKE2 may still be initializing. This is normal for the first run."
fi

echo "RKE2 setup completed successfully!"
echo "Script finished at: $(date)"
exit 0
