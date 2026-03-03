#!/bin/bash

# Skip hook execution during Helmsman dry-run - namespaces and releases
# are not actually created in dry-run mode so kubectl/helm calls will fail.
if [ "${HELMSMAN_MODE:-}" = "dry-run" ]; then
  echo "[DRY-RUN] Skipping config-server-setup.sh hook (no real resources exist in dry-run)"
  exit 0
fi
# Installs config-server

NS=config-server

function copy_resource() {
    echo Istio label
    kubectl label ns $NS istio-injection=enabled --overwrite
    
    echo Copying Resorces
    COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
    #Copy configmaps
    $COPY_UTIL configmap global default $NS
    $COPY_UTIL configmap keycloak-host keycloak $NS
    $COPY_UTIL configmap activemq-activemq-artemis-share activemq $NS
    $COPY_UTIL configmap s3 s3 $NS
    $COPY_UTIL configmap msg-gateway msg-gateways $NS
    $COPY_UTIL configmap postgres-setup-config postgres $NS
    #Copy Secrets
    $COPY_UTIL secret db-common-secrets postgres $NS
    $COPY_UTIL secret keycloak keycloak $NS
    $COPY_UTIL secret keycloak-client-secrets keycloak $NS
    $COPY_UTIL secret activemq-activemq-artemis activemq $NS
    $COPY_UTIL secret softhsm-kernel softhsm $NS
    $COPY_UTIL secret softhsm-ida softhsm $NS
    $COPY_UTIL secret s3 s3 $NS
    $COPY_UTIL secret msg-gateway msg-gateways $NS
    $COPY_UTIL secret mosip-captcha captcha $NS
    $COPY_UTIL secret conf-secrets-various conf-secrets $NS

    return 0
}
# Set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialized variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
copy_resource   # calling function
