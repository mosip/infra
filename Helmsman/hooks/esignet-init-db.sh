#!/bin/bash
# Script to initialize esignet and mockidentitysystem DBs.
# DB_USER_PASSWORD must be set as env var before running Helmsman
# (fetched from postgres namespace in GitHub Actions workflow)

NS=esignet

function installing_esignet_init_db () {

  echo "Removing existing postgres-init-esignet release"
  helm -n $NS delete postgres-init || true

  echo "Delete existing secrets to allow fresh install"
  kubectl -n $NS delete secret db-common-secrets --ignore-not-found=true
  kubectl -n $NS delete secret postgres-postgresql --ignore-not-found=true

  echo "Copy postgres-postgresql secret from postgres namespace"
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  
  # Copy postgres-postgresql secret (postgres connection credentials for superuser)
  if kubectl -n postgres get secret postgres-postgresql &>/dev/null; then
    $COPY_UTIL secret postgres-postgresql postgres $NS
    echo "✓ postgres-postgresql secret copied"
  else
    echo "ERROR: postgres-postgresql secret not found in postgres namespace!"
    exit 1
  fi
  
  # db-common-secrets will be created by Helm chart using DB_USER_PASSWORD env var
  # passed via DSF: dbUserPasswords.dbuserPassword: "$DB_USER_PASSWORD"
  
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_esignet_init_db   # calling function