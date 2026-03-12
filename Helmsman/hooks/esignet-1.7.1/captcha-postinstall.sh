#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Captcha Post-install
# =============================================================================
# Based on: deploy/captcha/install.sh
# Configures captcha secrets for eSignet and patches captcha deployment
# with the secret key environment variable.
#
# Environment Variables:
#   CAPTCHA_SITE_KEY     - reCAPTCHA site key (REQUIRED)
#   CAPTCHA_SECRET_KEY   - reCAPTCHA secret key (REQUIRED)
#   ESIGNET_NS           - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
CAPTCHA_NS="captcha"
CAPTCHA_SITE_KEY="${CAPTCHA_SITE_KEY:?ERROR: CAPTCHA_SITE_KEY environment variable must be set}"
CAPTCHA_SECRET_KEY="${CAPTCHA_SECRET_KEY:?ERROR: CAPTCHA_SECRET_KEY environment variable must be set}"

echo "================================================"
echo "eSignet 1.7.1 - Captcha Post-install"
echo "================================================"

# --- Step 1: Create captcha secrets for eSignet ---
# Source: deploy/captcha/install.sh - captcha secrets section
echo "Creating esignet-captcha secret in $ESIGNET_NS namespace"
kubectl -n "$ESIGNET_NS" create secret generic esignet-captcha \
  --from-literal=esignet-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=esignet-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 2: Copy captcha secret to captcha namespace ---
# Source: deploy/captcha/install.sh -> ../copy_cm_func.sh secret esignet-captcha esignet captcha
echo "Copying esignet-captcha secret to $CAPTCHA_NS namespace"
kubectl -n "$ESIGNET_NS" get secret esignet-captcha -o yaml | \
  sed "s/namespace: $ESIGNET_NS/namespace: $CAPTCHA_NS/g" | \
  kubectl apply -f -

# --- Step 3: Patch captcha deployment with secret env var ---
# Source: deploy/captcha/install.sh - MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET
echo "Patching captcha deployment with secret key environment variable"
ENV_VAR_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET')].name}" 2>/dev/null || echo "")

if [[ -z "$ENV_VAR_EXISTS" ]]; then
  echo "Adding MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET env var..."
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET", "valueFrom": {"secretKeyRef": {"name": "esignet-captcha", "key": "esignet-captcha-secret-key"}}}}]'
else
  echo "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNET env var already exists."
fi

echo "Captcha post-install completed."
