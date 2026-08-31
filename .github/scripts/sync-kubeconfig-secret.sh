#!/bin/bash
# Update the KUBECONFIG GitHub environment secret from a kubeconfig file.
# Called after terraform apply so Helmsman workflows that still read the secret
# do not keep targeting a destroyed control-plane IP.
#
# Usage:
#   GH_TOKEN=... ENVIRONMENT=<branch> ./sync-kubeconfig-secret.sh <kubeconfig-file>

set -euo pipefail

SCRIPT_NAME="sync-kubeconfig-secret.sh"
FILE="${1:-}"
ENVIRONMENT="${ENVIRONMENT:-${GITHUB_REF_NAME:-}}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "[$SCRIPT_NAME] ❌ kubeconfig file not found: ${FILE:-<missing>}"
  exit 1
fi

if [ -z "$ENVIRONMENT" ]; then
  echo "[$SCRIPT_NAME] ❌ ENVIRONMENT or GITHUB_REF_NAME is required"
  exit 1
fi

if [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  echo "[$SCRIPT_NAME] ❌ GH_TOKEN is required to update environment secrets"
  exit 1
fi

export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

API_SERVER=$(grep -E '^\s+server:' "$FILE" | head -1 | awk '{print $2}' || true)
echo "[$SCRIPT_NAME] Syncing KUBECONFIG secret for environment '$ENVIRONMENT'"
echo "[$SCRIPT_NAME] API server: ${API_SERVER:-unknown}"

gh secret set KUBECONFIG --env "$ENVIRONMENT" < "$FILE"
echo "[$SCRIPT_NAME] ✅ KUBECONFIG environment secret updated"
