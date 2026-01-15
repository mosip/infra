#!/bin/bash
# Script to initialize esignet and mockidentitysystem DBs.
## Usage: ./init_db.sh [kubeconfig]

NS=esignet
RELEASE_NAME=postgres-init

function installing_esignet_init_db () {

  echo Removing existing postgres-init release
  helm -n $NS delete $RELEASE_NAME || true

  echo Delete existing secrets to allow fresh install
  kubectl -n $NS delete secret db-common-secrets --ignore-not-found=true
  kubectl -n $NS delete secret postgres-postgresql --ignore-not-found=true

  echo Copy secrets from postgres namespace for DB initialization  
  COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh
  
  # Copy postgres-postgresql secret (postgres connection credentials)
  if kubectl -n postgres get secret postgres-postgresql &>/dev/null; then
    echo "Copying postgres-postgresql secret from postgres namespace"
    $COPY_UTIL secret postgres-postgresql postgres $NS
  else
    echo "Warning: postgres-postgresql secret not found in postgres namespace"
  fi
  
  # Copy db-common-secrets (contains database user passwords)
  if kubectl -n postgres get secret db-common-secrets &>/dev/null; then
    echo "Copying db-common-secrets secret from postgres namespace"
    $COPY_UTIL secret db-common-secrets postgres $NS
    
    # Add Helm ownership labels and annotations so Helm can adopt this secret
    echo "Adding Helm ownership metadata to db-common-secrets"
    kubectl -n $NS label secret db-common-secrets \
      app.kubernetes.io/managed-by=Helm --overwrite
    kubectl -n $NS annotate secret db-common-secrets \
      meta.helm.sh/release-name=$RELEASE_NAME \
      meta.helm.sh/release-namespace=$NS --overwrite
  else
    echo "Warning: db-common-secrets not found in postgres namespace"
    echo "The postgres-init Helm chart will create it with values from postgres-postgresql"
  fi
  
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_esignet_init_db   # calling function