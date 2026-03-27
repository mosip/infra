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

echo "================================================"
echo "eSignet 1.7.1 - Keycloak Post-install (Init)"
echo "================================================"

# --- Step 1: Copy keycloak configmaps and secrets to esignet namespace ---
# Source: deploy/keycloak/keycloak-init.sh - copy_cm_func.sh calls
echo "Copying keycloak configmaps and secrets to $ESIGNET_NS namespace"

# Copy keycloak-host configmap
if kubectl -n "$KEYCLOAK_NS" get configmap keycloak-host &>/dev/null; then
  kubectl -n "$KEYCLOAK_NS" get configmap keycloak-host -o yaml | \
    sed "s/namespace: $KEYCLOAK_NS/namespace: $ESIGNET_NS/g" | \
    kubectl apply -f -
  echo "keycloak-host configmap copied."
else
  # Create keycloak-host configmap if keycloak didn't create it
  echo "Creating keycloak-host configmap"
  kubectl -n "$ESIGNET_NS" create configmap keycloak-host \
    --from-literal=keycloak-external-url="https://$IAMHOST_URL" \
    --from-literal=keycloak-internal-url="http://keycloak.$KEYCLOAK_NS" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

# Copy keycloak-env-vars configmap
if kubectl -n "$KEYCLOAK_NS" get configmap keycloak-env-vars &>/dev/null; then
  kubectl -n "$KEYCLOAK_NS" get configmap keycloak-env-vars -o yaml | \
    sed "s/namespace: $KEYCLOAK_NS/namespace: $ESIGNET_NS/g" | \
    kubectl apply -f -
  echo "keycloak-env-vars configmap copied."
fi

# Copy keycloak secret
if kubectl -n "$KEYCLOAK_NS" get secret keycloak &>/dev/null; then
  kubectl -n "$KEYCLOAK_NS" get secret keycloak -o yaml | \
    sed "s/namespace: $KEYCLOAK_NS/namespace: $ESIGNET_NS/g" | \
    kubectl apply -f -
  echo "keycloak secret copied."
fi

# --- Step 2: Read existing client secrets if any ---
# Source: deploy/keycloak/keycloak-init.sh - reading existing secrets
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
# Source: deploy/keycloak/keycloak-init.sh - helm install keycloak-init
echo "Installing esignet-keycloak-init"
helm repo add mosip https://mosip.github.io/mosip-helm || true
helm repo update

kubectl -n "$ESIGNET_NS" delete secret --ignore-not-found=true keycloak-client-secrets
helm -n "$ESIGNET_NS" delete esignet-keycloak-init 2>/dev/null || true

helm -n "$ESIGNET_NS" install esignet-keycloak-init mosip/keycloak-init \
  "${HELM_SET_SECRETS[@]}" \
  --set keycloak.realms.mosip.realm_config.attributes.frontendUrl="https://$IAMHOST_URL/auth" \
  --set keycloakInternalHost="keycloak.$KEYCLOAK_NS" \
  --set keycloakExternalHost="$IAMHOST_URL" \
  --version "$CHART_VERSION" --wait --wait-for-jobs

# --- Step 4: Sync updated client secrets back to keycloak namespace ---
# Source: deploy/keycloak/keycloak-init.sh - secret sync back
echo "Syncing keycloak-client-secrets back to $KEYCLOAK_NS namespace"
if kubectl -n "$ESIGNET_NS" get secret keycloak-client-secrets &>/dev/null; then
  if kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets &>/dev/null; then
    # Update existing secret in keycloak namespace
    for key in "${!SECRET_KEYS[@]}"; do
      val=$(kubectl -n "$ESIGNET_NS" get secret keycloak-client-secrets \
        -o jsonpath="{.data.$key}" 2>/dev/null || echo "")
      if [[ -n "$val" ]]; then
        kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets -o json | \
          jq ".data[\"$key\"]=\"$val\"" | \
          kubectl apply -f -
      fi
    done
  else
    # Copy entire secret to keycloak namespace
    kubectl -n "$ESIGNET_NS" get secret keycloak-client-secrets -o yaml | \
      sed "s/namespace: $ESIGNET_NS/namespace: $KEYCLOAK_NS/g" | \
      kubectl apply -f -
  fi
  echo "keycloak-client-secrets synced to $KEYCLOAK_NS namespace."
fi

echo "Keycloak post-install (init) completed."
