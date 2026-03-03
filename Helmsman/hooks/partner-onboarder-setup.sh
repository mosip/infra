#!/bin/bash

# Skip hook execution during Helmsman dry-run - namespaces and releases
# are not actually created in dry-run mode so kubectl/helm calls will fail.
if [ "${HELMSMAN_MODE:-}" = "dry-run" ]; then
  echo "[DRY-RUN] Skipping partner-onboarder-setup.sh hook (no real resources exist in dry-run)"
  exit 0
fi

NS=onboarder

function installing_onboarder() {

  echo Copy configmaps
  # kubectl -n $NS --ignore-not-found=true delete cm s3
  # kubectl -n $NS --ignore-not-found=true delete cm onboarder-namespace
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
   #Copy configmaps
  $COPY_UTIL configmap global default $NS
  $COPY_UTIL configmap keycloak-env-vars keycloak $NS
  $COPY_UTIL configmap keycloak-host keycloak $NS

  $COPY_UTIL secret s3 s3 $NS
  #$COPY_UTIL secret s3-partner-onboarder s3 $NS
  $COPY_UTIL secret keycloak keycloak $NS
  $COPY_UTIL secret keycloak-client-secrets keycloak $NS
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_onboarder   # calling function
