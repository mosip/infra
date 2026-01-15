#!/bin/bash
# Script to initialize esignet DB.
## Usage: ./init_db.sh [kubeconfig]

NS=esignet
function installing_esignet_init_db () {

  echo Removing existing mosip_esignet DB installation
  helm -n $NS delete postgres-init-esignet || true

  echo Delete existing DB common sets
  kubectl -n $NS delete secret db-common-secrets --ignore-not-found=true

  echo Copy secrets for esignet DB initialization  
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  $COPY_UTIL secret postgres-postgresql postgres $NS
  $COPY_UTIL secret db-common-secrets  postgres $NS
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_esignet_init_db   # calling function