#!/bin/bash
# Pre-install hook for esignet-keycloak-init (eSignet 1.7.1 standalone)
# Prepares esignet namespace before keycloak-init helm chart is deployed.
# Mirrors the pattern in hooks/esignet-preinstall-keycloak-init.sh (Java 11/21)
# but handles fresh installs where keycloak-client-secrets may not exist yet.
set -euo pipefail

NS="esignet"
KEYCLOAK_NS="keycloak"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Keycloak Init Pre-install"
echo "================================================"

# Clean up previous release and any kubectl-applied resources helm cannot import
kubectl -n "$NS" delete secret --ignore-not-found=true keycloak-client-secrets
kubectl -n "$NS" delete configmap --ignore-not-found=true keycloak-host
helm -n "$NS" delete esignet-keycloak-init 2>/dev/null || true

echo "Copying keycloak configmaps and secrets to $NS namespace"
$COPY_UTIL configmap keycloak-env-vars "$KEYCLOAK_NS" "$NS"
$COPY_UTIL secret keycloak "$KEYCLOAK_NS" "$NS"

# Fetch existing client secrets from keycloak namespace (empty on fresh install — helm chart generates them)
PMS_CLIENT_SECRET_KEY="mosip_pms_client_secret"
MPARTNER_DEFAULT_AUTH_SECRET_KEY="mpartner_default_auth_secret"
IDA_CLIENT_SECRET_KEY="mosip_ida_client_secret"
DEPLOYMENT_CLIENT_SECRET_KEY="mosip_deployment_client_secret"
MPARTNER_DEFAULT_MOBILE_SECRET_KEY="mpartner_default_mobile_secret"

PMS_CLIENT_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${PMS_CLIENT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export PMS_CLIENT_SECRET_KEY
export PMS_CLIENT_SECRET_VALUE

MPARTNER_DEFAULT_AUTH_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${MPARTNER_DEFAULT_AUTH_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export MPARTNER_DEFAULT_AUTH_SECRET_KEY
export MPARTNER_DEFAULT_AUTH_SECRET_VALUE

IDA_CLIENT_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${IDA_CLIENT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export IDA_CLIENT_SECRET_KEY
export IDA_CLIENT_SECRET_VALUE

DEPLOYMENT_CLIENT_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${DEPLOYMENT_CLIENT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export DEPLOYMENT_CLIENT_SECRET_KEY
export DEPLOYMENT_CLIENT_SECRET_VALUE

MPARTNER_DEFAULT_MOBILE_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${MPARTNER_DEFAULT_MOBILE_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export MPARTNER_DEFAULT_MOBILE_SECRET_KEY
export MPARTNER_DEFAULT_MOBILE_SECRET_VALUE

echo "Pre-install setup complete. Helmsman will now deploy esignet-keycloak-init chart."
