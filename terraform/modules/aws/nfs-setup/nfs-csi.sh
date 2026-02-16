#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
mkdir -p ./tmp
LOG_FILE="./tmp/nfs-csi-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
source $ENV_FILE_PATH
env | grep K8S

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

which wget >/dev/null 2>&1 || { echo 'wget tool not found; EXITING'; exit 1; }
if ! [[ -f ./helm ]]; then
  echo "helm not found in current directory";
  wget https://get.helm.sh/$HELM_VERSION
  tar -xzvf $HELM_VERSION  linux-amd64/helm
  mv linux-amd64/helm helm
  rm -rf linux-amd64 $HELM_VERSION
fi

export PATH=$(pwd):$PATH
git clone $K8S_INFRA_REPO_URL -b $K8S_INFRA_BRANCH || true
echo "CLUSTER_NAME : $CLUSTER_NAME"
echo "DEPLOYMENT_TYPE : $DEPLOYMENT_TYPE"
echo "KUBECONFIG_PATH : $KUBECONFIG_PATH"
<<<<<<< HEAD

# Copy kubeconfig from correct path based on deployment type
KUBECONFIG_FILE="$CLUSTER_NAME-CONTROL-PLANE-NODE-1.yaml"
if [ -f "$KUBECONFIG_PATH/$KUBECONFIG_FILE" ]; then
  echo "Found kubeconfig at: $KUBECONFIG_PATH/$KUBECONFIG_FILE"
  cp "$KUBECONFIG_PATH/$KUBECONFIG_FILE" "$K8S_INFRA_NFS_LOCATION/"
else
  echo "ERROR: Kubeconfig not found at: $KUBECONFIG_PATH/$KUBECONFIG_FILE"
  echo "Checking available kubeconfig files..."
  ls -la "$KUBECONFIG_PATH/" || echo "Directory not found: $KUBECONFIG_PATH"
  exit 1
fi

cd $K8S_INFRA_NFS_LOCATION
=======

# Copy kubeconfig from correct path based on deployment type
KUBECONFIG_FILE="$CLUSTER_NAME-CONTROL-PLANE-NODE-1.yaml"
if [ -f "$KUBECONFIG_PATH/$KUBECONFIG_FILE" ]; then
  echo "Found kubeconfig at: $KUBECONFIG_PATH/$KUBECONFIG_FILE"
  cp "$KUBECONFIG_PATH/$KUBECONFIG_FILE" "$K8S_INFRA_NFS_LOCATION/"
else
  echo "ERROR: Kubeconfig not found at: $KUBECONFIG_PATH/$KUBECONFIG_FILE"
  echo "Checking available kubeconfig files..."
  ls -la "$KUBECONFIG_PATH/" || echo "Directory not found: $KUBECONFIG_PATH"
  exit 1
fi

cd "$K8S_INFRA_NFS_LOCATION" || { echo "ERROR: Failed to cd to $K8S_INFRA_NFS_LOCATION" >&2; exit 1; }
>>>>>>> origin/develop
bash $K8S_INFRA_NFS_CSI_SCRIPT_NAME $KUBECONFIG_FILE
