#!/bin/bash
# Script to initialize mock identity system DB.
# This hook runs AFTER postgres-init-esignet has already set up the required secrets.
# It only cleans up the previous helm release if it exists.

NS=esignet

function installing_mockidentitysystem_init_db () {
  echo "Removing existing postgres-init-mockidentitysystem release if exists"
  helm -n $NS delete postgres-init-mockidentitysystem || true
  
  echo "Verifying required secrets exist (should be created by postgres-init-esignet)"
  if kubectl -n $NS get secret postgres-postgresql &>/dev/null; then
    echo "✓ postgres-postgresql secret found"
  else
    echo "Warning: postgres-postgresql secret not found"
  fi
  
  if kubectl -n $NS get secret db-common-secrets &>/dev/null; then
    echo "✓ db-common-secrets secret found"
  else
    echo "Warning: db-common-secrets secret not found"
  fi
  
  return 0
}

# set commands for error handling.
set -e
set -o errexit
set -o nounset
set -o errtrace
set -o pipefail
installing_mockidentitysystem_init_db
