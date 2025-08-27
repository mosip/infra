#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
source $ENV_FILE_PATH

echo "=== Environment Variables Check ==="
env | grep -E 'K8S|RKE2|WORK|CONTROL|CLUSTER'

echo "=== Critical Variables Check ==="
echo "K8S_INFRA_REPO_URL: ${K8S_INFRA_REPO_URL:-NOT_SET}"
echo "K8S_INFRA_BRANCH: ${K8S_INFRA_BRANCH:-NOT_SET}"
echo "WORK_DIR: ${WORK_DIR:-NOT_SET}"
echo "RKE2_LOCATION: ${RKE2_LOCATION:-NOT_SET}"

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

echo "Setting up work directory: $WORK_DIR"
cd $WORK_DIR

# Clean up any existing k8s-infra directory to avoid conflicts
if [[ -d "k8s-infra" ]]; then
  echo "Removing existing k8s-infra directory"
  rm -rf k8s-infra
fi

echo "=== Git Clone Parameters ==="
echo "Repository URL: ${K8S_INFRA_REPO_URL}"
echo "Branch: ${K8S_INFRA_BRANCH}"
echo "Current directory: $(pwd)"

echo "Cloning k8s-infra repository"
if ! git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH; then
  echo "Failed to clone k8s-infra repository"
  echo "Repository URL: ${K8S_INFRA_REPO_URL}"
  echo "Branch: ${K8S_INFRA_BRANCH}"
  exit 1
fi

echo "Successfully cloned k8s-infra repository"

echo "Setting up RKE2 config directory: $RKE2_CONFIG_DIR"
mkdir -p $RKE2_CONFIG_DIR
chown -R 1000:1000 $RKE2_CONFIG_DIR

echo "Changing to RKE2 location: $RKE2_LOCATION"
cd $RKE2_LOCATION

if [[ -f "$RKE2_CONFIG_DIR/config.yaml" ]]; then
  echo "RKE CONFIG file exists \"$RKE2_CONFIG_DIR/config.yaml\""
  exit 0
fi

# Determine the role of the instance using pattern matching
echo "Waiting 30 seconds before configuring node role..."
sleep 30
echo "Sourcing environment file: $ENV_FILE_PATH"
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
if ! sudo systemctl enable $RKE2_SERVICE; then
  echo "Failed to enable $RKE2_SERVICE"
  exit 1
fi

if ! sudo systemctl start $RKE2_SERVICE; then
  echo "Failed to start $RKE2_SERVICE"
  sudo systemctl status $RKE2_SERVICE || true
  exit 1
fi

echo "Waiting 120 seconds for RKE2 to initialize..."
sleep 120

echo "Checking if RKE2 service is running..."
if ! sudo systemctl is-active --quiet $RKE2_SERVICE; then
  echo "RKE2 service is not running"
  sudo systemctl status $RKE2_SERVICE || true
  exit 1
fi

echo "Setting up kubectl configuration..."
if [[ -f "$RKE2_CONFIG_DIR/rke2.yaml" ]]; then
  echo "Found rke2.yaml, setting up kubectl"
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl
  mkdir -p /home/ubuntu/.kube/
  cat "$RKE2_CONFIG_DIR/rke2.yaml" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" | tee -a /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/*
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml
  sudo chmod +x /bin/kubectl
  echo "kubectl configuration completed successfully"
else
  echo "Warning: rke2.yaml not found at $RKE2_CONFIG_DIR/rke2.yaml"
  echo "RKE2 may not have started properly"
  exit 1
fi

echo "RKE2 setup completed successfully!"
