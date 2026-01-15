#!/bin/bash
# Pre-install hook for esignet
# This script sets up captcha secrets, MISP key, and copies required configmaps/secrets
# This script is IDEMPOTENT
## Usage: ./esignet-preinstall.sh [kubeconfig]
#
# Environment Variables (from GitHub Secrets):
#   ESIGNET_CAPTCHA_SITE_KEY    - reCAPTCHA site key for esignet domain
#   ESIGNET_CAPTCHA_SECRET_KEY  - reCAPTCHA secret key for esignet domain

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

# Read from environment variables (set by GitHub Actions from secrets)
ESIGNET_CAPTCHA_SITE_KEY="${ESIGNET_CAPTCHA_SITE_KEY:-}"
ESIGNET_CAPTCHA_SECRET_KEY="${ESIGNET_CAPTCHA_SECRET_KEY:-}"

function preinstall_esignet() {
  echo "Pre-install setup for esignet"

  # Debug: Check if captcha environment variables are set
  if [ -n "$ESIGNET_CAPTCHA_SITE_KEY" ]; then
    echo "✓ ESIGNET_CAPTCHA_SITE_KEY is set (value masked)"
  else
    echo "⚠ ESIGNET_CAPTCHA_SITE_KEY is NOT set"
  fi
  if [ -n "$ESIGNET_CAPTCHA_SECRET_KEY" ]; then
    echo "✓ ESIGNET_CAPTCHA_SECRET_KEY is set (value masked)"
  else
    echo "⚠ ESIGNET_CAPTCHA_SECRET_KEY is NOT set"
  fi

  # Create namespace if not exists
  kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f -

  # Add Istio label
  echo "Adding Istio injection label to $NS namespace"
  kubectl label ns $NS istio-injection=enabled --overwrite

  # Setup captcha secrets (idempotent - only create if not exists or if keys provided)
  echo "Setting up esignet captcha secrets"
  EXISTING_CAPTCHA=$( kubectl -n $NS get secret esignet-captcha -o jsonpath='{.data.esignet-captcha-site-key}' 2>/dev/null || echo "" )
  
  if [ -z "$EXISTING_CAPTCHA" ]; then
    if [ -n "$ESIGNET_CAPTCHA_SITE_KEY" ] && [ -n "$ESIGNET_CAPTCHA_SECRET_KEY" ]; then
      echo "Creating esignet-captcha secret with provided keys"
      kubectl -n $NS create secret generic esignet-captcha \
        --from-literal=esignet-captcha-site-key="$ESIGNET_CAPTCHA_SITE_KEY" \
        --from-literal=esignet-captcha-secret-key="$ESIGNET_CAPTCHA_SECRET_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
    else
      echo "WARNING: Captcha keys not provided and secret doesn't exist. Creating with empty values."
      echo "Please update the secret manually or re-run with captcha keys."
      kubectl -n $NS create secret generic esignet-captcha \
        --from-literal=esignet-captcha-site-key="" \
        --from-literal=esignet-captcha-secret-key="" \
        --dry-run=client -o yaml | kubectl apply -f -
    fi
  else
    echo "esignet-captcha secret already exists, skipping"
  fi

  # Setup MISP license key (idempotent - only create if not exists)
  echo "Setting up esignet MISP onboarder key"
  EXISTING_MISP=$( kubectl -n $NS get secret esignet-misp-onboarder-key -o jsonpath='{.data.mosip-esignet-misp-key}' 2>/dev/null || echo "" )
  
  if [ -z "$EXISTING_MISP" ]; then
    echo "Creating esignet-misp-onboarder-key secret with empty value"
    kubectl -n $NS create secret generic esignet-misp-onboarder-key \
      --from-literal=mosip-esignet-misp-key='' \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    echo "esignet-misp-onboarder-key secret already exists, skipping"
  fi

  # Copy MISP key to config-server
  echo "Copying esignet-misp-onboarder-key to config-server namespace"
  $COPY_UTIL secret esignet-misp-onboarder-key $NS config-server

  # Copy captcha secret to config-server
  echo "Copying esignet-captcha to config-server namespace"
  $COPY_UTIL secret esignet-captcha $NS config-server

  # Copy required configmaps and secrets from other namespaces
  echo "Copying keycloak configmaps and secrets to $NS namespace"
  $COPY_UTIL configmap keycloak-host keycloak $NS
  $COPY_UTIL configmap keycloak-env-vars keycloak $NS
  $COPY_UTIL configmap global default $DST_NS
  $COPY_UTIL configmap artifactory-share artifactory $DST_NS
  $COPY_UTIL configmap config-server-share config-server $DST_NS
  $COPY_UTIL configmap softhsm-esignet-share softhsm $DST_NS  
  $COPY_UTIL configmap artifactory-1202-share artifactory-1202 $NS  


  # Copy s3 secrets if exists
  echo "Copying s3 secret to $NS namespace (if exists)"
  $COPY_UTIL secret s3 s3 $NS 2>/dev/null || echo "s3 secret not found, skipping"
  $COPY_UTIL secret keycloak keycloak $NS
  echo "esignet pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_esignet   # calling function
