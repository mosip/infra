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

function wait_for_job_completion() {
  local job_label=$1
  local namespace=$2
  local timeout=${3:-300}
  
  echo "Waiting for job with label $job_label..."
  local max_wait=60
  local wait_interval=5
  local elapsed=0
  
  # Wait for job to be created or become active
  while [ $elapsed -lt $max_wait ]; do
    JOB_NAME=$(kubectl -n $namespace get jobs -l "$job_label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$JOB_NAME" ]; then
      # Check if job is active or was just created (not an old completed job)
      local active=$(kubectl -n $namespace get job/$JOB_NAME -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
      local succeeded=$(kubectl -n $namespace get job/$JOB_NAME -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
      local start_time=$(kubectl -n $namespace get job/$JOB_NAME -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
      
      # Check if job started within the last 5 minutes (300 seconds) - it's a fresh job
      if [ -n "$start_time" ]; then
        local job_start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        local age=$((current_epoch - job_start_epoch))
        
        if [ $age -lt 300 ] || [ "${active:-0}" -ge 1 ]; then
          echo "Found recent/active job: $JOB_NAME (age: ${age}s, active: ${active:-0})"
          break
        else
          echo "Found old completed job: $JOB_NAME (age: ${age}s), waiting for new job..."
        fi
      fi
      
      # If job is currently active, use it
      if [ "${active:-0}" -ge 1 ]; then
        echo "Found active job: $JOB_NAME"
        break
      fi
      
      # If job just completed successfully (within check interval), accept it
      if [ "${succeeded:-0}" -ge 1 ] && [ $elapsed -lt 30 ]; then
        echo "Found recently completed job: $JOB_NAME"
        return 0
      fi
    fi
    
    echo "Waiting for active/new job... ($elapsed/$max_wait seconds)"
    sleep $wait_interval
    elapsed=$((elapsed + wait_interval))
  done
  
  if [ -z "$JOB_NAME" ]; then
    echo "ERROR: No job found with label $job_label after $max_wait seconds"
    kubectl -n $namespace get jobs
    return 1
  fi
  
  # Check job status in a loop
  echo "Monitoring job $JOB_NAME status..."
  local start_time=$(date +%s)
  
  while true; do
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - start_time))
    
    if [ $elapsed_time -ge $timeout ]; then
      echo "ERROR: Job $JOB_NAME timed out after ${timeout}s"
      kubectl -n $namespace describe job/$JOB_NAME
      echo "(Job logs suppressed - check S3 onboarder bucket for reports)"
      return 1
    fi
    
    # Get job status
    local succeeded=$(kubectl -n $namespace get job/$JOB_NAME -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    local failed=$(kubectl -n $namespace get job/$JOB_NAME -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    local active=$(kubectl -n $namespace get job/$JOB_NAME -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
    
    echo "Job status - Active: ${active:-0}, Succeeded: ${succeeded:-0}, Failed: ${failed:-0} (elapsed: ${elapsed_time}s)"
    
    if [ "${succeeded:-0}" -ge 1 ]; then
      echo "Job $JOB_NAME completed successfully!"
      return 0
    fi
    
    if [ "${failed:-0}" -ge 1 ]; then
      echo "ERROR: Job $JOB_NAME failed!"
      kubectl -n $namespace describe job/$JOB_NAME
      echo "(Job logs suppressed - check S3 onboarder bucket for reports)"
      return 1
    fi
    
    sleep 5
  done
}

function postinstall_partner_onboarder() {
  echo "Post-install setup for esignet-resident-oidc-partner-onboarder"

  # Wait for the onboarder job to complete (it creates the secrets we need)
  echo "Waiting for esignet-resident-oidc-partner-onboarder job to complete..."
  
  # Wait for job completion with status monitoring
  if ! wait_for_job_completion "app.kubernetes.io/instance=esignet-resident-oidc-partner-onboarder" "$NS" 300; then
    echo "WARNING: Job completion wait failed, but will still try to verify secrets..."
  fi
  
  # Verify secrets exist before copying
  echo "Verifying secrets exist..."
  MAX_RETRIES=3
  RETRY_INTERVAL=5
  
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
  CONFIG_CHANGED=false
  if [ -z "$MISP_KEY_ENV" ]; then
    echo "Adding mosip-esignet-misp-key to config-server"
    kubectl -n config-server set env --keys=mosip-esignet-misp-key --from secret/esignet-misp-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
    CONFIG_CHANGED=true
  else
    echo "mosip-esignet-misp-key already exists in config-server, skipping"
  fi

  # Check and set resident OIDC client ID in config-server (idempotent)
  RESIDENT_OIDC_ENV=$( kubectl -n config-server get deployment config-server -o json 2>/dev/null | jq -c '.spec.template.spec.containers[].env[]? | select(.name == "SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_RESIDENT_OIDC_CLIENTID") | .name' 2>/dev/null || echo "" )
  if [ -z "$RESIDENT_OIDC_ENV" ]; then
    echo "Adding resident-oidc-clientid to config-server"
    kubectl -n config-server set env --keys=resident-oidc-clientid --from secret/resident-oidc-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
    CONFIG_CHANGED=true
  else
    echo "resident-oidc-clientid already exists in config-server, skipping"
  fi

  # If config was not changed, still restart config-server to pick up any secret changes
  if [ "$CONFIG_CHANGED" = "false" ]; then
    echo "No new env vars added, but restarting config-server to pick up any secret changes..."
    kubectl -n config-server rollout restart deploy/config-server
  fi

  # Config-server restart initiated - continuing with deployment
  echo "Config-server restart initiated, continuing with deployment..."

  # Restart esignet deployment to pick up new secrets
  echo "Restarting esignet deployment"
  kubectl rollout restart deployment -n $NS esignet 2>/dev/null || echo "esignet deployment not found, skipping restart"

  # Restart resident deployment to pick up new secrets (if exists)
  echo "Restarting resident deployment (if exists)"
  kubectl rollout restart deployment -n resident resident 2>/dev/null || echo "resident deployment not found, skipping restart"

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
