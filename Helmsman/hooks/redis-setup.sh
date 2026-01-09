#!/bin/bash
# Installs redis
## Usage: ./install.sh [kubeconfig]

NS=redis

function installing_redis() {
  echo Istio label
  kubectl label ns $NS istio-injection=enabled --overwrite

  echo Copy redis secret to config-server namespace
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  $COPY_UTIL secret redis redis config-server 

  kubectl -n config-server set env --keys=redis-password --from secret/redis deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_

  echo Installed prereq-redis service
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_redis   # calling function
