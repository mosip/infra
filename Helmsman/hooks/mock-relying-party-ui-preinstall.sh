#!/bin/bash
# Pre-install hook for mock-relying-party-ui
# This script sets up the namespace and Istio label
# This script is IDEMPOTENT
## Usage: ./mock-relying-party-ui-preinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet

function preinstall_mock_relying_party_ui() {
  echo "Pre-install setup for mock-relying-party-ui"

  # Create namespace if not exists
  kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f -

  # Add Istio label
  echo "Adding Istio injection label to $NS namespace"
  kubectl label ns $NS istio-injection=enabled --overwrite

  echo "mock-relying-party-ui pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_mock_relying_party_ui   # calling function
