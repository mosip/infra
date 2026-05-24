#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet QA11 Service Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-qa11, runs base esignet preinstall (copies
# postgres + redis config/secrets), then creates esignet-captcha-qa11 secret
# in the captcha namespace from workflow env vars, copies it to esignet-qa11,
# and patches the captcha deployment with the QA11 secret key.
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-qa11"
CAPTCHA_NS="captcha"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CAPTCHA_SITE_KEY="${ESIGNET_QA11_CAPTCHA_SITE_KEY:?ERROR: ESIGNET_QA11_CAPTCHA_SITE_KEY must be set}"
CAPTCHA_SECRET_KEY="${ESIGNET_QA11_CAPTCHA_SECRET_KEY:?ERROR: ESIGNET_QA11_CAPTCHA_SECRET_KEY must be set}"

"$WORKDIR/hooks/esignet-1.7.1/esignet-preinstall.sh"

# Override postgres-config with QA11-specific DB values
kubectl -n "$ESIGNET_NS" patch configmap postgres-config --type merge \
  -p '{"data":{"database-name":"mosip_esignet_qa11","database-username":"esignetuser_qa11"}}'

# Create esignet-misp-onboarder-key placeholder — real value written by MISP onboarder.
if ! kubectl -n "$ESIGNET_NS" get secret esignet-misp-onboarder-key &>/dev/null; then
  kubectl -n "$ESIGNET_NS" create secret generic esignet-misp-onboarder-key \
    --from-literal=mosip-esignet-misp-key=""
  echo "esignet-misp-onboarder-key placeholder created in $ESIGNET_NS"
fi

echo "Creating esignet-captcha-qa11 secret in $CAPTCHA_NS namespace"
kubectl -n "$CAPTCHA_NS" create secret generic esignet-captcha-qa11 \
  --from-literal=esignet-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=esignet-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Copying esignet-captcha-qa11 secret from $CAPTCHA_NS to $ESIGNET_NS"
$COPY_UTIL secret esignet-captcha-qa11 "$CAPTCHA_NS" "$ESIGNET_NS"

echo "Patching captcha deployment with ESIGNETQA11 secret key"
ENV_VAR_EXISTS=$(kubectl -n "$CAPTCHA_NS" get deployment captcha \
  -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETQA11')].name}" 2>/dev/null || echo "")
if [[ -z "$ENV_VAR_EXISTS" ]]; then
  kubectl patch deployment -n "$CAPTCHA_NS" captcha --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETQA11", "valueFrom": {"secretKeyRef": {"name": "esignet-captcha-qa11", "key": "esignet-captcha-secret-key"}}}}]'
else
  echo "MOSIP_CAPTCHA_GOOGLERECAPTCHAV2_SECRET_ESIGNETQA11 already exists."
fi

echo "eSignet QA11 pre-install completed."
