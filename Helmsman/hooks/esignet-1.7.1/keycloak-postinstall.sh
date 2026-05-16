#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Keycloak Post-install (Keycloak Init)
# =============================================================================
# Based on: deploy/keycloak/keycloak-init.sh + deploy/initialise-prereq.sh
# Copies keycloak configmaps/secrets to esignet namespace and runs
# keycloak-init helm chart to create eSignet-specific clients and roles.
#
# Environment Variables:
#   INSTALLATION_DOMAIN      - Base domain (default: sandbox.xyz.net)
#   KEYCLOAK_INIT_VERSION    - keycloak-init chart version (default: 12.0.2)
#   ESIGNET_NS               - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
KEYCLOAK_NS="keycloak"
CHART_VERSION="${KEYCLOAK_INIT_VERSION:-12.0.2}"
INSTALLATION_DOMAIN="${INSTALLATION_DOMAIN:-sandbox.xyz.net}"
IAMHOST_URL="iam.${INSTALLATION_DOMAIN}"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Keycloak Post-install (Init)"
echo "================================================"

# --- Step 1: Copy keycloak configmaps and secrets to esignet namespace ---
echo "Copying keycloak configmaps and secrets to $ESIGNET_NS namespace"

$COPY_UTIL configmap keycloak-host "$KEYCLOAK_NS" "$ESIGNET_NS" 2>/dev/null || {
  echo "keycloak-host not found in $KEYCLOAK_NS - creating directly"
  kubectl -n "$ESIGNET_NS" create configmap keycloak-host \
    --from-literal=keycloak-external-url="https://$IAMHOST_URL" \
    --from-literal=keycloak-internal-url="http://keycloak.$KEYCLOAK_NS" \
    --dry-run=client -o yaml | kubectl apply -f -
}

$COPY_UTIL configmap keycloak-env-vars "$KEYCLOAK_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: keycloak-env-vars not found in $KEYCLOAK_NS"

$COPY_UTIL secret keycloak "$KEYCLOAK_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: keycloak secret not found in $KEYCLOAK_NS"

# --- Step 2: Read existing client secrets if any ---
echo "Checking for existing keycloak-client-secrets"
HELM_SET_SECRETS=()

escape_helm_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//,/\\,}"
  value="${value//=/\\=}"
  printf '%s' "$value"
}

declare -A SECRET_KEYS=(
  ["mosip_pms_client_secret"]="0"
  ["mpartner_default_auth_secret"]="1"
  ["mosip_ida_client_secret"]="2"
  ["mosip_deployment_client_secret"]="3"
  ["mpartner_default_mobile_secret"]="4"
)

if kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets &>/dev/null; then
  echo "Found existing keycloak-client-secrets. Preserving client secrets."
  for key in "${!SECRET_KEYS[@]}"; do
    idx="${SECRET_KEYS[$key]}"
    val=$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
      -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [[ -n "$val" ]]; then
      HELM_SET_SECRETS+=(
        --set-string "clientSecrets[$idx].name=$key"
        --set-string "clientSecrets[$idx].secret=$(escape_helm_value "$val")"
      )
    fi
  done
else
  echo "No existing keycloak-client-secrets found. Fresh install."
fi

# --- Step 3: Run keycloak-init helm chart ---
echo "Installing esignet-keycloak-init"
helm repo add mosip https://mosip.github.io/mosip-helm || true
helm repo update

kubectl -n "$ESIGNET_NS" delete secret --ignore-not-found=true keycloak-client-secrets
helm -n "$ESIGNET_NS" delete esignet-keycloak-init 2>/dev/null || true

helm -n "$ESIGNET_NS" install esignet-keycloak-init mosip/keycloak-init \
  ${HELM_SET_SECRETS[@]+"${HELM_SET_SECRETS[@]}"} \
  --set keycloak.realms.mosip.realm_config.attributes.frontendUrl="https://$IAMHOST_URL/auth" \
  --set keycloakInternalHost="keycloak.$KEYCLOAK_NS" \
  --set keycloakExternalHost="$IAMHOST_URL" \
  --version "$CHART_VERSION" --wait --wait-for-jobs

# --- Step 4: Sync updated client secrets back to keycloak namespace ---
echo "Syncing keycloak-client-secrets back to $KEYCLOAK_NS namespace"
if kubectl -n "$ESIGNET_NS" get secret keycloak-client-secrets &>/dev/null; then
  $COPY_UTIL secret keycloak-client-secrets "$ESIGNET_NS" "$KEYCLOAK_NS"
  echo "keycloak-client-secrets synced to $KEYCLOAK_NS namespace."
fi

echo "Keycloak post-install (init) completed."
