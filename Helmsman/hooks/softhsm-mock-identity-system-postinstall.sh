#!/bin/bash
# Post-install hook for softhsm-mock-identity-system
# This script copies secret to config-server and sets up environment variables
# This script is IDEMPOTENT
## Usage: ./softhsm-mock-identity-system-postinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

SOFTHSM_NS=softhsm
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function postinstall_softhsm_mock_identity() {
  echo "Post-install setup for softhsm-mock-identity-system"

  # Copy softhsm-mock-identity-system secret to config-server
  echo "Copying softhsm-mock-identity-system secret to config-server namespace"
  $COPY_UTIL secret softhsm-mock-identity-system $SOFTHSM_NS config-server

  # Check and set softhsm security-pin in config-server (idempotent)
  SOFTHSM_MOCK_PIN_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_SOFTHSM_MOCK_IDENTITY_SYSTEM_SECURITY_PIN") | .name' 2>/dev/null || echo "" )
  if [ -z "$SOFTHSM_MOCK_PIN_ENV" ]; then
    echo "Adding softhsm-mock-identity-system security-pin to config-server"
    kubectl -n config-server set env --keys=security-pin --from secret/softhsm-mock-identity-system deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_SOFTHSM_MOCK_IDENTITY_SYSTEM_
  else
    echo "softhsm-mock-identity-system security-pin already exists in config-server, skipping"
  fi

  # Wait for config-server rollout
  echo "Waiting for config-server to be ready"
  kubectl -n config-server rollout status deploy/config-server --timeout=300s

  echo "SoftHSM mock-identity-system post-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
postinstall_softhsm_mock_identity   # calling function
