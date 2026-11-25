#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - esignet-apitestrig conformance plan Secret
# =============================================================================
# Usage: apitestrig-conformance-plan.sh <namespace> <ENV_PREFIX>
#
# Creates/updates Secret `esignet-conformance-plan` in <namespace> with the two
# OpenID Conformance Suite plan files the `conformance` surface reads
# (apitestrig.conformancePlanConfig.existingSecret in testrigs-dsf.yaml):
#
#   esignet-config.json        <- $<ENV_PREFIX>_CONFORMANCE_PLAN
#   esignet-fapi2-config.json  <- $<ENV_PREFIX>_CONFORMANCE_PLAN_FAPI2
#
# Each plan holds the instance's discovery URL, client IDs and a PRIVATE JWKS,
# so it is a per-instance GitHub Environment Secret, never a DSF value.
# Values are written via temp files (not argv) and never echoed.
#
# Unset (or UPDATE_BEFORE_RUN) -> the value already in the cluster Secret is
# kept, so a plan the team updated directly on the cluster survives re-deploys.
# If there is none yet, a dummy plan {"alias":"UPDATE_BEFORE_RUN"} is written so
# the testrig still deploys; only the conformance surface fails until the team
# replaces it. If the Secret cannot be read, the hook fails without writing.
#
# When does a plan change reach the cluster? This runs as preInstall /
# preUpgrade, i.e. only when Helmsman installs or upgrades the apitestrig
# release (new install, chart version or values change). Changing only the
# GitHub secret and re-running Helmsman does NOT trigger it. To refresh a plan
# without a chart change, edit the cluster Secret directly.
# =============================================================================
set -euo pipefail

NS="${1:?namespace required}"
PREFIX="${2:?env prefix required}"
SECRET=esignet-conformance-plan

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

write_plan() {
  local var="$1" file="$2" value
  value="${!var:-}"
  if [ -z "$value" ] || [ "$value" = "UPDATE_BEFORE_RUN" ]; then
    # A read / decode failure must not fall through to the dummy plan, or a
    # transient API error would overwrite the in-cluster plan (private JWKS).
    # Only a missing Secret or a missing key selects the dummy.
    local stored
    if ! stored=$(kubectl -n "$NS" get secret "$SECRET" --ignore-not-found -o json); then
      echo "ERROR: cannot read $NS/$SECRET - leaving it unchanged." >&2
      exit 1
    fi
    if ! value=$(printf '%s' "$stored" | jq -r --arg key "$file" 'if . == null then empty else (.data[$key] // empty) end' | base64 -d); then
      echo "ERROR: cannot decode $NS/$SECRET:$file - leaving it unchanged." >&2
      exit 1
    fi
    if [ -n "$value" ]; then
      echo "$var is not set - keeping the existing $NS/$SECRET:$file." >&2
    else
      echo "WARNING: $var is not set - writing a dummy plan to $NS/$SECRET:$file." >&2
      echo "         Update it before running the conformance surface." >&2
      value='{"alias":"UPDATE_BEFORE_RUN"}'
    fi
  fi
  if ! printf '%s' "$value" | jq -se 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
    echo "ERROR: $var is not a single JSON object - refusing to create $NS/$SECRET." >&2
    exit 1
  fi
  printf '%s' "$value" > "$TMP/$file"
}

write_plan "${PREFIX}_CONFORMANCE_PLAN"       esignet-config.json
write_plan "${PREFIX}_CONFORMANCE_PLAN_FAPI2" esignet-fapi2-config.json

kubectl -n "$NS" create secret generic "$SECRET" \
  --from-file=esignet-config.json="$TMP/esignet-config.json" \
  --from-file=esignet-fapi2-config.json="$TMP/esignet-fapi2-config.json" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Secret $NS/$SECRET is up to date"
