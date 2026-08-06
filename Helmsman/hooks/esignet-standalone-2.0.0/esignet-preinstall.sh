#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet Service Pre-install
# =============================================================================
# Based on: deploy/esignet-mock/install.sh
# Prepares esignet-mock namespace with postgres and redis configmaps/secrets
# before eSignet helm chart deployment.
#
# softhsm-esignet-mock deploys in the esignet-mock namespace (priority -14, before
# esignet-mock at -12), so esignet-softhsm-share is already present — no copy needed.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet-mock)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-go-mock}"
POSTGRES_NS="postgres"
REDIS_NS="redis"
KEYCLOAK_NS="keycloak"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - eSignet Service Pre-install"
echo "================================================"

# --- Step 1: Ensure esignet-mock namespace exists with Istio ---
echo "Setting up $ESIGNET_NS namespace"
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Update helm repos ---
helm repo add mosip https://mosip.github.io/mosip-helm || true
helm repo update

# --- Step 3: Copy configmaps from other namespaces ---
# All external services (postgres, redis) are guaranteed deployed before
# esignet-mock-dsf runs.
echo "Copying postgres-config configmap from $POSTGRES_NS"
$COPY_UTIL configmap postgres-config "$POSTGRES_NS" "$ESIGNET_NS"

# Override postgres-config with 2.0.0-specific DB values (isolated database)
kubectl -n "$ESIGNET_NS" patch configmap postgres-config --type merge \
  -p '{"data":{"database-name":"mosip_esignet_go","database-username":"esignetuser_go"}}'

echo "Copying redis-config configmap from $REDIS_NS"
$COPY_UTIL configmap redis-config "$REDIS_NS" "$ESIGNET_NS"

# --- Step 4: Copy secrets from other namespaces ---
echo "Copying postgres-postgresql secret from $POSTGRES_NS"
$COPY_UTIL secret postgres-postgresql "$POSTGRES_NS" "$ESIGNET_NS"

echo "Copying redis secret from $REDIS_NS"
$COPY_UTIL secret redis "$REDIS_NS" "$ESIGNET_NS"

# db-common-secrets is normally fanned out by esignet-db-postinstall.sh (part of the
# shared external-dsf.yaml postgres-init-esignet release), but that hook's namespace
# loop only covers the original esignet-standalone namespaces. Copy it directly here
# so the 2.0.0 namespace is self-sufficient without touching the shared hook.
echo "Copying db-common-secrets secret from $POSTGRES_NS"
$COPY_UTIL secret db-common-secrets "$POSTGRES_NS" "$ESIGNET_NS"

# keycloak-host/keycloak-env-vars/keycloak/keycloak-client-secrets are normally fanned
# out by esignet-postinstall-keycloak-init.sh (postInstall hook of the shared
# external-dsf.yaml esignet-keycloak-init release), but that hook's namespace loop only
# covers the original esignet-standalone namespaces. Copy them directly here so the
# 2.0.0 namespace is self-sufficient without touching the shared hook. This runs for
# every instance that delegates to this script (esignet-go-mock plus the
# mosipid1/mosipid2/sunbird wrappers), matching the original profile's fan-out to all
# four namespaces.
echo "Copying keycloak-host configmap from $KEYCLOAK_NS"
$COPY_UTIL configmap keycloak-host "$KEYCLOAK_NS" "$ESIGNET_NS"

echo "Copying keycloak-env-vars configmap from $KEYCLOAK_NS"
$COPY_UTIL configmap keycloak-env-vars "$KEYCLOAK_NS" "$ESIGNET_NS"

echo "Copying keycloak secret from $KEYCLOAK_NS"
$COPY_UTIL secret keycloak "$KEYCLOAK_NS" "$ESIGNET_NS"

echo "Copying keycloak-client-secrets secret from $KEYCLOAK_NS"
$COPY_UTIL secret keycloak-client-secrets "$KEYCLOAK_NS" "$ESIGNET_NS"

# --- Step 5: Shared eSignet P12 password + crypto encryption key ---
ESIGNET_P12_PASSWORD_VAL="${ESIGNET_P12_PASSWORD:?ERROR: ESIGNET_P12_PASSWORD must be set}"
ESIGNET_CRYPTO_KEY_VAL="${ESIGNET_CRYPTO_ENCRYPTION_KEY:?ERROR: ESIGNET_CRYPTO_ENCRYPTION_KEY must be set}"
CRYPTO_HUB_NS="captcha"

echo "Creating esignet-go-crypto secret in $CRYPTO_HUB_NS namespace"
kubectl -n "$CRYPTO_HUB_NS" create secret generic esignet-go-crypto \
  --from-literal=p12-password="$ESIGNET_P12_PASSWORD_VAL" \
  --from-literal=crypto-encryption-key="$ESIGNET_CRYPTO_KEY_VAL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Copying esignet-go-crypto secret from $CRYPTO_HUB_NS to $ESIGNET_NS"
$COPY_UTIL secret esignet-go-crypto "$CRYPTO_HUB_NS" "$ESIGNET_NS"

echo "eSignet pre-install completed."
