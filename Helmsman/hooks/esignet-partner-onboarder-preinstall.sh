#!/bin/bash
# Pre-install hook for esignet-resident-oidc-partner-onboarder
# This script prepares the environment before partner-onboarder helm chart is deployed
# This script is IDEMPOTENT
## Usage: ./esignet-partner-onboarder-preinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function preinstall_partner_onboarder() {
  echo "Pre-install setup for esignet-resident-oidc-partner-onboarder"

  # Create namespace if not exists
  kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f -

  # Disable Istio injection for onboarder (as per legacy script)
  echo "Setting Istio injection to disabled for $NS namespace"
  kubectl label ns $NS istio-injection=disabled --overwrite

  # Delete existing Jobs to avoid immutability errors on re-runs
  # Kubernetes Jobs cannot be updated once created, so we must delete them first
  echo "Cleaning up existing onboarder jobs in $NS namespace"
  kubectl -n $NS delete job -l app.kubernetes.io/instance=esignet-resident-oidc-partner-onboarder --ignore-not-found=true
  # Wait for job pods to terminate
  sleep 5

  # Delete existing s3 configmap to refresh (as per legacy script)
  echo "Cleaning up existing s3 configmap in $NS namespace"
  kubectl -n $NS delete cm s3 --ignore-not-found=true

  # Delete existing onboarding configmap (as per legacy script)
  echo "Cleaning up existing onboarding configmap in $NS namespace"
  kubectl -n $NS delete cm onboarding --ignore-not-found=true

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

  # Fetch s3-user-key from s3 configmap and create/update in esignet namespace
  echo "Fetching s3-user-key from s3 configmap"
  S3_USER_KEY=$( kubectl -n s3 get cm s3 -o jsonpath='{.data.s3-user-key}' 2>/dev/null || echo "" )
  if [ -n "$S3_USER_KEY" ]; then
    echo "s3-user-key found: $S3_USER_KEY"
    # Create a configmap with s3-user-key in esignet namespace for the chart to use
    kubectl -n $NS create configmap s3-onboarder-config \
      --from-literal=s3-user-key="$S3_USER_KEY" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    echo "WARNING: s3-user-key not found in s3 configmap"
  fi

  echo "Partner onboarder pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_partner_onboarder   # calling function
