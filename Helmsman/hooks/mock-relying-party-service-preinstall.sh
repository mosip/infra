#!/bin/bash
# Pre-install hook for mock-relying-party-service
# This script copies configmaps and creates secrets for private keys
# This script is IDEMPOTENT
#
# Required GitHub Actions Secrets (passed as environment variables):
#   - MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY: Client private key (PEM format, base64 encoded)
#   - MOCK_RELYING_PARTY_JWE_PRIVATE_KEY: JWE userinfo private key (PEM format, base64 encoded)
#
# Example GitHub Actions workflow usage:
#   env:
#     MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY: ${{ secrets.MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY }}
#     MOCK_RELYING_PARTY_JWE_PRIVATE_KEY: ${{ secrets.MOCK_RELYING_PARTY_JWE_PRIVATE_KEY }}
#
## Usage: ./mock-relying-party-service-preinstall.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
COPY_UTIL=$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh

function preinstall_mock_relying_party_service() {
  echo "Pre-install setup for mock-relying-party-service"

  # Create namespace if not exists
  kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f -

  # Add Istio label
  echo "Adding Istio injection label to $NS namespace"
  kubectl label ns $NS istio-injection=enabled --overwrite

  # Copy configmaps
  echo "Copying configmaps to $NS namespace"
  $COPY_UTIL configmap global default $NS
  $COPY_UTIL configmap config-server-share config-server $NS 2>/dev/null || echo "config-server-share configmap not found, skipping"
  $COPY_UTIL configmap artifactory-share artifactory $NS 2>/dev/null || echo "artifactory-share configmap not found, skipping"
  $COPY_UTIL configmap softhsm-mock-identity-system-share softhsm $NS 2>/dev/null || echo "softhsm-mock-identity-system-share configmap not found, skipping"

  # Check and create mock-relying-party-service-secrets (idempotent)
  echo "Setting up mock-relying-party-service-secrets"
  EXISTING_CLIENT_SECRET=$( kubectl -n $NS get secret mock-relying-party-service-secrets -o jsonpath='{.data.client-private-key}' 2>/dev/null || echo "" )
  
  if [ -z "$EXISTING_CLIENT_SECRET" ]; then
    # Check if GitHub Actions secret is provided as environment variable
    if [ -n "${MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY:-}" ]; then
      echo "Creating mock-relying-party-service-secrets from GitHub Actions secret"
      # Decode base64 and process the key - remove quotes and convert newlines
      echo "$MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY" | base64 -d | sed "s/'//g" | sed -z 's/\n/\\n/g' > /tmp/client-private-key
      kubectl -n $NS delete secret mock-relying-party-service-secrets --ignore-not-found=true
      kubectl -n $NS create secret generic mock-relying-party-service-secrets --from-file=client-private-key=/tmp/client-private-key
      rm -f /tmp/client-private-key
    else
      echo "WARNING: MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY environment variable not set"
      echo "Please configure this as a GitHub Actions secret (base64 encoded PEM)"
      echo "  Example: echo -n '<pem-content>' | base64 > encoded_key"
    fi
  else
    echo "mock-relying-party-service-secrets already exists, skipping"
  fi

  # Check and create jwe-userinfo-service-secrets (idempotent)
  echo "Setting up jwe-userinfo-service-secrets"
  EXISTING_JWE_SECRET=$( kubectl -n $NS get secret jwe-userinfo-service-secrets -o jsonpath='{.data.jwe-userinfo-private-key}' 2>/dev/null || echo "" )
  
  if [ -z "$EXISTING_JWE_SECRET" ]; then
    # Check if GitHub Actions secret is provided as environment variable
    if [ -n "${MOCK_RELYING_PARTY_JWE_PRIVATE_KEY:-}" ]; then
      echo "Creating jwe-userinfo-service-secrets from GitHub Actions secret"
      # Decode base64 and process the key - remove quotes and convert newlines
      echo "$MOCK_RELYING_PARTY_JWE_PRIVATE_KEY" | base64 -d | sed "s/'//g" | sed -z 's/\n/\\n/g' > /tmp/jwe-userinfo-private-key
      kubectl -n $NS delete secret jwe-userinfo-service-secrets --ignore-not-found=true
      kubectl -n $NS create secret generic jwe-userinfo-service-secrets --from-file=jwe-userinfo-private-key=/tmp/jwe-userinfo-private-key
      rm -f /tmp/jwe-userinfo-private-key
    else
      echo "WARNING: MOCK_RELYING_PARTY_JWE_PRIVATE_KEY environment variable not set"
      echo "Please configure this as a GitHub Actions secret (base64 encoded PEM)"
      echo "  Example: echo -n '<pem-content>' | base64 > encoded_key"
    fi
  else
    echo "jwe-userinfo-service-secrets already exists, skipping"
  fi

  echo "mock-relying-party-service pre-install setup complete"
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
preinstall_mock_relying_party_service   # calling function
