#!/bin/sh
# Post-install hook for esignet keycloak-init
# This script syncs the newly created keycloak-client-secrets to other namespaces
# and updates config-server with the required environment variables
# This script is IDEMPOTENT - it will not overwrite existing secrets
## Usage: ./esignet-postinstall-keycloak-init.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
PMS_CLIENT_SECRET_KEY='mosip_pms_client_secret'
MPARTNER_DEFAULT_AUTH_SECRET_KEY='mpartner_default_auth_secret'

echo "Checking keycloak-client-secrets in keycloak namespace"
KEYCLOAK_PMS_SECRET=$( kubectl -n keycloak get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" 2>/dev/null )
KEYCLOAK_MPARTNER_SECRET=$( kubectl -n keycloak get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" 2>/dev/null )

# Only sync to keycloak namespace if secrets don't exist there
if [ -z "$KEYCLOAK_PMS_SECRET" ] || [ -z "$KEYCLOAK_MPARTNER_SECRET" ]; then
  echo "Secrets missing in keycloak namespace, syncing from $NS namespace"
  ESIGNET_PMS_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" )
  ESIGNET_MPARTNER_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" )
  
  kubectl -n keycloak get secret keycloak-client-secrets -o json | \
    jq ".data[\"$PMS_CLIENT_SECRET_KEY\"]=\"$ESIGNET_PMS_SECRET\"" | \
    jq ".data[\"$MPARTNER_DEFAULT_AUTH_SECRET_KEY\"]=\"$ESIGNET_MPARTNER_SECRET\"" | \
    kubectl apply -f -
else
  echo "Secrets already exist in keycloak namespace, skipping sync"
fi

echo "Checking keycloak-client-secrets in config-server namespace"
CONFIG_PMS_SECRET=$( kubectl -n config-server get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" 2>/dev/null )
CONFIG_MPARTNER_SECRET=$( kubectl -n config-server get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" 2>/dev/null )

# Only sync to config-server namespace if secrets don't exist there
if [ -z "$CONFIG_PMS_SECRET" ] || [ -z "$CONFIG_MPARTNER_SECRET" ]; then
  echo "Secrets missing in config-server namespace, syncing from $NS namespace"
  ESIGNET_PMS_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" )
  ESIGNET_MPARTNER_SECRET=$( kubectl -n $NS get secrets keycloak-client-secrets -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" )
  
  kubectl -n config-server get secret keycloak-client-secrets -o json | \
    jq ".data[\"$PMS_CLIENT_SECRET_KEY\"]=\"$ESIGNET_PMS_SECRET\"" | \
    jq ".data[\"$MPARTNER_DEFAULT_AUTH_SECRET_KEY\"]=\"$ESIGNET_MPARTNER_SECRET\"" | \
    kubectl apply -f -
else
  echo "Secrets already exist in config-server namespace, skipping sync"
fi

echo "Checking and updating config-server deployment environment variables"

# Check and set ESIGNET host
ESIGNET_HOST_PLACEHOLDER=$( kubectl -n config-server get deployment -o json | jq -c '.items[].spec.template.spec.containers[].env[]| select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_HOST")|.name' )
if [ -z "$ESIGNET_HOST_PLACEHOLDER" ]; then
  echo "Adding ESIGNET host to config-server"
  kubectl -n config-server set env --keys=mosip-esignet-host --from configmap/global deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  echo "Waiting for config-server to be Up and running"
  kubectl -n config-server rollout status deploy/config-server
else
  echo "ESIGNET host already exists in config-server, skipping"
fi

# Check and set PMS client secret
PMS_CLIENT_SECRET_PLACEHOLDER=$( kubectl -n config-server get deployment -o json | jq -c '.items[].spec.template.spec.containers[].env[]| select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_PMS_CLIENT_SECRET")|.name' )
if [ -z "$PMS_CLIENT_SECRET_PLACEHOLDER" ]; then
  echo "Adding PMS client secret to config-server"
  kubectl -n config-server set env --keys=$PMS_CLIENT_SECRET_KEY --from secret/keycloak-client-secrets deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  echo "Waiting for config-server to be Up and running"
  kubectl -n config-server rollout status deploy/config-server
else
  echo "PMS client secret already exists in config-server, skipping"
fi

# Check and set mpartner default auth secret
MPARTNER_DEFAULT_AUTH_SECRET_PLACEHOLDER=$( kubectl -n config-server get deployment -o json | jq -c '.items[].spec.template.spec.containers[].env[]| select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MPARTNER_DEFAULT_AUTH_SECRET")|.name' )
if [ -z "$MPARTNER_DEFAULT_AUTH_SECRET_PLACEHOLDER" ]; then
  echo "Adding mpartner default auth secret to config-server"
  kubectl -n config-server set env --keys=$MPARTNER_DEFAULT_AUTH_SECRET_KEY --from secret/keycloak-client-secrets deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  echo "Waiting for config-server to be Up and running"
  kubectl -n config-server rollout status deploy/config-server
else
  echo "Mpartner default auth secret already exists in config-server, skipping"
fi

echo "Post-install setup complete."
