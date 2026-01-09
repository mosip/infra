#!/bin/bash
# Post-install hook for esignet
# This script sets up config-server environment variables for captcha and MISP
# This script is IDEMPOTENT
## Usage: ./esignet-postinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet

function postinstall_esignet() {
  echo "Post-install setup for esignet"

  # Check and set captcha site key in config-server
  CAPTCHA_SITE_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_ESIGNET_CAPTCHA_SITE_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$CAPTCHA_SITE_KEY_ENV" ]; then
    echo "Adding esignet-captcha-site-key to config-server"
    kubectl -n config-server set env --keys=esignet-captcha-site-key --from secret/esignet-captcha deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "esignet-captcha-site-key already exists in config-server, skipping"
  fi

  # Check and set captcha secret key in config-server
  CAPTCHA_SECRET_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_ESIGNET_CAPTCHA_SECRET_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$CAPTCHA_SECRET_KEY_ENV" ]; then
    echo "Adding esignet-captcha-secret-key to config-server"
    kubectl -n config-server set env --keys=esignet-captcha-secret-key --from secret/esignet-captcha deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "esignet-captcha-secret-key already exists in config-server, skipping"
  fi

  # Check and set MISP key in config-server
  MISP_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_MISP_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$MISP_KEY_ENV" ]; then
    echo "Adding mosip-esignet-misp-key to config-server"
    kubectl -n config-server set env --keys=mosip-esignet-misp-key --from secret/esignet-misp-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "mosip-esignet-misp-key already exists in config-server, skipping"
  fi

  # Wait for config-server rollout
  echo "Waiting for config-server to be ready"
  kubectl -n config-server rollout status deploy/config-server --timeout=300s

  echo "esignet post-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
postinstall_esignet   # calling function
