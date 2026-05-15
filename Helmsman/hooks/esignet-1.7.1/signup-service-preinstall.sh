#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Signup Service Pre-install
# =============================================================================
# Based on: esignet-signup/deploy/prereq.sh + deploy/msg-gateway/install.sh
# Sets up all prerequisites for signup-service:
#   - Copies redis-config configmap and redis secret
#   - Creates keycloak-host configmap (KEYCLOAK_EXTERNAL_URL)
#   - Creates empty signup-captcha secret (update site/secret keys for prod)
#   - Creates empty signup-keystore and signup-keystore-password secrets
#   - Creates msg-gateway configmap and secret (default: mock-smtp)
#
# Environment Variables:
#   SIGNUP_NS              - Signup namespace (default: signup)
#   MOSIP_IAM_EXTERNAL_HOST - Keycloak external host (e.g. iam.sandbox.xyz.net)
#   MOSIP_SIGNUP_CAPTCHA_SITE_KEY   - reCAPTCHA site key (default: empty)
#   MOSIP_SIGNUP_CAPTCHA_SECRET_KEY - reCAPTCHA secret key (default: empty)
# =============================================================================
set -euo pipefail

SIGNUP_NS="${SIGNUP_NS:-signup}"
REDIS_NS="redis"
KEYCLOAK_NS="keycloak"
IAM_EXTERNAL_HOST="${MOSIP_IAM_EXTERNAL_HOST:-}"
CAPTCHA_SITE_KEY="${MOSIP_SIGNUP_CAPTCHA_SITE_KEY:-}"
CAPTCHA_SECRET_KEY="${MOSIP_SIGNUP_CAPTCHA_SECRET_KEY:-}"

echo "================================================"
echo "eSignet 1.7.1 - Signup Service Pre-install"
echo "================================================"

# --- Step 1: Ensure signup namespace exists with istio ---
kubectl create namespace "$SIGNUP_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$SIGNUP_NS" istio-injection=enabled --overwrite

# --- Step 2: Copy redis configmap and secret ---
# Source: deploy/prereq.sh - copy_cm_func.sh redis-config and redis secret
echo "Copying redis-config to $SIGNUP_NS namespace"
kubectl -n "$REDIS_NS" get configmap redis-config -o yaml | \
  sed "s|^\(\s*namespace:\) $REDIS_NS$|\1 $SIGNUP_NS|" | \
  kubectl apply -f -
echo "Copying redis secret to $SIGNUP_NS namespace"
kubectl -n "$REDIS_NS" get secret redis -o yaml | \
  sed "s|^\(\s*namespace:\) $REDIS_NS$|\1 $SIGNUP_NS|" | \
  kubectl apply -f -

# --- Step 3: Create keycloak-host configmap ---
# Source: deploy/prereq.sh + keycloak-postinstall.sh pattern
echo "Creating keycloak-host configmap in $SIGNUP_NS"
kubectl -n "$SIGNUP_NS" create configmap keycloak-host \
  --from-literal=keycloak-external-url="https://$IAM_EXTERNAL_HOST/auth" \
  --from-literal=keycloak-internal-url="http://keycloak.$KEYCLOAK_NS" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 4: Create signup-captcha secret ---
# Source: deploy/prereq.sh - signup-captcha secret
# For production: set MOSIP_SIGNUP_CAPTCHA_SITE_KEY and MOSIP_SIGNUP_CAPTCHA_SECRET_KEY
echo "Creating signup-captcha secret in $SIGNUP_NS"
kubectl -n "$SIGNUP_NS" create secret generic signup-captcha \
  --from-literal=signup-captcha-site-key="$CAPTCHA_SITE_KEY" \
  --from-literal=signup-captcha-secret-key="$CAPTCHA_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 5: Create signup-keystore secrets ---
# Source: deploy/prereq.sh - empty keystore secrets created initially
echo "Creating signup-keystore secrets in $SIGNUP_NS"
kubectl -n "$SIGNUP_NS" create secret generic signup-keystore-password \
  --from-literal=signup-keystore-password='' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$SIGNUP_NS" create secret generic signup-keystore \
  --from-literal=oidckeystore.p12='' \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 6: Create msg-gateway configmap and secret (pointing to mock-smtp) ---
# Source: deploy/msg-gateway/install.sh - default mock-smtp config
echo "Creating msg-gateway configmap and secret in $SIGNUP_NS"
kubectl -n "$SIGNUP_NS" create configmap msg-gateway \
  --from-literal=smtp-host="mock-smtp.mock-smtp" \
  --from-literal=sms-host="mock-smtp.mock-smtp" \
  --from-literal=smtp-port="8025" \
  --from-literal=sms-port="8080" \
  --from-literal=smtp-username="" \
  --from-literal=sms-username="" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$SIGNUP_NS" create secret generic msg-gateway \
  --from-literal=smtp-secret='' \
  --from-literal=sms-secret='' \
  --from-literal=sms-authkey='authkey' \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Signup service pre-install completed."
