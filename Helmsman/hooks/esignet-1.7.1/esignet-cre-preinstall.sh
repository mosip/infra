#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet CRE Service Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-cre, runs base esignet preinstall (copies
# postgres + redis config/secrets), then creates esignet-captcha-cre secret
# in the captcha namespace from workflow env vars, copies it to esignet-cre,
# and patches the captcha deployment with the CRE secret key.
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-cre"
CAPTCHA_NS="captcha"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CAPTCHA_SITE_KEY="${ESIGNET_CRE_CAPTCHA_SITE_KEY:?ERROR: ESIGNET_CRE_CAPTCHA_SITE_KEY must be set}"
CAPTCHA_SECRET_KEY="${ESIGNET_CRE_CAPTCHA_SECRET_KEY:?ERROR: ESIGNET_CRE_CAPTCHA_SECRET_KEY must be set}"
CRE_POSTGRES_PASS="${CRE_POSTGRES_PASSWORD:?ERROR: CRE_POSTGRES_PASSWORD must be set}"
CRE_KC_ADMIN_PASS="${CRE_KEYCLOAK_ADMIN_PASSWORD:?ERROR: CRE_KEYCLOAK_ADMIN_PASSWORD must be set}"

"$WORKDIR/hooks/esignet-1.7.1/esignet-preinstall.sh"

# Create CRE-specific esignet-domain-config — same domain_name, but esignet/signup hosts differ
kubectl -n "$ESIGNET_NS" create configmap esignet-domain-config \
  --from-literal=installation-domain="${domain_name}" \
  --from-literal=mosip-api-host="api.${domain_name}" \
  --from-literal=mosip-api-internal-host="api-internal.${domain_name}" \
  --from-literal=mosip-esignet-host="esignet-mosipid-cre.${domain_name}" \
  --from-literal=mosip-iam-external-host="iam.${domain_name}" \
  --from-literal=mosip-kafka-host="kafka.${domain_name}" \
  --from-literal=mosip-postgres-host="postgres.${domain_name}" \
  --from-literal=mosip-signup-host="signup-mosipid-cre.${domain_name}" \
  --from-literal=mosip-smtp-host="smtp.${domain_name}" \
  --from-literal=mosip-version="develop" \
  --dry-run=client -o yaml | kubectl apply -f -

# Override postgres-config with CRE-specific DB values
kubectl -n "$ESIGNET_NS" patch configmap postgres-config --type merge \
  -p '{"data":{"database-name":"mosip_esignet_cre","database-username":"esignetuser_cre"}}'

# Create esignet-misp-onboarder-key placeholder — real value written by MISP onboarder.
if ! kubectl -n "$ESIGNET_NS" get secret esignet-misp-onboarder-key &>/dev/null; then
  kubectl -n "$ESIGNET_NS" create secret generic esignet-misp-onboarder-key \
    --from-literal=mosip-esignet-misp-key=""
  echo "esignet-misp-onboarder-key placeholder created in $ESIGNET_NS"
fi

echo "Creating esignet-captcha-cre secret in $CAPTCHA_NS namespace"
kubectl -n "$CAPTCHA_NS" create secret generic esignet-captcha-cre \
  --from-literal=esignet-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=esignet-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Copying esignet-captcha-cre secret from $CAPTCHA_NS to $ESIGNET_NS"
$COPY_UTIL secret esignet-captcha-cre "$CAPTCHA_NS" "$ESIGNET_NS"

echo "Patching captcha deployment with ESIGNETCRE secret key"
ENV_VAR_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
  -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETCRE')].name}" 2>/dev/null || echo "")
if [[ -z "$ENV_VAR_EXISTS" ]]; then
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETCRE", "valueFrom": {"secretKeyRef": {"name": "esignet-captcha-cre", "key": "esignet-captcha-secret-key"}}}}]'
else
  echo "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETCRE already exists."
fi

# --- postgres-postgresql-cre secret (CRE remote postgres password) ---
echo "Creating postgres-postgresql-cre secret in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create secret generic postgres-postgresql-cre \
  --from-literal=postgres-password="${CRE_POSTGRES_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- keycloak-host-cre CM (external URL points to CRE Keycloak) ---
echo "Creating keycloak-host-cre configmap in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create configmap keycloak-host-cre \
  --from-literal=keycloak-external-host="iam.${cre_domain_name}" \
  --from-literal=keycloak-external-url="https://iam.${cre_domain_name}" \
  --from-literal=keycloak-internal-host="keycloak.keycloak" \
  --from-literal=keycloak-internal-service-url="http://keycloak.keycloak/auth/" \
  --from-literal=keycloak-internal-url="http://keycloak.keycloak" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- keycloak-client-secrets-cre: fetch all confidential clients from CRE Keycloak ---
KC_HOST="iam.${cre_domain_name}"
REALM="mosip"

echo "Fetching admin token from $KC_HOST"
TOKEN_RESPONSE=$(curl -sf -X POST \
  "https://${KC_HOST}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=${CRE_KC_ADMIN_PASS}")
ADMIN_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
if [[ -z "$ADMIN_TOKEN" || "$ADMIN_TOKEN" == "null" ]]; then
  echo "❌ Failed to get admin token from $KC_HOST" >&2; exit 1
fi
echo "✓ Admin token obtained"

echo "Fetching all clients from realm $REALM on $KC_HOST"
CLIENTS=$(curl -sf \
  "https://${KC_HOST}/auth/admin/realms/${REALM}/clients?max=500" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

SECRET_ARGS=()
while IFS= read -r client_json; do
  client_id=$(echo "$client_json" | jq -r '.clientId')
  uuid=$(echo "$client_json"      | jq -r '.id')
  auth_type=$(echo "$client_json" | jq -r '.clientAuthenticatorType')
  is_public=$(echo "$client_json" | jq -r '.publicClient')
  [[ "$auth_type" != "client-secret" || "$is_public" == "true" ]] && continue
  secret_val=$(curl -sf \
    "https://${KC_HOST}/auth/admin/realms/${REALM}/clients/${uuid}/client-secret" \
    -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.value // empty')
  [[ -z "$secret_val" || "$secret_val" == "null" ]] && continue
  key=$(echo "$client_id" | tr '-' '_')_secret
  SECRET_ARGS+=("--from-literal=${key}=${secret_val}")
  echo "  ✓ $client_id"
done < <(echo "$CLIENTS" | jq -c '.[]')

if [[ ${#SECRET_ARGS[@]} -eq 0 ]]; then
  echo "❌ No client secrets fetched from CRE Keycloak" >&2; exit 1
fi
echo "Creating keycloak-client-secrets-cre in $ESIGNET_NS (${#SECRET_ARGS[@]} clients)"
kubectl -n "$ESIGNET_NS" create secret generic keycloak-client-secrets-cre \
  "${SECRET_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ keycloak-client-secrets-cre created"

echo "eSignet CRE pre-install completed."
