#!/bin/bash
# Script to initialize esignet DB.
## Usage: ./init_db.sh [kubeconfig]

NS=esignet
function installing_esignet_init_db () {

  echo Removing existing mosip_esignet DB installation
  helm -n $NS delete postgres-init-esignet || true

  echo Delete existing secrets to allow fresh install
  kubectl -n $NS delete secret db-common-secrets --ignore-not-found=true
  kubectl -n $NS delete secret postgres-postgresql --ignore-not-found=true

  echo Copy postgres-postgresql secret for esignet DB initialization  
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  
  # Copy only postgres-postgresql secret - db-common-secrets will be created by Helm chart
  if kubectl -n postgres get secret postgres-postgresql &>/dev/null; then
    $COPY_UTIL secret postgres-postgresql postgres $NS
  else
    echo "Warning: postgres-postgresql secret not found in postgres namespace, skipping copy"
  fi
  
  # NOTE: db-common-secrets is created by the postgres-init Helm chart, not copied here
  
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_esignet_init_db   # calling function