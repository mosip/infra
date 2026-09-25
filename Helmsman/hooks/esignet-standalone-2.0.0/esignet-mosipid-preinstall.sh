#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MOSIPID Service Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid, runs base esignet preinstall (copies
# postgres + redis config/secrets), then creates esignet-captcha-mosipid secret
# in the captcha namespace from workflow env vars, copies it to esignet-mosipid,
# and patches the captcha deployment with the MOSIPID secret key.
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-mosipid"
CAPTCHA_NS="captcha"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CAPTCHA_SITE_KEY="${ESIGNET_MOSIPID_CAPTCHA_SITE_KEY:?ERROR: ESIGNET_MOSIPID_CAPTCHA_SITE_KEY must be set}"
CAPTCHA_SECRET_KEY="${ESIGNET_MOSIPID_CAPTCHA_SECRET_KEY:?ERROR: ESIGNET_MOSIPID_CAPTCHA_SECRET_KEY must be set}"
MOSIPID_POSTGRES_PASS="${MOSIPID_POSTGRES_PASSWORD:?ERROR: MOSIPID_POSTGRES_PASSWORD must be set}"
MOSIPID_KC_ADMIN_PASS="${MOSIPID_KEYCLOAK_ADMIN_PASSWORD:?ERROR: MOSIPID_KEYCLOAK_ADMIN_PASSWORD must be set}"

"$WORKDIR/hooks/esignet-standalone-2.0.0/esignet-preinstall.sh"

# Create MOSIPID-specific esignet-global — same domain_name, but esignet/signup hosts differ
kubectl -n "$ESIGNET_NS" create configmap esignet-global \
  --from-literal=installation-domain="${domain_name}" \
  --from-literal=mosip-api-host="api.${domain_name}" \
  --from-literal=mosip-api-internal-host="api-internal.${domain_name}" \
  --from-literal=mosip-esignet-host="esignet-mosipid.${domain_name}" \
  --from-literal=mosip-iam-external-host="iam.${domain_name}" \
  --from-literal=mosip-kafka-host="kafka.${domain_name}" \
  --from-literal=mosip-postgres-host="postgres.${domain_name}" \
  --from-literal=mosip-signup-host="signup-mosipid.${domain_name}" \
  --from-literal=mosip-smtp-host="smtp.${domain_name}" \
  --from-literal=mosip-version="develop" \
  --dry-run=client -o yaml | kubectl apply -f -

# Override postgres-config with MOSIPID-specific DB values (2.0.0: isolated database)
kubectl -n "$ESIGNET_NS" patch configmap postgres-config --type merge \
  -p '{"data":{"database-name":"mosip_esignet_go_mosipid","database-username":"esignetuser_go_mosipid"}}'

# Create esignet-misp-onboarder-key with a random placeholder value — real value written
# by MISP onboarder if/when that's wired up. An empty value makes the Go esignet service
# Fatal on startup during plugin provider init, so this can't be left blank. Only generated
# once (create-if-missing, not overwritten on every run) so the value stays stable across
# redeploys - regenerating it on every run would be pointless churn since nothing else reads
# or depends on this specific value being consistent.
if ! kubectl -n "$ESIGNET_NS" get secret esignet-misp-onboarder-key &>/dev/null; then
  kubectl -n "$ESIGNET_NS" create secret generic esignet-misp-onboarder-key \
    --from-literal=mosip-esignet-misp-key="$(openssl rand -hex 16)"
  echo "esignet-misp-onboarder-key (random placeholder) created in $ESIGNET_NS"
fi

echo "Creating esignet-captcha-mosipid secret in $CAPTCHA_NS namespace"
kubectl -n "$CAPTCHA_NS" create secret generic esignet-captcha-mosipid \
  --from-literal=esignet-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=esignet-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Copying esignet-captcha-mosipid secret from $CAPTCHA_NS to $ESIGNET_NS"
$COPY_UTIL secret esignet-captcha-mosipid "$CAPTCHA_NS" "$ESIGNET_NS"

echo "Patching captcha deployment with ESIGNETMOSIPID secret key"

# Remove stale pre-rename/pre-consolidation env var names if still present, so they
# don't linger pointing at secrets that no longer exist.
for OLD_NAME in MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETGOMOSIPID1 MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETGOMOSIPID2; do
  OLD_ENV_INDEX=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
    -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}{'\n'}{end}" 2>/dev/null \
    | grep -n -x "$OLD_NAME" | cut -d: -f1 || echo "")
  if [[ -n "$OLD_ENV_INDEX" ]]; then
    OLD_ENV_ARRAY_INDEX=$((OLD_ENV_INDEX - 1))
    echo "Removing stale $OLD_NAME env var (index $OLD_ENV_ARRAY_INDEX)"
    kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
      -p="[{\"op\": \"remove\", \"path\": \"/spec/template/spec/containers/0/env/$OLD_ENV_ARRAY_INDEX\"}]"
  fi
done

ENV_VAR_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
  -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETMOSIPID')].name}" 2>/dev/null || echo "")
if [[ -z "$ENV_VAR_EXISTS" ]]; then
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETMOSIPID", "valueFrom": {"secretKeyRef": {"name": "esignet-captcha-mosipid", "key": "esignet-captcha-secret-key"}}}}]'
else
  echo "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETMOSIPID already exists."
fi

# --- postgres-postgresql-mosipid secret (MOSIPID remote postgres password) ---
echo "Creating postgres-postgresql-mosipid secret in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create secret generic postgres-postgresql-mosipid \
  --from-literal=postgres-password="${MOSIPID_POSTGRES_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- keycloak-host-mosipid CM (external URL points to MOSIPID Keycloak) ---
echo "Creating keycloak-host-mosipid configmap in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create configmap keycloak-host-mosipid \
  --from-literal=keycloak-external-host="iam.${mosipid_domain_name}" \
  --from-literal=keycloak-external-url="https://iam.${mosipid_domain_name}" \
  --from-literal=keycloak-internal-host="keycloak.keycloak" \
  --from-literal=keycloak-internal-service-url="http://keycloak.keycloak/auth/" \
  --from-literal=keycloak-internal-url="http://keycloak.keycloak" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- keycloak-client-secrets-mosipid: fetch all confidential clients from MOSIPID Keycloak ---
KC_HOST="iam.${mosipid_domain_name}"
REALM="mosip"

echo "Fetching admin token from $KC_HOST"
TOKEN_RESPONSE=$(curl -sf -X POST \
  "https://${KC_HOST}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=${MOSIPID_KC_ADMIN_PASS}")
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
  echo "❌ No client secrets fetched from MOSIPID Keycloak" >&2; exit 1
fi
echo "Creating keycloak-client-secrets-mosipid in $ESIGNET_NS (${#SECRET_ARGS[@]} clients)"
kubectl -n "$ESIGNET_NS" create secret generic keycloak-client-secrets-mosipid \
  "${SECRET_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ keycloak-client-secrets-mosipid created"

echo "eSignet MOSIPID pre-install completed."
