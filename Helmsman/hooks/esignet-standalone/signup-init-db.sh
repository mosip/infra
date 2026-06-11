#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Signup Service DB Init Pre-install
# =============================================================================
# Based on: esignet-signup/deploy/postgres-init.sh
# Creates signup namespace and copies postgres secrets before
# the postgres-init helm chart runs DB initialization for
# mosip_audit, mosip_kernel, and mosip_otp.
#
# Environment Variables:
#   SIGNUP_NS - Signup namespace (default: signup)
# =============================================================================
set -euo pipefail

SIGNUP_NS="${SIGNUP_NS:-signup}"
POSTGRES_NS="postgres"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Signup DB Init Pre-install"
echo "================================================"

# --- Step 1: Ensure signup namespace exists with istio ---
kubectl create namespace "$SIGNUP_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$SIGNUP_NS" istio-injection=enabled --overwrite

# --- Step 2: Copy postgres-postgresql secret to signup namespace ---
echo "Copying postgres-postgresql secret to $SIGNUP_NS namespace"
$COPY_UTIL secret postgres-postgresql "$POSTGRES_NS" "$SIGNUP_NS"

echo "Signup DB init pre-install completed."
