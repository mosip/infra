#!/bin/bash
# Post-install hook for esignet-demo-oidc-partner-onboarder
# This script extracts the private/public key pair and client ID from onboarder job logs
# and updates the mock-relying-party-service secrets and mock-relying-party-ui deployment
# This script is IDEMPOTENT
## Usage: ./esignet-demo-oidc-partner-onboarder-postinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
JOB_NAME="esignet-demo-oidc-partner-onboarder-demo-oidc"

function wait_for_job_status() {
  local job_name=$1
  local namespace=$2
  local timeout=${3:-300}
  
  echo "Waiting for job $job_name..."
  local max_wait=60
  local wait_interval=5
  local elapsed=0
  
  # Wait for job to be created and become active (not an old completed job)
  while [ $elapsed -lt $max_wait ]; do
    if kubectl get job/$job_name -n $namespace &>/dev/null; then
      # Check if job is active or was recently started
      local active=$(kubectl -n $namespace get job/$job_name -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
      local succeeded=$(kubectl -n $namespace get job/$job_name -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
      local job_start_time=$(kubectl -n $namespace get job/$job_name -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
      
      # Check if job started within the last 5 minutes (300 seconds) - it's a fresh job
      if [ -n "$job_start_time" ]; then
        local job_start_epoch=$(date -d "$job_start_time" +%s 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        local age=$((current_epoch - job_start_epoch))
        
        if [ $age -lt 300 ] || [ "${active:-0}" -ge 1 ]; then
          echo "Found recent/active job: $job_name (age: ${age}s, active: ${active:-0})"
          break
        else
          echo "Found old completed job: $job_name (age: ${age}s), waiting for new job..."
        fi
      fi
      
      # If job is currently active, use it
      if [ "${active:-0}" -ge 1 ]; then
        echo "Found active job: $job_name"
        break
      fi
      
      # If job just completed successfully (within check interval), accept it
      if [ "${succeeded:-0}" -ge 1 ] && [ $elapsed -lt 30 ]; then
        echo "Found recently completed job: $job_name"
        return 0
      fi
    fi
    
    echo "Waiting for active/new job... ($elapsed/$max_wait seconds)"
    sleep $wait_interval
    elapsed=$((elapsed + wait_interval))
  done
  
  if ! kubectl get job/$job_name -n $namespace &>/dev/null; then
    echo "ERROR: Job $job_name not found after $max_wait seconds"
    kubectl -n $namespace get jobs
    return 1
  fi
  
  # Check job status in a loop
  echo "Monitoring job $job_name status..."
  local start_time=$(date +%s)
  
  while true; do
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - start_time))
    
    if [ $elapsed_time -ge $timeout ]; then
      echo "ERROR: Job $job_name timed out after ${timeout}s"
      kubectl -n $namespace describe job/$job_name
      echo "(Job logs suppressed - check S3 onboarder bucket for reports)"
      return 1
    fi
    
    # Get job status
    local succeeded=$(kubectl -n $namespace get job/$job_name -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    local failed=$(kubectl -n $namespace get job/$job_name -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    local active=$(kubectl -n $namespace get job/$job_name -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
    
    echo "Job status - Active: ${active:-0}, Succeeded: ${succeeded:-0}, Failed: ${failed:-0} (elapsed: ${elapsed_time}s)"
    
    if [ "${succeeded:-0}" -ge 1 ]; then
      echo "Job $job_name completed successfully!"
      return 0
    fi
    
    if [ "${failed:-0}" -ge 1 ]; then
      echo "ERROR: Job $job_name failed!"
      kubectl -n $namespace describe job/$job_name
      echo "(Job logs suppressed - check S3 onboarder bucket for reports)"
      return 1
    fi
    
    sleep 5
  done
}

function postinstall_demo_oidc_partner_onboarder() {
  echo "=============================================="
  echo "Post-install setup for esignet-demo-oidc-partner-onboarder"
  echo "=============================================="

  # Wait for job completion with status monitoring
  if ! wait_for_job_status "$JOB_NAME" "$NS" 300; then
    echo "ERROR: Job completion failed"
    return 1
  fi

  # Extract private and public key pair from job logs
  echo "Extracting private and public key pair from job logs..."
  PRIVATE_PUBLIC_KEY_PAIR=$(kubectl logs -n $NS job/$JOB_NAME | \
    grep -Pzo "(?s)Private and Public KeyPair:\s*\K.*?(?=\s*mpartner default demo OIDC clientId:)" | \
    tr -d '\0' | tr -d '\n' || echo "")

  if [ -z "$PRIVATE_PUBLIC_KEY_PAIR" ]; then
    echo "WARNING: Could not extract private/public key pair from job logs"
    echo "(Job logs suppressed - check S3 onboarder bucket for reports)"
  else
    echo "Extracted private/public key pair successfully"
    
    # Update mock-relying-party-service-secrets with the new key pair
    echo "Updating mock-relying-party-service-secrets..."
    ENCODED_KEY=$(echo -n "$PRIVATE_PUBLIC_KEY_PAIR" | base64 | tr -d '\n')
    
    if kubectl get secret mock-relying-party-service-secrets -n $NS &>/dev/null; then
      kubectl patch secret mock-relying-party-service-secrets -n $NS \
        -p "{\"data\":{\"client-private-key\":\"$ENCODED_KEY\"}}"
      echo "Secret mock-relying-party-service-secrets patched successfully"
    else
      echo "Creating mock-relying-party-service-secrets..."
      kubectl create secret generic mock-relying-party-service-secrets \
        --from-literal=client-private-key="$PRIVATE_PUBLIC_KEY_PAIR" \
        -n $NS
    fi
    
    # Restart mock-relying-party-service deployment to pick up new secret
    echo "Restarting mock-relying-party-service deployment..."
    kubectl rollout restart deployment/mock-relying-party-service -n $NS || \
      echo "mock-relying-party-service deployment not found, skipping restart"
  fi

  # Extract demo OIDC client ID from job logs
  echo "Extracting demo OIDC client ID from job logs..."
  DEMO_OIDC_CLIENT_ID=$(kubectl logs -n $NS job/$JOB_NAME | \
    grep "mpartner default demo OIDC clientId:" | \
    awk '{sub("clientId:", ""); print $5}' || echo "")

  if [ -z "$DEMO_OIDC_CLIENT_ID" ]; then
    echo "WARNING: Could not extract demo OIDC client ID from job logs"
  else
    echo "Extracted demo OIDC client ID: $DEMO_OIDC_CLIENT_ID"
    
    # Update mock-relying-party-ui deployment with CLIENT_ID environment variable
    echo "Updating mock-relying-party-ui deployment with CLIENT_ID..."
    kubectl -n $NS set env deployment/mock-relying-party-ui CLIENT_ID="$DEMO_OIDC_CLIENT_ID" || \
      echo "mock-relying-party-ui deployment not found, skipping env update"
  fi

  echo "Reports are available in S3 under onboarder bucket"
  echo "Demo OIDC partner onboarder post-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
postinstall_demo_oidc_partner_onboarder   # calling function
