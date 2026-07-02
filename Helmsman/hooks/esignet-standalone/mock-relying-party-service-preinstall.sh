#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service Pre-install
# =============================================================================
# Creates K8s secrets for mock relying party private keys from GitHub Actions
# environment secrets, then verifies the esignet service is running.
#
# Required env vars (set in workflow env: block from GitHub Actions secrets):
#   MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY — base64-encoded PEM client private key
#   MOCK_RELYING_PARTY_JWE_PRIVATE_KEY    — base64-encoded PEM JWE userinfo private key
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"

CLIENT_KEY_TMPFILE=""
JWE_KEY_TMPFILE=""

cleanup_temp_files() {
  [ -n "$CLIENT_KEY_TMPFILE" ] && [ -f "$CLIENT_KEY_TMPFILE" ] && \
    { shred -u "$CLIENT_KEY_TMPFILE" 2>/dev/null || rm -f "$CLIENT_KEY_TMPFILE"; }
  [ -n "$JWE_KEY_TMPFILE" ] && [ -f "$JWE_KEY_TMPFILE" ] && \
    { shred -u "$JWE_KEY_TMPFILE" 2>/dev/null || rm -f "$JWE_KEY_TMPFILE"; }
}
trap cleanup_temp_files EXIT INT TERM

echo "================================================"
echo "eSignet 1.7.1 - Mock Relying Party Service Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Create mock-relying-party-private-key-jwk (client private key)
EXISTING=$(kubectl -n "$ESIGNET_NS" get secret mock-relying-party-private-key-jwk \
  -o jsonpath='{.data.client-private-key}' 2>/dev/null || echo "")
if [ -z "$EXISTING" ]; then
  if [ -n "${MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY:-}" ]; then
    CLIENT_KEY_TMPFILE=$(mktemp)
    chmod 600 "$CLIENT_KEY_TMPFILE"
    echo "$MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY" | base64 -d | sed "s/'//g" | sed -z 's/\n/\\n/g' > "$CLIENT_KEY_TMPFILE"
    kubectl -n "$ESIGNET_NS" delete secret mock-relying-party-private-key-jwk --ignore-not-found=true
    kubectl -n "$ESIGNET_NS" create secret generic mock-relying-party-private-key-jwk \
      --from-file=client-private-key="$CLIENT_KEY_TMPFILE"
    echo "mock-relying-party-private-key-jwk created."
  else
    echo "ERROR: MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY is not set." >&2
    exit 1
  fi
else
  echo "mock-relying-party-private-key-jwk already exists, skipping."
fi

# Create jwe-userinfo-service-secrets (JWE userinfo private key)
EXISTING=$(kubectl -n "$ESIGNET_NS" get secret jwe-userinfo-service-secrets \
  -o jsonpath='{.data.jwe-userinfo-private-key}' 2>/dev/null || echo "")
if [ -z "$EXISTING" ]; then
  if [ -n "${MOCK_RELYING_PARTY_JWE_PRIVATE_KEY:-}" ]; then
    JWE_KEY_TMPFILE=$(mktemp)
    chmod 600 "$JWE_KEY_TMPFILE"
    echo "$MOCK_RELYING_PARTY_JWE_PRIVATE_KEY" | base64 -d | sed "s/'//g" | sed -z 's/\n/\\n/g' > "$JWE_KEY_TMPFILE"
    kubectl -n "$ESIGNET_NS" delete secret jwe-userinfo-service-secrets --ignore-not-found=true
    kubectl -n "$ESIGNET_NS" create secret generic jwe-userinfo-service-secrets \
      --from-file=jwe-userinfo-private-key="$JWE_KEY_TMPFILE"
    echo "jwe-userinfo-service-secrets created."
  else
    echo "ERROR: MOCK_RELYING_PARTY_JWE_PRIVATE_KEY is not set." >&2
    exit 1
  fi
else
  echo "jwe-userinfo-service-secrets already exists, skipping."
fi

echo "Mock relying party service pre-install completed."
