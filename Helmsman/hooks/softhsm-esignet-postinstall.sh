#!/bin/bash
# Post-install hook for softhsm-esignet
# This script copies softhsm secret to config-server and sets up environment variables
# This script is IDEMPOTENT
## Usage: ./softhsm-esignet-postinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

SOFTHSM_NS=softhsm
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function postinstall_softhsm_esignet() {
  echo "Post-install setup for SoftHSM esignet"

  # Copy global configmap to config-server if not exists
  echo "Copying global configmap to config-server namespace"
  $COPY_UTIL configmap global default config-server

  # Copy softhsm-esignet secret to config-server
  echo "Copying softhsm-esignet secret to config-server namespace"
  $COPY_UTIL secret softhsm-esignet $SOFTHSM_NS config-server

  # Check and set esignet host in config-server
  ESIGNET_HOST_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_HOST") | .name' 2>/dev/null || echo "" )
  if [ -z "$ESIGNET_HOST_ENV" ]; then
    echo "Adding mosip-esignet-host to config-server"
    kubectl -n config-server set env --keys=mosip-esignet-host --from configmap/global deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "mosip-esignet-host already exists in config-server, skipping"
  fi

  # Check and set softhsm security-pin in config-server
  SOFTHSM_PIN_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_SOFTHSM_ESIGNET_SECURITY_PIN") | .name' 2>/dev/null || echo "" )
  if [ -z "$SOFTHSM_PIN_ENV" ]; then
    echo "Adding softhsm security-pin to config-server"
    kubectl -n config-server set env --keys=security-pin --from secret/softhsm-esignet deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_SOFTHSM_ESIGNET_
  else
    echo "softhsm security-pin already exists in config-server, skipping"
  fi

  # Wait for config-server rollout
  echo "Waiting for config-server to be ready"
  
  # Check if there are any pods stuck in terminating state
  TERMINATING_PODS=$(kubectl -n config-server get pods -l app.kubernetes.io/name=config-server --field-selector=status.phase=Terminating -o name 2>/dev/null || echo "")
  if [ -n "$TERMINATING_PODS" ]; then
    echo "Found terminating pods, waiting for them to clear..."
    for pod in $TERMINATING_PODS; do
      echo "Waiting for $pod to terminate..."
      kubectl -n config-server wait --for=delete "$pod" --timeout=120s 2>/dev/null || true
    done
  fi
  
  # Wait for rollout with increased timeout
  if ! kubectl -n config-server rollout status deploy/config-server --timeout=600s; then
    echo "Rollout timed out, checking deployment status..."
    kubectl -n config-server describe deploy/config-server
    kubectl -n config-server get pods -l app.kubernetes.io/name=config-server
    echo "Attempting to restart stuck rollout..."
    kubectl -n config-server rollout restart deploy/config-server
    kubectl -n config-server rollout status deploy/config-server --timeout=300s
  fi

  echo "SoftHSM esignet post-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
postinstall_softhsm_esignet   # calling function
