#!/bin/bash
# Prefer the terraform-generated kubeconfig committed after infra apply.
# Fall back to the KUBECONFIG_CONTENT environment variable (GitHub environment secret).
#
# After terraform destroy + apply the cluster API IP changes, but the KUBECONFIG
# environment secret is often left pointing at the old node. The file written to
# terraform/implementations/<cloud>/infra/*-CONTROL-PLANE-NODE-1.yaml is the
# current cluster.
#
# Usage:
#   KUBECONFIG_CONTENT="$SECRET" ./resolve-kubeconfig.sh <dest> [search-root]

set -euo pipefail

SCRIPT_NAME="resolve-kubeconfig.sh"
DEST="${1:-}"
SEARCH_ROOT="${2:-${GITHUB_WORKSPACE:-.}}"

if [ -z "$DEST" ]; then
  echo "[$SCRIPT_NAME] Usage: $0 <destination-kubeconfig> [search-root]"
  exit 1
fi

mkdir -p "$(dirname "$DEST")"

find_repo_kubeconfig() {
  local root="$1"
  local found=""

  if [ -d "$root/terraform/implementations" ]; then
    found=$(find "$root/terraform/implementations" \
      -path '*/infra/*CONTROL-PLANE-NODE-1.yaml' -type f \
      -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || true)
    if [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
  fi

  # Terraform apply runs from implementations/<cloud>/infra — look in cwd too
  found=$(find "$root" -maxdepth 1 -name '*CONTROL-PLANE-NODE-1.yaml' -type f 2>/dev/null | head -1 || true)
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  return 1
}

REPO_KUBECONFIG=""
if REPO_KUBECONFIG=$(find_repo_kubeconfig "$SEARCH_ROOT"); then
  echo "[$SCRIPT_NAME] Using terraform-generated kubeconfig: $REPO_KUBECONFIG"
  cp "$REPO_KUBECONFIG" "$DEST"
elif [ -n "${KUBECONFIG_CONTENT:-}" ]; then
  echo "[$SCRIPT_NAME] No terraform kubeconfig in repo; using KUBECONFIG environment secret"
  printf '%s\n' "$KUBECONFIG_CONTENT" > "$DEST"
else
  echo "[$SCRIPT_NAME] ❌ No kubeconfig found."
  echo "Deploy infra first (terraform apply writes *-CONTROL-PLANE-NODE-1.yaml),"
  echo "or set the KUBECONFIG environment secret for branch '${GITHUB_REF_NAME:-unknown}'."
  exit 1
fi

chmod 400 "$DEST"

API_SERVER=$(grep -E '^\s+server:' "$DEST" | head -1 | awk '{print $2}' || true)
echo "[$SCRIPT_NAME] Kubernetes API server: ${API_SERVER:-unknown}"
