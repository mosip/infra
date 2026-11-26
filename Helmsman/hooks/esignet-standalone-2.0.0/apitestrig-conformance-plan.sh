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
# The cluster Secret is the source of truth once it holds a real plan:
#   1. cluster has a real plan          -> kept (a differing GitHub value is
#                                          ignored, with a warning)
#   2. else GitHub secret is set        -> written (seeds the cluster)
#   3. else                             -> dummy {"alias":"UPDATE_BEFORE_RUN"},
#                                          so the testrig still deploys and only
#                                          the conformance surface fails
# So a plan edited on the cluster is never overwritten. To re-seed from GitHub,
# delete that key (or the Secret) and re-deploy. If the Secret cannot be read,
# the hook fails without writing.
#
# This runs as preInstall / preUpgrade, i.e. only when Helmsman installs or
# upgrades the apitestrig release (new install, chart version or values change).
# =============================================================================
set -euo pipefail

NS="${1:?namespace required}"
PREFIX="${2:?env prefix required}"
SECRET=esignet-conformance-plan
DUMMY='{"alias":"UPDATE_BEFORE_RUN"}'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

# Read once. A read failure must not fall through to the dummy plan, or a
# transient API error would overwrite the in-cluster plan (private JWKS).
if ! STORED=$(kubectl -n "$NS" get secret "$SECRET" --ignore-not-found -o json); then
  echo "ERROR: cannot read $NS/$SECRET - leaving it unchanged." >&2
  exit 1
fi

write_plan() {
  local var="$1" file="$2" gh cluster value
  gh="${!var:-}"
  [ "$gh" = "UPDATE_BEFORE_RUN" ] && gh=""
  if ! cluster=$(printf '%s' "$STORED" | jq -r --arg key "$file" 'if . == null then empty else (.data[$key] // empty) end' | base64 -d); then
    echo "ERROR: cannot decode $NS/$SECRET:$file - leaving it unchanged." >&2
    exit 1
  fi

  if [ -n "$cluster" ] && [ "$cluster" != "$DUMMY" ]; then
    value="$cluster"
    if [ -n "$gh" ] && [ "$gh" != "$cluster" ]; then
      echo "WARNING: $var differs from $NS/$SECRET:$file - keeping the cluster plan." >&2
      echo "         To use the GitHub value, delete that key (or the Secret) and re-deploy." >&2
    else
      echo "Keeping the existing $NS/$SECRET:$file." >&2
    fi
  elif [ -n "$gh" ]; then
    value="$gh"
    echo "Writing $NS/$SECRET:$file from $var." >&2
  else
    value="$DUMMY"
    echo "WARNING: $var is not set - writing a dummy plan to $NS/$SECRET:$file." >&2
    echo "         Update it before running the conformance surface." >&2
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
  --dry-run=client -o yaml > "$TMP/secret.yaml"

# create / replace, not `kubectl apply`: apply would copy the whole Secret,
# private JWKS included, into the last-applied-configuration annotation that
# `kubectl describe` prints. replace also drops that annotation if an earlier
# apply left it behind.
if [ -n "$STORED" ]; then
  kubectl -n "$NS" replace -f "$TMP/secret.yaml" >/dev/null
else
  kubectl -n "$NS" create -f "$TMP/secret.yaml" >/dev/null
fi

echo "Secret $NS/$SECRET is up to date"
