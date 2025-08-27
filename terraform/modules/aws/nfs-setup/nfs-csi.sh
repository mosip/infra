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

cp $CLUSTER_NAME-CONTROL-PLANE-NODE-1.yaml $K8S_INFRA_NFS_LOCATION
cd $K8S_INFRA_NFS_LOCATION
bash $K8S_INFRA_NFS_CSI_SCRIPT_NAME $CLUSTER_NAME-CONTROL-PLANE-NODE-1.yaml
