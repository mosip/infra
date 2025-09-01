#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
source $ENV_FILE_PATH
env | grep -E 'K8S|RKE2|WORK|CONTROL'

# Check system resources
echo "=== System Resource Check ==="
echo "Memory usage:"
free -h
echo "Disk usage:"
df -h
echo "CPU info:"
nproc
echo "Network connectivity test:"
ping -c 3 8.8.8.8 || echo "Network connectivity issue detected"
echo "DNS test:"
nslookup github.com || echo "DNS resolution issue detected"
echo "Test HTTPS connectivity:"
curl -v -m 30 https://get.rke2.io/ || echo "RKE2 download site unreachable"
echo "Test GitHub connectivity:"
curl -v -m 30 https://github.com || echo "GitHub unreachable"
echo "Check NAT Gateway connectivity:"
curl -v -m 30 https://httpbin.org/ip || echo "External IP check failed"
echo "================================"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
#set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes


echo "Installing RKE2"
# Pre-installation connectivity verification
echo "=== Verifying Internet Connectivity Before RKE2 Download ==="
for site in "https://get.rke2.io/" "https://github.com" "https://raw.githubusercontent.com"; do
    echo "Testing connectivity to: $site"
    if timeout 30 curl -s -I "$site" >/dev/null 2>&1; then
        echo "✓ $site is reachable"
    else
        echo "✗ $site is NOT reachable - this will cause installation failure"
        echo "Checking routing..."
        ip route show
        echo "Checking DNS..."
        cat /etc/resolv.conf
        echo "Testing with different DNS..."
        nslookup github.com 8.8.8.8 || true
    fi
done
echo "==============================================="

RKE2_EXISTENCE=$( which rke2 || true)
if [[ -z $RKE2_EXISTENCE ]]; then
  echo "Downloading RKE2 installer..."
  timeout 300 curl -sfL https://get.rke2.io | sh - || {
    echo "Failed to download RKE2 after 5 minutes, retrying..."
    sleep 30
    timeout 300 curl -sfL https://get.rke2.io | sh -
  }
fi

cd $WORK_DIR
echo "Cloning K8S infrastructure repository..."
timeout 120 git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH || {
  echo "Git clone failed or repository already exists, checking if directory exists..."
  if [[ ! -d "k8s-infra" ]]; then
    echo "Repository not found and clone failed, exiting..."
    exit 1
  fi
}

mkdir -p $RKE2_CONFIG_DIR
chown -R 1000:1000 $RKE2_CONFIG_DIR

cd $RKE2_LOCATION

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

echo "Starting RKE2 service: $RKE2_SERVICE"
sudo systemctl enable $RKE2_SERVICE
sudo systemctl start $RKE2_SERVICE

echo "Waiting for RKE2 service to be ready..."
# Wait up to 10 minutes for the service to be active
timeout 600 bash -c 'while [[ $(sudo systemctl is-active '$RKE2_SERVICE') != "active" ]]; do 
  echo "Service status: $(sudo systemctl is-active '$RKE2_SERVICE')"; 
  sleep 10; 
done' || {
  echo "RKE2 service failed to start within 10 minutes"
  sudo systemctl status $RKE2_SERVICE
  exit 1
}

echo "RKE2 service is active, waiting additional 2 minutes for full initialization..."
sleep 120

if [[ -f "$RKE2_CONFIG_DIR/rke2.yaml" ]]; then
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl
  mkdir -p /home/ubuntu/.kube/
  cat "$RKE2_CONFIG_DIR/rke2.yaml" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" | tee -a /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/*
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml
  sudo chmod +x /bin/kubectl
fi
