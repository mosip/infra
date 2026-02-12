#!/bin/bash
# Pre-install hook for esignet keycloak-init
# This script prepares the environment before keycloak-init helm chart is deployed
## Usage: ./esignet-preinstall-keycloak-init.sh [kubeconfig]

NS=esignet

function installing_preinstall_esignet_setup() {
  echo "creating and adding roles to keycloak pms & mpartner_default_auth clients for ESIGNET"
  kubectl -n $NS delete secret  --ignore-not-found=true keycloak-client-secrets
  helm -n $NS delete esignet-keycloak-init || true
  echo "Copying keycloak configmaps and secret to $NS namespace"
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  $COPY_UTIL configmap keycloak-env-vars keycloak $NS
  $COPY_UTIL secret keycloak keycloak $NS

  # Fetch PMS and MPARTNER secrets from keycloak namespace
  echo "Checking if PMS & mpartner_default_auth client secrets exist..."
  PMS_CLIENT_SECRET_KEY='mosip_pms_client_secret'
  PMS_CLIENT_SECRET_VALUE="$(kubectl -n keycloak get secrets keycloak-client-secrets -o jsonpath="{.data.${PMS_CLIENT_SECRET_KEY}}" | base64 -d)"
  export PMS_CLIENT_SECRET_KEY
  export PMS_CLIENT_SECRET_VALUE
  
  MPARTNER_DEFAULT_AUTH_SECRET_KEY='mpartner_default_auth_secret'
  MPARTNER_DEFAULT_AUTH_SECRET_VALUE="$(kubectl -n keycloak get secrets keycloak-client-secrets -o jsonpath="{.data.${MPARTNER_DEFAULT_AUTH_SECRET_KEY}}" | base64 -d)"
  export MPARTNER_DEFAULT_AUTH_SECRET_KEY
  export MPARTNER_DEFAULT_AUTH_SECRET_VALUE

  echo "PMS_CLIENT_SECRET_KEY: $PMS_CLIENT_SECRET_KEY"
  echo "MPARTNER_DEFAULT_AUTH_SECRET_KEY: $MPARTNER_DEFAULT_AUTH_SECRET_KEY"
  # Note: Not printing secret values for security reasons

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