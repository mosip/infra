#!/bin/bash
# Pre-install hook for softhsm-mock-identity-system
# This script sets up the softhsm namespace and Istio label
# This script is IDEMPOTENT
## Usage: ./softhsm-mock-identity-system-preinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

SOFTHSM_NS=softhsm

function preinstall_softhsm_mock_identity() {
  echo "Pre-install setup for softhsm-mock-identity-system"

  # Create namespace if not exists
  kubectl create ns $SOFTHSM_NS --dry-run=client -o yaml | kubectl apply -f -

  # Add Istio label
  echo "Adding Istio injection label to $SOFTHSM_NS namespace"
  kubectl label ns $SOFTHSM_NS istio-injection=enabled --overwrite

  echo "SoftHSM mock-identity-system pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_softhsm_mock_identity   # calling function
