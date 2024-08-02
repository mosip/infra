#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
sudo mv /tmp/rke2-setup.log /tmp/rke2-setup.log.old || true
LOG_FILE="/tmp/rke2-setup.log"
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
git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH || true # read it from variables

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
  cp rke2-etcd-worker.conf.template $RKE2_CONFIG_DIR/config.yaml
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

else
  echo "WORKER NODE"
  cp rke2-worker.conf.template $RKE2_CONFIG_DIR/config.yaml
  RKE2_SERVICE=rke2-agent
  export RKE2_SERVICE="rke2-agent" | sudo tee -a $ENV_FILE_PATH

fi

cd $RKE2_CONFIG_DIR

sed -i 's/<configure-some-token-here>/abc123/g' $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-name>/${NODE_NAME}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<node-internal-ip>/${INTERNAL_IP}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<primary-server-ip>/${CONTROL_PLANE_NODE_1}/g" $RKE2_CONFIG_DIR/config.yaml
sed -i "s/<cluster-name>/${CLUSTER_DOMAIN}/g" $RKE2_CONFIG_DIR/config.yaml


source $ENV_FILE_PATH
cat $ENV_FILE_PATH

sudo systemctl enable $RKE2_SERVICE
sudo systemctl start $RKE2_SERVICE
