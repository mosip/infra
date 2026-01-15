#!/bin/bash
# Pre-install hook for esignet keycloak-init
# This script prepares the environment before keycloak-init helm chart is deployed
## Usage: ./esignet-preinstall-keycloak-init.sh [kubeconfig]

NS=esignet

function installing_preinstall_esignet_setup() {
  echo "Copying keycloak configmaps and secret to $NS namespace"
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  $COPY_UTIL configmap keycloak-env-vars keycloak $NS
  $COPY_UTIL secret keycloak keycloak $NS  
  echo "Pre-install setup complete. Helmsman will now deploy esignet-keycloak-init chart."
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_preinstall_esignet_setup   # calling function