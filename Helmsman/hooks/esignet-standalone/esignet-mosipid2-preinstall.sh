#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MOSIPID2 Service Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid2, runs base esignet preinstall (copies
# postgres + redis config/secrets), then creates esignet-captcha-mosipid2 secret
# in the captcha namespace from workflow env vars, copies it to esignet-mosipid2,
# and patches the captcha deployment with the MOSIPID2 secret key.
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-mosipid2"
CAPTCHA_NS="captcha"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CAPTCHA_SITE_KEY="${ESIGNET_MOSIPID2_CAPTCHA_SITE_KEY:?ERROR: ESIGNET_MOSIPID2_CAPTCHA_SITE_KEY must be set}"
CAPTCHA_SECRET_KEY="${ESIGNET_MOSIPID2_CAPTCHA_SECRET_KEY:?ERROR: ESIGNET_MOSIPID2_CAPTCHA_SECRET_KEY must be set}"
MOSIPID2_POSTGRES_PASS="${MOSIPID2_POSTGRES_PASSWORD:?ERROR: MOSIPID2_POSTGRES_PASSWORD must be set}"
MOSIPID2_KC_ADMIN_PASS="${MOSIPID2_KEYCLOAK_ADMIN_PASSWORD:?ERROR: MOSIPID2_KEYCLOAK_ADMIN_PASSWORD must be set}"

"$WORKDIR/hooks/esignet-standalone/esignet-preinstall.sh"

# Create MOSIPID2-specific esignet-global — same domain_name, but esignet/signup hosts differ
kubectl -n "$ESIGNET_NS" create configmap esignet-global \
  --from-literal=installation-domain="${domain_name}" \
  --from-literal=mosip-api-host="api.${domain_name}" \
  --from-literal=mosip-api-internal-host="api-internal.${domain_name}" \
  --from-literal=mosip-esignet-host="esignet-mosipid2.${domain_name}" \
  --from-literal=mosip-iam-external-host="iam.${domain_name}" \
  --from-literal=mosip-kafka-host="kafka.${domain_name}" \
  --from-literal=mosip-postgres-host="postgres.${domain_name}" \
  --from-literal=mosip-signup-host="signup-mosipid2.${domain_name}" \
  --from-literal=mosip-smtp-host="smtp.${domain_name}" \
  --from-literal=mosip-version="develop" \
  --dry-run=client -o yaml | kubectl apply -f -

# Override postgres-config with MOSIPID2-specific DB values
kubectl -n "$ESIGNET_NS" patch configmap postgres-config --type merge \
  -p '{"data":{"database-name":"mosip_esignet_mosipid2","database-username":"esignetuser_mosipid2"}}'

# Create esignet-misp-onboarder-key placeholder — real value written by MISP onboarder.
if ! kubectl -n "$ESIGNET_NS" get secret esignet-misp-onboarder-key &>/dev/null; then
  kubectl -n "$ESIGNET_NS" create secret generic esignet-misp-onboarder-key \
    --from-literal=mosip-esignet-misp-key=""
  echo "esignet-misp-onboarder-key placeholder created in $ESIGNET_NS"
fi

echo "Creating esignet-captcha-mosipid2 secret in $CAPTCHA_NS namespace"
kubectl -n "$CAPTCHA_NS" create secret generic esignet-captcha-mosipid2 \
  --from-literal=esignet-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=esignet-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Copying esignet-captcha-mosipid2 secret from $CAPTCHA_NS to $ESIGNET_NS"
$COPY_UTIL secret esignet-captcha-mosipid2 "$CAPTCHA_NS" "$ESIGNET_NS"

echo "Patching captcha deployment with ESIGNETMOSIPID2 secret key"
ENV_VAR_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
  -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETMOSIPID2')].name}" 2>/dev/null || echo "")
if [[ -z "$ENV_VAR_EXISTS" ]]; then
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETMOSIPID2", "valueFrom": {"secretKeyRef": {"name": "esignet-captcha-mosipid2", "key": "esignet-captcha-secret-key"}}}}]'
else
  echo "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETMOSIPID2 already exists."
fi

# --- postgres-postgresql-mosipid2 secret (MOSIPID2 remote postgres password) ---
echo "Creating postgres-postgresql-mosipid2 secret in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create secret generic postgres-postgresql-mosipid2 \
  --from-literal=postgres-password="${MOSIPID2_POSTGRES_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- keycloak-host-mosipid2 CM (external URL points to MOSIPID2 Keycloak) ---
echo "Creating keycloak-host-mosipid2 configmap in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create configmap keycloak-host-mosipid2 \
  --from-literal=keycloak-external-host="iam.${mosipid2_domain_name}" \
  --from-literal=keycloak-external-url="https://iam.${mosipid2_domain_name}" \
  --from-literal=keycloak-internal-host="keycloak.keycloak" \
  --from-literal=keycloak-internal-service-url="http://keycloak.keycloak/auth/" \
  --from-literal=keycloak-internal-url="http://keycloak.keycloak" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- keycloak-client-secrets-mosipid2: fetch all confidential clients from MOSIPID2 Keycloak ---
KC_HOST="iam.${mosipid2_domain_name}"
REALM="mosip"

echo "Fetching admin token from $KC_HOST"
TOKEN_RESPONSE=$(curl -sf -X POST \
  "https://${KC_HOST}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=${MOSIPID2_KC_ADMIN_PASS}")
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
  echo "❌ No client secrets fetched from MOSIPID2 Keycloak" >&2; exit 1
fi
echo "Creating keycloak-client-secrets-mosipid2 in $ESIGNET_NS (${#SECRET_ARGS[@]} clients)"
kubectl -n "$ESIGNET_NS" create secret generic keycloak-client-secrets-mosipid2 \
  "${SECRET_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ keycloak-client-secrets-mosipid2 created"

echo "eSignet MOSIPID2 pre-install completed."
