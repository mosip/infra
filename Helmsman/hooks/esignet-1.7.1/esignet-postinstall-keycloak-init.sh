#!/bin/bash
# Post-install hook for esignet-keycloak-init (eSignet 1.7.1 standalone)
# Syncs keycloak-client-secrets from esignet namespace back to keycloak namespace.
# Mirrors hooks/esignet-postinstall-keycloak-init.sh but skips config-server sync
# since config-server is not deployed in the eSignet standalone profile.
set -euo pipefail

NS="esignet"
KEYCLOAK_NS="keycloak"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
PMS_CLIENT_SECRET_KEY="mosip_pms_client_secret"
MPARTNER_DEFAULT_AUTH_SECRET_KEY="mpartner_default_auth_secret"
IDA_CLIENT_SECRET_KEY="mosip_ida_client_secret"
DEPLOYMENT_CLIENT_SECRET_KEY="mosip_deployment_client_secret"
MPARTNER_DEFAULT_MOBILE_SECRET_KEY="mpartner_default_mobile_secret"

echo "================================================"
echo "eSignet 1.7.1 - Keycloak Init Post-install"
echo "================================================"

echo "Checking keycloak-client-secrets in $KEYCLOAK_NS namespace"
KEYCLOAK_PMS_SECRET=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" 2>/dev/null || echo "")
KEYCLOAK_MPARTNER_SECRET=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" 2>/dev/null || echo "")
KEYCLOAK_IDA_SECRET=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.$IDA_CLIENT_SECRET_KEY}" 2>/dev/null || echo "")
KEYCLOAK_DEPLOYMENT_SECRET=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.$DEPLOYMENT_CLIENT_SECRET_KEY}" 2>/dev/null || echo "")
KEYCLOAK_MOBILE_SECRET=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.$MPARTNER_DEFAULT_MOBILE_SECRET_KEY}" 2>/dev/null || echo "")

if [ -z "$KEYCLOAK_PMS_SECRET" ] || [ -z "$KEYCLOAK_MPARTNER_SECRET" ] || \
   [ -z "$KEYCLOAK_IDA_SECRET" ] || [ -z "$KEYCLOAK_DEPLOYMENT_SECRET" ] || \
   [ -z "$KEYCLOAK_MOBILE_SECRET" ]; then
  echo "Syncing keycloak-client-secrets from $NS to $KEYCLOAK_NS namespace"

  if ! kubectl -n "$NS" get secret keycloak-client-secrets &>/dev/null; then
    echo "ERROR: keycloak-client-secrets not found in $NS namespace" >&2
    exit 1
  fi

  JQ_FILTER="."
  ESIGNET_PMS_SECRET=$(kubectl -n "$NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$PMS_CLIENT_SECRET_KEY}" 2>/dev/null || echo "")
  ESIGNET_MPARTNER_SECRET=$(kubectl -n "$NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$MPARTNER_DEFAULT_AUTH_SECRET_KEY}" 2>/dev/null || echo "")
  ESIGNET_IDA_SECRET=$(kubectl -n "$NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$IDA_CLIENT_SECRET_KEY}" 2>/dev/null || echo "")
  ESIGNET_DEPLOYMENT_SECRET=$(kubectl -n "$NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$DEPLOYMENT_CLIENT_SECRET_KEY}" 2>/dev/null || echo "")
  ESIGNET_MOBILE_SECRET=$(kubectl -n "$NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$MPARTNER_DEFAULT_MOBILE_SECRET_KEY}" 2>/dev/null || echo "")

  [ -n "$ESIGNET_PMS_SECRET" ] && \
    JQ_FILTER="$JQ_FILTER | .data[\"$PMS_CLIENT_SECRET_KEY\"]=\"$ESIGNET_PMS_SECRET\""
  [ -n "$ESIGNET_MPARTNER_SECRET" ] && \
    JQ_FILTER="$JQ_FILTER | .data[\"$MPARTNER_DEFAULT_AUTH_SECRET_KEY\"]=\"$ESIGNET_MPARTNER_SECRET\""
  [ -n "$ESIGNET_IDA_SECRET" ] && \
    JQ_FILTER="$JQ_FILTER | .data[\"$IDA_CLIENT_SECRET_KEY\"]=\"$ESIGNET_IDA_SECRET\""
  [ -n "$ESIGNET_DEPLOYMENT_SECRET" ] && \
    JQ_FILTER="$JQ_FILTER | .data[\"$DEPLOYMENT_CLIENT_SECRET_KEY\"]=\"$ESIGNET_DEPLOYMENT_SECRET\""
  [ -n "$ESIGNET_MOBILE_SECRET" ] && \
    JQ_FILTER="$JQ_FILTER | .data[\"$MPARTNER_DEFAULT_MOBILE_SECRET_KEY\"]=\"$ESIGNET_MOBILE_SECRET\""

  if kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets &>/dev/null; then
    kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets -o json | \
      jq "$JQ_FILTER" | kubectl apply -f -
  else
    echo "keycloak-client-secrets not found in $KEYCLOAK_NS, copying from $NS"
    $COPY_UTIL secret keycloak-client-secrets "$NS" "$KEYCLOAK_NS"
  fi
  echo "keycloak-client-secrets synced to $KEYCLOAK_NS namespace."
else
  echo "Secrets already exist in $KEYCLOAK_NS namespace, skipping sync."
fi

echo "Post-install setup complete."
