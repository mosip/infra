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


echo "Installing RKE2"
RKE2_EXISTENCE=$( which rke2 || true)
if [[ -z $RKE2_EXISTENCE ]]; then
  curl -sfL https://get.rke2.io | sh -
fi

cd $WORK_DIR
echo "Cloning k8s-infra repository (shallow clone for faster download)..."
if [ -d "k8s-infra" ]; then
  echo "k8s-infra directory already exists, updating..."
  # Fix git ownership issue
  echo "Fixing git ownership for k8s-infra directory..."
  sudo chown -R ubuntu:ubuntu k8s-infra/
  git config --global --add safe.directory /home/ubuntu/k8s-infra
  cd k8s-infra
  timeout 300 git fetch origin $K8S_INFRA_BRANCH --depth=1 || echo "Git fetch failed or timed out, continuing..."
  git checkout $K8S_INFRA_BRANCH || echo "Git checkout failed, continuing..."
  cd ..
else
  echo "Starting git clone with 5-minute timeout..."
  timeout 300 git clone --depth=1 --single-branch -b $K8S_INFRA_BRANCH $K8S_INFRA_REPO_URL || echo "Git clone failed or timed out, continuing..."
  if [ -d "k8s-infra" ]; then
    echo "Git clone completed successfully"
    # Ensure proper ownership after clone
    sudo chown -R ubuntu:ubuntu k8s-infra/
    git config --global --add safe.directory /home/ubuntu/k8s-infra
  else
    echo "Git clone failed - directory not found"
  fi
fi

echo "Successfully cloned/updated k8s-infra repository"

mkdir -p $RKE2_CONFIG_DIR
chown -R 1000:1000 $RKE2_CONFIG_DIR
echo "Created and configured RKE2 config directory: $RKE2_CONFIG_DIR"

echo "Verifying k8s-infra directory structure:"
ls -la $WORK_DIR/k8s-infra/ || echo "Failed to list k8s-infra contents"
echo "Checking for k8-cluster directory:"
ls -la $WORK_DIR/k8s-infra/k8-cluster/ || echo "k8-cluster directory not found"

cd $RKE2_LOCATION
echo "Changed to RKE2 location: $RKE2_LOCATION"
echo "Contents of RKE2 location:"
ls -la . || echo "Failed to list RKE2 location contents"

if [[ -f "$RKE2_CONFIG_DIR/config.yaml" ]]; then
  echo "RKE CONFIG file exists \"$RKE2_CONFIG_DIR/config.yaml\""
  exit 0
fi

# Determine the role of the instance using pattern matching
echo "Determining node role based on NODE_NAME: $NODE_NAME"
echo "Available template files in current directory:"
ls -la *.template || echo "No template files found"
echo "Current working directory: $(pwd)"

sleep 5  # Reduced from 30 seconds to 5 seconds
source $ENV_FILE_PATH
if [[ "$NODE_NAME" == CONTROL-PLANE-NODE-1 ]]; then
  echo "PRIMARY CONTROL PLANE NODE"
  RKE2_SERVICE="rke2-server"
  echo "Copying template: rke2-server-control-plane-primary.conf.template"
  if [[ -f "rke2-server-control-plane-primary.conf.template" ]]; then
    cp rke2-server-control-plane-primary.conf.template $RKE2_CONFIG_DIR/config.yaml
    echo "Template copied successfully"
  else
    echo "ERROR: Template file rke2-server-control-plane-primary.conf.template not found!"
    exit 1
  fi
  export RKE2_SERVICE="rke2-server" | sudo tee -a $ENV_FILE_PATH

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
  export RKE2_SERVICE="rke2-server" | sudo tee -a $ENV_FILE_PATH

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
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

else
  echo "WORKER NODE"
  echo "Copying template: rke2-agents.conf.template"
  if [[ -f "rke2-agents.conf.template" ]]; then
    cp rke2-agents.conf.template $RKE2_CONFIG_DIR/config.yaml
    echo "Template copied successfully"
  else
    echo "ERROR: Template file rke2-agents.conf.template not found!"
    exit 1
  fi
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

fi

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

source $ENV_FILE_PATH
echo "Environment variables:"
cat $ENV_FILE_PATH

echo "Enabling and starting RKE2 service: $RKE2_SERVICE"
sudo systemctl enable $RKE2_SERVICE || echo "Failed to enable $RKE2_SERVICE"
sudo systemctl start $RKE2_SERVICE || echo "Failed to start $RKE2_SERVICE"

echo "Waiting for RKE2 service to initialize (2 minutes)..."
sleep 120

echo "Checking RKE2 service status:"
sudo systemctl status $RKE2_SERVICE --no-pager || echo "Service status check failed"

if [[ -f "$RKE2_CONFIG_DIR/rke2.yaml" ]]; then
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl
  mkdir -p /home/ubuntu/.kube/
  cat "$RKE2_CONFIG_DIR/rke2.yaml" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" | tee -a /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/*
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml
  sudo chmod +x /bin/kubectl
fi
