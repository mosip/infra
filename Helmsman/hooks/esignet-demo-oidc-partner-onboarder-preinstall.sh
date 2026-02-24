#!/bin/bash
# Pre-install hook for esignet-demo-oidc-partner-onboarder
# This script prepares the environment before partner-onboarder helm chart is deployed for demo-oidc
# This script is IDEMPOTENT
## Usage: ./esignet-demo-oidc-partner-onboarder-preinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function preinstall_demo_oidc_partner_onboarder() {
  echo "=============================================="
  echo "Pre-install setup for esignet-demo-oidc-partner-onboarder"
  echo "=============================================="

  # Create namespace if not exists
  kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f -

  # Disable Istio injection for onboarder (as per legacy script)
  echo "Setting Istio injection to disabled for $NS namespace"
  kubectl label ns $NS istio-injection=disabled --overwrite

  # Delete existing Jobs to avoid immutability errors on re-runs
  # Kubernetes Jobs cannot be updated once created, so we must delete them first
  echo "Cleaning up existing demo-oidc onboarder jobs in $NS namespace"
  kubectl -n $NS delete job -l app.kubernetes.io/instance=esignet-demo-oidc-partner-onboarder --ignore-not-found=true
  # Wait for job pods to terminate
  sleep 5

  # Delete existing onboarding configmap to avoid helm ownership conflict
  # This configmap may have been created by esignet-resident-oidc-partner-onboarder
  echo "Cleaning up existing onboarding configmap in $NS namespace"
  kubectl -n $NS delete cm onboarding --ignore-not-found=true

  # Delete existing s3 configmap to refresh (as per legacy script)
  echo "Cleaning up existing s3 configmap in $NS namespace"
  kubectl -n $NS delete cm s3 --ignore-not-found=true

  # Copy configmaps
  echo "Copying configmaps to $NS namespace"
  $COPY_UTIL configmap global default $NS
  $COPY_UTIL configmap keycloak-env-vars keycloak $NS
  $COPY_UTIL configmap keycloak-host keycloak $NS

  # Copy secrets
  echo "Copying secrets to $NS namespace"
  $COPY_UTIL secret s3 s3 $NS 2>/dev/null || echo "s3 secret not found in s3 namespace, skipping"
  $COPY_UTIL secret keycloak keycloak $NS
  $COPY_UTIL secret keycloak-client-secrets keycloak $NS

  # Create/update esignet-onboarder-namespace configmap from onboarder-namespace (as per legacy script)
  echo "Setting up esignet-onboarder-namespace configmap"
  kubectl -n $NS delete cm esignet-onboarder-namespace --ignore-not-found=true
  if kubectl -n $NS get cm onboarder-namespace &>/dev/null; then
    # Use yq to change only metadata.name, or fall back to anchored sed
    if command -v yq &> /dev/null; then
      kubectl -n $NS get cm onboarder-namespace -o yaml | \
        yq eval '.metadata.name = "esignet-onboarder-namespace"' - | \
        kubectl -n $NS apply -f -
    else
      # Fallback: Use sed with anchored pattern to match only metadata section
      kubectl -n $NS get cm onboarder-namespace -o yaml | \
        sed '/^metadata:/,/^[^ ]/ s/^  name:.*/  name: esignet-onboarder-namespace/' | \
        kubectl -n $NS apply -f -
    fi
    kubectl -n $NS delete cm onboarder-namespace --ignore-not-found=true
  else
    echo "onboarder-namespace configmap not found, skipping rename"
  fi

  # Fetch s3-user-key from s3 configmap
  echo "Fetching s3-user-key from s3 configmap"
  S3_USER_KEY=$( kubectl -n s3 get cm s3 -o jsonpath='{.data.s3-user-key}' 2>/dev/null || echo "" )
  if [ -n "$S3_USER_KEY" ]; then
    echo "s3-user-key found"
    # Store for use in DSF set values
    kubectl -n $NS create configmap s3-onboarder-config \
      --from-literal=s3-user-key="$S3_USER_KEY" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    echo "ERROR: s3-user-key not found in s3 configmap"
    return 1
  fi

  echo "Demo OIDC partner onboarder pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_demo_oidc_partner_onboarder   # calling function
