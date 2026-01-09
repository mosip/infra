#!/bin/bash
# Pre/Post-install hook for softhsm-esignet
# This script sets up SoftHSM for esignet and syncs secrets to config-server
# This script is IDEMPOTENT
## Usage: ./softhsm-esignet-setup.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

SOFTHSM_NS=softhsm
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function setup_softhsm_esignet() {
  echo "Setting up SoftHSM for esignet"

  # Create namespace if not exists
  kubectl create ns $SOFTHSM_NS --dry-run=client -o yaml | kubectl apply -f -

  # Add Istio label
  echo "Adding Istio injection label to $SOFTHSM_NS namespace"
  kubectl label ns $SOFTHSM_NS istio-injection=enabled --overwrite

  echo "SoftHSM namespace setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
setup_softhsm_esignet   # calling function
