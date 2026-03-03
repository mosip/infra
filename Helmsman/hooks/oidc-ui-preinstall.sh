#!/bin/bash

# Skip hook execution during Helmsman dry-run - namespaces and releases
# are not actually created in dry-run mode so kubectl/helm calls will fail.
if [ "${HELMSMAN_MODE:-}" = "dry-run" ]; then
  echo "[DRY-RUN] Skipping oidc-ui-preinstall.sh hook (no real resources exist in dry-run)"
  exit 0
fi

DST_NS=esignet
function installing_oidc_ui () {
  echo Copy configmaps to $DST_NS namespace
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  $COPY_UTIL configmap global default $DST_NS
  $COPY_UTIL configmap artifactory-share artifactory $DST_NS
  $COPY_UTIL configmap config-server-share config-server $DST_NS
  $COPY_UTIL configmap softhsm-esignet-share softhsm $DST_NS
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_oidc_ui   # calling function
