#!/bin/bash
# Post-install hook for esignet-resident-oidc-partner-onboarder
# This script copies secrets to config-server and restarts deployments
# This script is IDEMPOTENT
## Usage: ./esignet-partner-onboarder-postinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function postinstall_partner_onboarder() {
  echo "Post-install setup for esignet-resident-oidc-partner-onboarder"

  # Copy esignet-misp-onboarder-key to config-server
  echo "Copying esignet-misp-onboarder-key secret to config-server namespace"
  $COPY_UTIL secret esignet-misp-onboarder-key $NS config-server

  # Copy resident-oidc-onboarder-key to config-server and resident namespaces
  echo "Copying resident-oidc-onboarder-key secret to config-server namespace"
  $COPY_UTIL secret resident-oidc-onboarder-key $NS config-server

  echo "Copying resident-oidc-onboarder-key secret to resident namespace"
  kubectl create ns resident --dry-run=client -o yaml | kubectl apply -f -
  $COPY_UTIL secret resident-oidc-onboarder-key $NS resident

  # Check and set MISP key in config-server (idempotent)
  MISP_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_MISP_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$MISP_KEY_ENV" ]; then
    echo "Adding mosip-esignet-misp-key to config-server"
    kubectl -n config-server set env --keys=mosip-esignet-misp-key --from secret/esignet-misp-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "mosip-esignet-misp-key already exists in config-server, skipping"
  fi

  # Check and set resident OIDC client ID in config-server (idempotent)
  RESIDENT_OIDC_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_RESIDENT_OIDC_CLIENTID") | .name' 2>/dev/null || echo "" )
  if [ -z "$RESIDENT_OIDC_ENV" ]; then
    echo "Adding resident-oidc-clientid to config-server"
    kubectl -n config-server set env --keys=resident-oidc-clientid --from secret/resident-oidc-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "resident-oidc-clientid already exists in config-server, skipping"
  fi

  # Wait for config-server rollout
  echo "Waiting for config-server to be ready"
  kubectl -n config-server rollout status deploy/config-server --timeout=300s

  # Restart esignet deployment to pick up new secrets
  echo "Restarting esignet deployment"
  kubectl rollout restart deployment -n $NS esignet 2>/dev/null || echo "esignet deployment not found, skipping restart"
  kubectl -n $NS rollout status deploy/esignet --timeout=300s 2>/dev/null || true

  # Restart resident deployment to pick up new secrets (if exists)
  echo "Restarting resident deployment (if exists)"
  kubectl rollout restart deployment -n resident resident 2>/dev/null || echo "resident deployment not found, skipping restart"
  kubectl -n resident rollout status deploy/resident --timeout=300s 2>/dev/null || true

  echo "eSignet MISP License Key and Resident OIDC Client ID updated successfully."
  echo "Reports are moved to S3 under onboarder bucket"

  echo "Partner onboarder post-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
postinstall_partner_onboarder   # calling function
