#!/bin/bash

# Skip hook execution during Helmsman dry-run - namespaces and releases
# are not actually created in dry-run mode so kubectl/helm calls will fail.
if [ "${HELMSMAN_MODE:-}" = "dry-run" ]; then
  echo "[DRY-RUN] Skipping mock-identity-system-preinstall.sh hook (no real resources exist in dry-run)"
  exit 0
fi
# Pre-install hook for mock-identity-system
# This script copies configmaps and sets up the namespace
# This script is IDEMPOTENT
## Usage: ./mock-identity-system-preinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function preinstall_mock_identity_system() {
  echo "Pre-install setup for mock-identity-system"

  # Create namespace if not exists
  kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f -

  # Add Istio label
  echo "Adding Istio injection label to $NS namespace"
  kubectl label ns $NS istio-injection=enabled --overwrite

  # Copy configmaps
  echo "Copying configmaps to $NS namespace"
  $COPY_UTIL configmap global default $NS
  $COPY_UTIL configmap artifactory-1202-share artifactory-1202 $NS 2>/dev/null || echo "artifactory-1202-share configmap not found, skipping"
  $COPY_UTIL configmap config-server-share config-server $NS 2>/dev/null || echo "config-server-share configmap not found, skipping"
  $COPY_UTIL configmap softhsm-mock-identity-system-share softhsm $NS 2>/dev/null || echo "softhsm-mock-identity-system-share configmap not found, skipping"

  echo "mock-identity-system pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_mock_identity_system   # calling function
