#!/bin/bash

# SSH Connection Keep-Alive (prevent SSH timeouts)
echo "Configuring SSH keep-alive settings..."
sudo bash -c 'cat >> /etc/ssh/sshd_config << EOF
# Terraform SSH Connection Optimizations
ClientAliveInterval 60
ClientAliveCountMax 10
TCPKeepAlive yes
EOF'

# Restart SSH service to apply changes (in background to avoid connection loss)
sudo systemctl reload ssh &

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/rke2-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
source $ENV_FILE_PATH
env | grep -E 'K8S|RKE2|WORK|CONTROL'

# Send periodic keep-alive signals to prevent SSH timeout
keep_alive_pid=""
start_keep_alive() {
    while true; do
        echo "Keep-alive: $(date)" >> "$LOG_FILE"
        sleep 30
    done &
    keep_alive_pid=$!
}

stop_keep_alive() {
    if [ ! -z "$keep_alive_pid" ]; then
        kill $keep_alive_pid 2>/dev/null || true
    fi
}

# Start keep-alive
start_keep_alive

# Trap to ensure keep-alive is stopped on script exit
trap stop_keep_alive EXIT

# Manual logging instead of exec redirection to avoid SSH issues
# exec > >(tee -a "$LOG_FILE") 2>&1

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

echo "Installing RKE2" | tee -a "$LOG_FILE"
RKE2_EXISTENCE=$( which rke2 || true)
if [[ -z $RKE2_EXISTENCE ]]; then
  echo "Downloading and installing RKE2..." | tee -a "$LOG_FILE"
  curl -sfL https://get.rke2.io | sh - 2>&1 | tee -a "$LOG_FILE"
fi

cd $WORK_DIR
echo "Cloning k8s-infra repository..." | tee -a "$LOG_FILE"

# Add timeout and retry logic for git clone
if [ ! -d "k8s-infra" ]; then
  echo "Cloning repository with timeout..." | tee -a "$LOG_FILE"
  timeout 300 git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH 2>&1 | tee -a "$LOG_FILE" || {
    echo "First clone attempt failed, retrying..." | tee -a "$LOG_FILE"
    rm -rf k8s-infra 2>/dev/null || true
    timeout 300 git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH 2>&1 | tee -a "$LOG_FILE" || {
      echo "Git clone failed after retry. Exiting." | tee -a "$LOG_FILE"
      exit 1
    }
  }
else
  echo "k8s-infra directory already exists, skipping clone." | tee -a "$LOG_FILE"
fi

echo "Creating RKE2 config directory..." | tee -a "$LOG_FILE"
mkdir -p $RKE2_CONFIG_DIR
chown -R 1000:1000 $RKE2_CONFIG_DIR

echo "Changing to RKE2 location: $RKE2_LOCATION" | tee -a "$LOG_FILE"
cd $RKE2_LOCATION

if [[ -f "$RKE2_CONFIG_DIR/config.yaml" ]]; then
  echo "RKE CONFIG file exists \"$RKE2_CONFIG_DIR/config.yaml\"" | tee -a "$LOG_FILE"
  exit 0
fi

# Determine the role of the instance using pattern matching
echo "Waiting 30 seconds before configuring node role..." | tee -a "$LOG_FILE"
sleep 30
source $ENV_FILE_PATH
echo "Configuring node with NODE_NAME: $NODE_NAME" | tee -a "$LOG_FILE"
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

echo "Configuring RKE2 config file..." | tee -a "$LOG_FILE"
sed -i "s/<configure-some-token-here>/$K8S_TOKEN/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-name>/${NODE_NAME}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-internal-ip>/${INTERNAL_IP}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<primary-server-ip>/${CONTROL_PLANE_NODE_1}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<cluster-name>/${CLUSTER_DOMAIN}/g" $RKE2_CONFIG_DIR/config.yaml

source $ENV_FILE_PATH
echo "Environment variables:" | tee -a "$LOG_FILE"
cat $ENV_FILE_PATH | tee -a "$LOG_FILE"

echo "Starting RKE2 service: $RKE2_SERVICE" | tee -a "$LOG_FILE"
sudo systemctl enable $RKE2_SERVICE 2>&1 | tee -a "$LOG_FILE"
sudo systemctl start $RKE2_SERVICE 2>&1 | tee -a "$LOG_FILE"

echo "Waiting 120 seconds for RKE2 to start..." | tee -a "$LOG_FILE"
sleep 120
echo "Checking RKE2 service status..." | tee -a "$LOG_FILE"
sudo systemctl status $RKE2_SERVICE --no-pager 2>&1 | tee -a "$LOG_FILE" || true

if [[ -f "$RKE2_CONFIG_DIR/rke2.yaml" ]]; then
  echo "Configuring kubectl and kubeconfig..." | tee -a "$LOG_FILE"
  sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl
  mkdir -p /home/ubuntu/.kube/
  cat "$RKE2_CONFIG_DIR/rke2.yaml" | sed "s/127.0.0.1/${INTERNAL_IP}/g" | sed "s/default/${CLUSTER_DOMAIN}/g" | tee -a /home/ubuntu/.kube/${CLUSTER_DOMAIN}-${NODE_NAME}.yaml
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/*
  sudo chmod -R 444 /home/ubuntu/.kube/*.yaml
  sudo chmod +x /bin/kubectl
  echo "RKE2 setup completed successfully!" | tee -a "$LOG_FILE"
else
  echo "ERROR: RKE2 config file not found after setup!" | tee -a "$LOG_FILE"
  exit 1
fi

# Stop keep-alive (trap will handle this, but let's be explicit)
stop_keep_alive
echo "Script execution finished at $(date)" | tee -a "$LOG_FILE"