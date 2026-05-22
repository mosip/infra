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

"$WORKDIR/hooks/esignet-1.7.1/esignet-preinstall.sh"

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

echo "eSignet CRE pre-install completed."
