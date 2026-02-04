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

function wait_for_config_server() {
  local old_generation=$1
  local timeout=180
  local elapsed=0
  
  echo "Waiting for config-server rollout (generation: $old_generation -> new)..."
  
  # First, wait for generation to change (rollout started)
  while [ $elapsed -lt 30 ]; do
    local current_generation=$(kubectl get deployment config-server -n config-server -o jsonpath='{.metadata.generation}' 2>/dev/null || echo "0")
    
    if [ "${current_generation:-0}" -gt "${old_generation:-0}" ]; then
      echo "New rollout detected (generation: $current_generation)"
      break
    fi
    
    echo "Waiting for rollout to start... (${elapsed}s)"
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  # Now wait for the new pods to be ready
  elapsed=0
  while [ $elapsed -lt $timeout ]; do
    local ready=$(kubectl get deployment config-server -n config-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment config-server -n config-server -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    local updated=$(kubectl get deployment config-server -n config-server -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || echo "0")
    
    # Check that updated replicas match desired and all are ready
    if [ "${ready:-0}" -ge "${desired:-1}" ] && [ "${updated:-0}" -ge "${desired:-1}" ] && [ "${ready:-0}" -gt 0 ]; then
      echo "config-server ready ($ready/$desired replicas, $updated updated)"
      return 0
    fi
    
    echo "Waiting for config-server: $ready/$desired ready, $updated/$desired updated (${elapsed}s)"
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  echo "WARNING: config-server not ready after ${timeout}s, proceeding anyway"
  return 1
}

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

  # ============================================================
  # Setup config-server environment variables for esignet
  # This must be done BEFORE esignet pods start, so they can
  # read config from config-server on startup
  # ============================================================
  echo "Setting up config-server environment variables for esignet"

  # Check and set captcha site key in config-server
  CAPTCHA_SITE_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_ESIGNET_CAPTCHA_SITE_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$CAPTCHA_SITE_KEY_ENV" ]; then
    echo "Adding esignet-captcha-site-key to config-server"
    kubectl -n config-server set env --keys=esignet-captcha-site-key --from secret/esignet-captcha deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "esignet-captcha-site-key already exists in config-server, skipping"
  fi

  # Check and set captcha secret key in config-server
  CAPTCHA_SECRET_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_ESIGNET_CAPTCHA_SECRET_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$CAPTCHA_SECRET_KEY_ENV" ]; then
    echo "Adding esignet-captcha-secret-key to config-server"
    kubectl -n config-server set env --keys=esignet-captcha-secret-key --from secret/esignet-captcha deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "esignet-captcha-secret-key already exists in config-server, skipping"
  fi

  # Check and set MISP key in config-server
  MISP_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_MISP_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$MISP_KEY_ENV" ]; then
    # Get current generation before making changes
    CURRENT_GENERATION=$(kubectl get deployment config-server -n config-server -o jsonpath='{.metadata.generation}' 2>/dev/null || echo "0")
    
    echo "Adding mosip-esignet-misp-key to config-server"
    kubectl -n config-server set env --keys=mosip-esignet-misp-key --from secret/esignet-misp-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
    
    # Wait for config-server to be ready after environment changes
    wait_for_config_server "$CURRENT_GENERATION"
  else
    echo "mosip-esignet-misp-key already exists in config-server, skipping"
  fi

  # Config-server is ready - proceeding with setup

  echo "Config-server configured, proceeding with setup..."

  # Copy required configmaps and secrets from other namespaces
  echo "Copying keycloak configmaps and secrets to $NS namespace"
  $COPY_UTIL configmap keycloak-host keycloak $NS
  $COPY_UTIL configmap keycloak-env-vars keycloak $NS
  $COPY_UTIL configmap global default $NS
  $COPY_UTIL configmap artifactory-share artifactory $NS
  $COPY_UTIL configmap config-server-share config-server $NS
  $COPY_UTIL configmap softhsm-esignet-share softhsm $NS  
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
