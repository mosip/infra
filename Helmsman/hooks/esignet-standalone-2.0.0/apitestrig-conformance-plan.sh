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
#                                          ignored, with a warning; an invalid
#                                          cluster value is replaced)
#   2. else GitHub secret is set        -> written (seeds the cluster)
#   3. else                             -> dummy {"alias":"UPDATE_BEFORE_RUN"},
#                                          so the testrig still deploys and only
#                                          the conformance surface fails
# So a plan edited on the cluster is never overwritten. To change a plan,
# replace the Secret by hand (see docs/HELMSMAN_TESTRIGS_GUIDE.md); deleting it
# and re-deploying does NOT work, because Helmsman skips an unchanged release
# and this hook then never runs. If the Secret cannot be read, the hook fails
# without writing.
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
# Kept in a 0600 file under $TMP so it never goes on a command line.
if ! STORED=$(kubectl -n "$NS" get secret "$SECRET" --ignore-not-found -o json); then
  echo "ERROR: cannot read $NS/$SECRET - leaving it unchanged." >&2
  exit 1
fi
(umask 077; printf '%s' "${STORED:-null}" > "$TMP/old.json")

# Single JSON object -> its canonical form (jq -cS), so formatting / trailing
# newline differences don't count as a change. Fails on anything else.
canon() { printf '%s' "$1" | jq -cSe -s 'if length == 1 and (.[0] | type == "object") then .[0] else error("not a single object") end' 2>/dev/null; }

CHANGED=false
write_plan() {
  local var="$1" file="$2" gh cluster ccl cgh value
  gh="${!var:-}"
  [ "$gh" = "UPDATE_BEFORE_RUN" ] && gh=""
  if ! cluster=$(printf '%s' "$STORED" | jq -r --arg key "$file" 'if . == null then empty else (.data[$key] // empty) end' | base64 -d); then
    echo "ERROR: cannot decode $NS/$SECRET:$file - leaving it unchanged." >&2
    exit 1
  fi
  ccl=""; cgh=""
  if [ -n "$cluster" ] && ! ccl=$(canon "$cluster"); then
    echo "WARNING: $NS/$SECRET:$file on the cluster is not a single JSON object - replacing it." >&2
    ccl=""
  fi
  if [ -n "$gh" ] && ! cgh=$(canon "$gh"); then
    echo "ERROR: GitHub secret $var is not a single JSON object - refusing to update $NS/$SECRET." >&2
    exit 1
  fi

  if [ -n "$ccl" ] && [ "$ccl" != "$(canon "$DUMMY")" ]; then
    value="$ccl"
    if [ -n "$cgh" ] && [ "$cgh" != "$ccl" ]; then
      echo "WARNING: $var differs from $NS/$SECRET:$file - keeping the cluster plan." >&2
      echo "         To use the GitHub value, replace the Secret by hand (see docs/HELMSMAN_TESTRIGS_GUIDE.md)." >&2
    else
      echo "Keeping the existing $NS/$SECRET:$file." >&2
    fi
  elif [ -n "$cgh" ]; then
    value="$cgh"
    echo "Writing $NS/$SECRET:$file from $var." >&2
  else
    value=$(canon "$DUMMY")
    echo "WARNING: $var is not set - writing a dummy plan to $NS/$SECRET:$file." >&2
    echo "         Update it before running the conformance surface." >&2
  fi

  # Keep the stored bytes when the plan is unchanged.
  if [ -n "$ccl" ] && [ "$value" = "$ccl" ]; then
    printf '%s' "$cluster" > "$TMP/$file"
  else
    printf '%s' "$value" > "$TMP/$file"
    CHANGED=true
  fi
}

write_plan "${PREFIX}_CONFORMANCE_PLAN"       esignet-config.json
write_plan "${PREFIX}_CONFORMANCE_PLAN_FAPI2" esignet-fapi2-config.json

# Earlier versions of this hook used `kubectl apply`, which left both plans
# (private JWKS included) in the last-applied-configuration annotation. Rewrite
# the Secret once so the replace below drops it, even if the plans are unchanged.
if jq -e '.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"] != null' "$TMP/old.json" >/dev/null 2>&1; then
  echo "Removing the last-applied-configuration annotation from $NS/$SECRET." >&2
  CHANGED=true
fi

if [ -n "$STORED" ] && [ "$CHANGED" = false ]; then
  echo "Secret $NS/$SECRET is unchanged"
  exit 0
fi

kubectl -n "$NS" create secret generic "$SECRET" \
  --from-file=esignet-config.json="$TMP/esignet-config.json" \
  --from-file=esignet-fapi2-config.json="$TMP/esignet-fapi2-config.json" \
  --dry-run=client -o json > "$TMP/new.json"

# create / replace, not `kubectl apply`: apply would copy the whole Secret,
# private JWKS included, into the last-applied-configuration annotation that
# `kubectl describe` prints. On replace, labels and annotations added outside
# this hook are carried over (minus any last-applied annotation an earlier
# apply left behind), and the resourceVersion that was read is sent, so a
# Secret edited while this hook ran is not overwritten (the replace fails).
if [ -n "$STORED" ]; then
  jq --slurpfile old "$TMP/old.json" '
    $old[0] as $o
    | .metadata.resourceVersion = $o.metadata.resourceVersion
    | .metadata.labels = ($o.metadata.labels // {})
    | .metadata.annotations = (($o.metadata.annotations // {})
        | del(.["kubectl.kubernetes.io/last-applied-configuration"]))
  ' "$TMP/new.json" > "$TMP/secret.json"
  if ! kubectl -n "$NS" replace -f "$TMP/secret.json" >/dev/null; then
    echo "ERROR: could not replace $NS/$SECRET (changed while this hook ran?) - re-run the deployment." >&2
    exit 1
  fi
else
  kubectl -n "$NS" create -f "$TMP/new.json" >/dev/null
fi

echo "Secret $NS/$SECRET is up to date"
