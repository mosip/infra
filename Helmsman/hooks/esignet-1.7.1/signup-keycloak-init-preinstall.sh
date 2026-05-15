#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Signup Keycloak Init Pre-install
# =============================================================================
# Based on: esignet-signup/deploy/keycloak/keycloak-init.sh
# Copies keycloak configmaps/secrets to signup namespace and ensures
# keycloak-client-secrets contains mosip_signup_client_secret before
# the keycloak-init helm chart runs.
#
# On first deploy: generates a UUID secret if none exists in keycloak ns.
# On re-deploy:    propagates the existing secret from keycloak namespace.
#
# Environment Variables:
#   SIGNUP_NS - Signup namespace (default: signup)
# =============================================================================
set -euo pipefail

SIGNUP_NS="${SIGNUP_NS:-signup}"
KEYCLOAK_NS="keycloak"
SECRET_KEY="mosip_signup_client_secret"

echo "================================================"
echo "eSignet 1.7.1 - Signup Keycloak Init Pre-install"
echo "================================================"

# --- Step 1: Ensure signup namespace exists with istio ---
kubectl create namespace "$SIGNUP_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$SIGNUP_NS" istio-injection=enabled --overwrite

# --- Step 2: Copy keycloak-env-vars configmap ---
echo "Copying keycloak-env-vars to $SIGNUP_NS namespace"
kubectl -n "$KEYCLOAK_NS" get configmap keycloak-env-vars -o yaml | \
  sed "s|^\(\s*namespace:\) $KEYCLOAK_NS$|\1 $SIGNUP_NS|" | \
  kubectl apply -f -

# --- Step 3: Copy keycloak secret ---
echo "Copying keycloak secret to $SIGNUP_NS namespace"
kubectl -n "$KEYCLOAK_NS" get secret keycloak -o yaml | \
  sed "s|^\(\s*namespace:\) $KEYCLOAK_NS$|\1 $SIGNUP_NS|" | \
  kubectl apply -f -

# --- Step 4: Ensure keycloak-client-secrets has mosip_signup_client_secret ---
# Source: deploy/keycloak/keycloak-init.sh - reading existing secret from keycloak ns
echo "Ensuring mosip_signup_client_secret exists in $SIGNUP_NS"
if kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets &>/dev/null && \
   kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
     -o jsonpath="{.data.$SECRET_KEY}" 2>/dev/null | grep -q '.'; then
  echo "Found existing $SECRET_KEY in keycloak namespace — propagating to $SIGNUP_NS"
  SECRET_B64=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$SECRET_KEY}")
else
  echo "No existing $SECRET_KEY found — generating new secret"
  SECRET_B64=$(python3 -c "import uuid, base64; print(base64.b64encode(str(uuid.uuid4()).encode()).decode())")
fi

kubectl -n "$SIGNUP_NS" create secret generic keycloak-client-secrets \
  --from-literal=dummy=placeholder \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$SIGNUP_NS" patch secret keycloak-client-secrets \
  --type=merge \
  -p "{\"data\":{\"$SECRET_KEY\":\"$SECRET_B64\"}}"

echo "Signup keycloak init pre-install completed."
