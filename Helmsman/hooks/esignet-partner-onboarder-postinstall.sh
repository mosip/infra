#!/bin/bash
# Post-install hook for esignet-resident-oidc-partner-onboarder
# This script copies secrets to config-server and restarts deployments
# This script is IDEMPOTENT
## Usage: ./esignet-partner-onboarder-postinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function postinstall_partner_onboarder() {
  echo "Post-install setup for esignet-resident-oidc-partner-onboarder"

  # Wait for the onboarder job to complete (it creates the secrets we need)
  echo "Waiting for esignet-resident-oidc-partner-onboarder job to complete..."
  echo "Sleeping for 2 minutes to allow job to start and complete..."
  sleep 120
  
  # Wait for the job to complete with timeout
  JOB_NAME=$(kubectl -n $NS get jobs -l app.kubernetes.io/instance=esignet-resident-oidc-partner-onboarder -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$JOB_NAME" ]; then
    echo "Found job: $JOB_NAME, waiting for completion..."
    kubectl -n $NS wait --for=condition=complete --timeout=600s job/$JOB_NAME || {
      echo "Job did not complete in time, checking status..."
      kubectl -n $NS describe job/$JOB_NAME
      kubectl -n $NS logs job/$JOB_NAME --tail=100 || true
      echo "Continuing anyway..."
    }
  else
    echo "No onboarder job found, waiting additional time for secrets to be created..."
    sleep 60
  fi
  
  # Verify secrets exist before copying
  echo "Verifying secrets exist..."
  MAX_RETRIES=10
  RETRY_INTERVAL=30
  
  for i in $(seq 1 $MAX_RETRIES); do
    MISP_SECRET=$(kubectl -n $NS get secret esignet-misp-onboarder-key --ignore-not-found -o name 2>/dev/null || echo "")
    RESIDENT_SECRET=$(kubectl -n $NS get secret resident-oidc-onboarder-key --ignore-not-found -o name 2>/dev/null || echo "")
    
    if [ -n "$MISP_SECRET" ] && [ -n "$RESIDENT_SECRET" ]; then
      echo "Both secrets found, proceeding with copy..."
      break
    fi
    
    if [ $i -eq $MAX_RETRIES ]; then
      echo "ERROR: Secrets not found after $MAX_RETRIES retries"
      echo "esignet-misp-onboarder-key: $MISP_SECRET"
      echo "resident-oidc-onboarder-key: $RESIDENT_SECRET"
      kubectl -n $NS get secrets
      exit 1
    fi
    
    echo "Waiting for secrets to be created (attempt $i/$MAX_RETRIES)..."
    sleep $RETRY_INTERVAL
  done

  # Copy esignet-misp-onboarder-key to config-server
  echo "Copying esignet-misp-onboarder-key secret to config-server namespace"
  $COPY_UTIL secret esignet-misp-onboarder-key $NS config-server

  # Copy resident-oidc-onboarder-key to config-server and resident namespaces
  echo "Copying resident-oidc-onboarder-key secret to config-server namespace"
  $COPY_UTIL secret resident-oidc-onboarder-key $NS config-server

  echo "Copying resident-oidc-onboarder-key secret to resident namespace"
  kubectl create ns resident --dry-run=client -o yaml | kubectl apply -f -
  $COPY_UTIL secret resident-oidc-onboarder-key $NS resident

  # Check and set MISP key in config-server (idempotent)
  MISP_KEY_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_MOSIP_ESIGNET_MISP_KEY") | .name' 2>/dev/null || echo "" )
  if [ -z "$MISP_KEY_ENV" ]; then
    echo "Adding mosip-esignet-misp-key to config-server"
    kubectl -n config-server set env --keys=mosip-esignet-misp-key --from secret/esignet-misp-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "mosip-esignet-misp-key already exists in config-server, skipping"
  fi

  # Check and set resident OIDC client ID in config-server (idempotent)
  RESIDENT_OIDC_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_RESIDENT_OIDC_CLIENTID") | .name' 2>/dev/null || echo "" )
  if [ -z "$RESIDENT_OIDC_ENV" ]; then
    echo "Adding resident-oidc-clientid to config-server"
    kubectl -n config-server set env --keys=resident-oidc-clientid --from secret/resident-oidc-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  else
    echo "resident-oidc-clientid already exists in config-server, skipping"
  fi

  # Wait for config-server rollout
  echo "Waiting for config-server to be ready"
  
  # Check if there are any pods stuck in terminating state
  TERMINATING_PODS=$(kubectl -n config-server get pods -l app.kubernetes.io/name=config-server --field-selector=status.phase=Terminating -o name 2>/dev/null || echo "")
  if [ -n "$TERMINATING_PODS" ]; then
    echo "Found terminating pods, waiting for them to clear..."
    for pod in $TERMINATING_PODS; do
      echo "Waiting for $pod to terminate..."
      kubectl -n config-server wait --for=delete "$pod" --timeout=120s 2>/dev/null || true
    done
  fi
  
  # Wait for rollout with increased timeout
  if ! kubectl -n config-server rollout status deploy/config-server --timeout=600s; then
    echo "Rollout timed out, checking deployment status..."
    kubectl -n config-server describe deploy/config-server
    kubectl -n config-server get pods -l app.kubernetes.io/name=config-server
    echo "Attempting to restart stuck rollout..."
    kubectl -n config-server rollout restart deploy/config-server
    kubectl -n config-server rollout status deploy/config-server --timeout=300s
  fi

  # Restart esignet deployment to pick up new secrets
  echo "Restarting esignet deployment"
  kubectl rollout restart deployment -n $NS esignet 2>/dev/null || echo "esignet deployment not found, skipping restart"
  kubectl -n $NS rollout status deploy/esignet --timeout=300s 2>/dev/null || true

  # Restart resident deployment to pick up new secrets (if exists)
  echo "Restarting resident deployment (if exists)"
  kubectl rollout restart deployment -n resident resident 2>/dev/null || echo "resident deployment not found, skipping restart"
  kubectl -n resident rollout status deploy/resident --timeout=300s 2>/dev/null || true

  echo "eSignet MISP License Key and Resident OIDC Client ID updated successfully."
  echo "Reports are moved to S3 under onboarder bucket"

  echo "Partner onboarder post-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
postinstall_partner_onboarder   # calling function
