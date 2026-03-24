#!/bin/bash
# Post-install hook for esignet keycloak-init
# This script syncs the newly created keycloak-client-secrets to other namespaces
# and updates config-server with the required environment variables
# This script is IDEMPOTENT - it will not overwrite existing secrets
## Usage: ./esignet-postinstall-keycloak-init.sh [kubeconfig]

# Strict error handling
set -e
set -o errexit   ## exit the script if any statement returns a non-true return value
set -o nounset   ## exit the script if you try to use an uninitialised variable
set -o pipefail  ## trace ERR through pipes
set -o errtrace  # trace ERR through functions

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
PMS_CLIENT_SECRET_KEY='mosip_pms_client_secret'
MPARTNER_DEFAULT_AUTH_SECRET_KEY='mpartner_default_auth_secret'

echo "Checking keycloak-client-secrets in keycloak namespace"
KEYCLOAK_PMS_SECRET=$( kubectl -n keycloak get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" 2>/dev/null || echo "" )
KEYCLOAK_MPARTNER_SECRET=$( kubectl -n keycloak get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" 2>/dev/null || echo "" )

# Only sync to keycloak namespace if secrets don't exist there
if [ -z "$KEYCLOAK_PMS_SECRET" ] || [ -z "$KEYCLOAK_MPARTNER_SECRET" ]; then
  echo "Secrets missing in keycloak namespace, syncing from $NS namespace"
  
  # Validate source secrets exist
  if ! kubectl -n $NS get secrets keycloak-client-secrets &>/dev/null; then
    echo "ERROR: Source secret keycloak-client-secrets not found in $NS namespace"
    exit 1
  fi
  
  # Fetch secrets from esignet namespace
  ESIGNET_PMS_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" || echo "" )
  ESIGNET_MPARTNER_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" || echo "" )
  
  # Build jq filter to only update non-empty secrets
  JQ_FILTER="."
  SECRETS_TO_SYNC=0
  
  if [ -n "$ESIGNET_PMS_SECRET" ]; then
    JQ_FILTER="$JQ_FILTER | .data[\"$PMS_CLIENT_SECRET_KEY\"]=\"$ESIGNET_PMS_SECRET\""
    echo "Will sync PMS client secret to keycloak namespace"
    SECRETS_TO_SYNC=$((SECRETS_TO_SYNC + 1))
  else
    echo "WARNING: PMS client secret is empty in $NS namespace, skipping"
  fi
  
  if [ -n "$ESIGNET_MPARTNER_SECRET" ]; then
    JQ_FILTER="$JQ_FILTER | .data[\"$MPARTNER_DEFAULT_AUTH_SECRET_KEY\"]=\"$ESIGNET_MPARTNER_SECRET\""
    echo "Will sync MPARTNER default auth secret to keycloak namespace"
    SECRETS_TO_SYNC=$((SECRETS_TO_SYNC + 1))
  else
    echo "WARNING: MPARTNER default auth secret is empty in $NS namespace, skipping"
  fi
  
  # Only apply if we have at least one secret to sync
  if [ "$SECRETS_TO_SYNC" -eq 0 ]; then
    echo "ERROR: No valid secrets found in $NS namespace to sync"
    exit 1
  fi
  
  # Use intermediate variable to check pipeline success
  UPDATED_SECRET=$(kubectl -n keycloak get secret keycloak-client-secrets -o json | \
    jq "$JQ_FILTER") || {
    echo "ERROR: Failed to update keycloak-client-secrets in keycloak namespace"
    exit 1
  }
  
  echo "$UPDATED_SECRET" | kubectl apply -f - || {
    echo "ERROR: Failed to apply updated secret to keycloak namespace"
    exit 1
  }
  
  echo "Successfully synced $SECRETS_TO_SYNC secret(s) to keycloak namespace"
else
  echo "Secrets already exist in keycloak namespace, skipping sync"
fi

echo "Checking keycloak-client-secrets in config-server namespace"
CONFIG_PMS_SECRET=$( kubectl -n config-server get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" 2>/dev/null || echo "" )
CONFIG_MPARTNER_SECRET=$( kubectl -n config-server get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" 2>/dev/null || echo "" )

# Only sync to config-server namespace if secrets don't exist there
if [ -z "$CONFIG_PMS_SECRET" ] || [ -z "$CONFIG_MPARTNER_SECRET" ]; then
  echo "Secrets missing in config-server namespace, syncing from $NS namespace"
  
  # Validate source secrets exist
  if ! kubectl -n $NS get secrets keycloak-client-secrets &>/dev/null; then
    echo "ERROR: Source secret keycloak-client-secrets not found in $NS namespace"
    exit 1
  fi
  
  # Fetch secrets from esignet namespace
  ESIGNET_PMS_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" || echo "" )
  ESIGNET_MPARTNER_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" || echo "" )
  
  # Build jq filter to only update non-empty secrets
  JQ_FILTER="."
  SECRETS_TO_SYNC=0
  
  if [ -n "$ESIGNET_PMS_SECRET" ]; then
    JQ_FILTER="$JQ_FILTER | .data[\"$PMS_CLIENT_SECRET_KEY\"]=\"$ESIGNET_PMS_SECRET\""
    echo "Will sync PMS client secret to config-server namespace"
    SECRETS_TO_SYNC=$((SECRETS_TO_SYNC + 1))
  else
    echo "WARNING: PMS client secret is empty in $NS namespace, skipping"
  fi
  
  if [ -n "$ESIGNET_MPARTNER_SECRET" ]; then
    JQ_FILTER="$JQ_FILTER | .data[\"$MPARTNER_DEFAULT_AUTH_SECRET_KEY\"]=\"$ESIGNET_MPARTNER_SECRET\""
    echo "Will sync MPARTNER default auth secret to config-server namespace"
    SECRETS_TO_SYNC=$((SECRETS_TO_SYNC + 1))
  else
    echo "WARNING: MPARTNER default auth secret is empty in $NS namespace, skipping"
  fi
  
  # Only apply if we have at least one secret to sync
  if [ "$SECRETS_TO_SYNC" -eq 0 ]; then
    echo "ERROR: No valid secrets found in $NS namespace to sync"
    exit 1
  fi
  
  # Use intermediate variable to check pipeline success
  UPDATED_SECRET=$(kubectl -n config-server get secret keycloak-client-secrets -o json | \
    jq "$JQ_FILTER") || {
    echo "ERROR: Failed to update keycloak-client-secrets in config-server namespace"
    exit 1
  }
  
  echo "$UPDATED_SECRET" | kubectl apply -f - || {
    echo "ERROR: Failed to apply updated secret to config-server namespace"
    exit 1
  }
  
  echo "Successfully synced $SECRETS_TO_SYNC secret(s) to config-server namespace"
else
  echo "Secrets already exist in config-server namespace, skipping sync"
fi

echo "Checking and updating config-server deployment environment variables"

# Check and set ESIGNET host
ESIGNET_HOST_PLACEHOLDER=$( kubectl -n config-server get deployment -o json | jq -c '.items[].spec.template.spec.containers[].env[]| select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_HOST")|.name' )
if [ -z "$ESIGNET_HOST_PLACEHOLDER" ]; then
  echo "Adding ESIGNET host to config-server"
  kubectl -n config-server set env --keys=mosip-esignet-host --from configmap/global deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
else
  echo "ESIGNET host already exists in config-server, skipping"
fi

# Check and set PMS client secret
PMS_CLIENT_SECRET_PLACEHOLDER=$( kubectl -n config-server get deployment -o json | jq -c '.items[].spec.template.spec.containers[].env[]| select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_PMS_CLIENT_SECRET")|.name' )
if [ -z "$PMS_CLIENT_SECRET_PLACEHOLDER" ]; then
  echo "Adding PMS client secret to config-server"
  kubectl -n config-server set env --keys=$PMS_CLIENT_SECRET_KEY --from secret/keycloak-client-secrets deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
else
  echo "PMS client secret already exists in config-server, skipping"
fi

# Check and set mpartner default auth secret
MPARTNER_DEFAULT_AUTH_SECRET_PLACEHOLDER=$( kubectl -n config-server get deployment -o json | jq -c '.items[].spec.template.spec.containers[].env[]| select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MPARTNER_DEFAULT_AUTH_SECRET")|.name' )
if [ -z "$MPARTNER_DEFAULT_AUTH_SECRET_PLACEHOLDER" ]; then
  echo "Adding mpartner default auth secret to config-server"
  kubectl -n config-server set env --keys=$MPARTNER_DEFAULT_AUTH_SECRET_KEY --from secret/keycloak-client-secrets deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
else
  echo "Mpartner default auth secret already exists in config-server, skipping"
fi

echo "Post-install setup complete."
