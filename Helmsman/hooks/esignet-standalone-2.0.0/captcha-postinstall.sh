#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Captcha Post-install
# =============================================================================
# Based on: deploy/captcha/install.sh
# Configures captcha secrets for eSignet and patches captcha deployment
# with the secret key environment variable.
#
# Environment Variables:
#   ESIGNET_CAPTCHA_SITE_KEY     - reCAPTCHA site key (REQUIRED)
#   ESIGNET_CAPTCHA_SECRET_KEY   - reCAPTCHA secret key (REQUIRED)
#   ESIGNET_NS                  - eSignet namespace (default: esignet-mock)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"
CAPTCHA_NS="captcha"
CAPTCHA_SITE_KEY="${ESIGNET_CAPTCHA_SITE_KEY:?ERROR: ESIGNET_CAPTCHA_SITE_KEY environment variable must be set}"
CAPTCHA_SECRET_KEY="${ESIGNET_CAPTCHA_SECRET_KEY:?ERROR: ESIGNET_CAPTCHA_SECRET_KEY environment variable must be set}"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Captcha Post-install"
echo "================================================"

# --- Step 1: Create captcha secrets for eSignet ---
echo "Creating esignet-captcha secret in $ESIGNET_NS namespace"
kubectl -n "$ESIGNET_NS" create secret generic esignet-captcha \
  --from-literal=esignet-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=esignet-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 2: Copy captcha secret to captcha namespace ---
echo "Copying esignet-captcha secret to $CAPTCHA_NS namespace"
$COPY_UTIL secret esignet-captcha "$ESIGNET_NS" "$CAPTCHA_NS"

# --- Step 3: Patch captcha deployment with secret env var ---
echo "Patching captcha deployment with secret key environment variable"

# Remove the old pre-rename env var name if still present, so it doesn't linger
# pointing at a secret that no longer exists (esignet-captcha-go was renamed to
# esignet-captcha).
OLD_ENV_INDEX=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
  -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}{'\n'}{end}" 2>/dev/null \
  | grep -n -x "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET_GO" | cut -d: -f1 || echo "")
if [[ -n "$OLD_ENV_INDEX" ]]; then
  OLD_ENV_ARRAY_INDEX=$((OLD_ENV_INDEX - 1))
  echo "Removing stale MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET_GO env var (index $OLD_ENV_ARRAY_INDEX)"
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p="[{\"op\": \"remove\", \"path\": \"/spec/template/spec/containers/0/env/$OLD_ENV_ARRAY_INDEX\"}]"
fi

ENV_VAR_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET')].name}" 2>/dev/null || echo "")

if [[ -z "$ENV_VAR_EXISTS" ]]; then
  echo "Adding MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET env var..."
  ENV_ARRAY_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
    -o jsonpath="{.spec.template.spec.containers[0].env}" 2>/dev/null || echo "")
  if [[ -z "$ENV_ARRAY_EXISTS" ]]; then
    echo "env array not found, initializing..."
    kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
      -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env", "value": []}]'
  fi
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET", "valueFrom": {"secretKeyRef": {"name": "esignet-captcha", "key": "esignet-captcha-secret-key"}}}}]'
else
  echo "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET env var already exists."
fi

echo "Captcha post-install completed."
