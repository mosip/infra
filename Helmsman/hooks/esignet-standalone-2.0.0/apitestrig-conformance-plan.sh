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
# Unset -> the key is written as `{}` with a warning, so the testrig still
# deploys (same as the UPDATE_BEFORE_RUN placeholders); only the conformance
# surface fails until the real plan is set and the workflow is re-run.
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
    echo "WARNING: $var is not set - writing an empty plan to $NS/$SECRET:$file." >&2
    echo "         The conformance surface will fail until it is set and testrigs are re-deployed." >&2
    value='{}'
  fi
  if ! printf '%s' "$value" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERROR: $var is not a JSON object - refusing to create $NS/$SECRET." >&2
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
