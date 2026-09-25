#!/bin/bash
# Pre-install hook for esignet-keycloak-init (eSignet 1.7.1 standalone)
# Runs in the keycloak namespace — all required resources (keycloak secret,
# keycloak-env-vars CM) are already present from the bitnami keycloak chart.
# The chart creates keycloak-host CM and keycloak-client-secrets in keycloak ns.
# We clean up the previous release and chart-managed resources so the fresh
# helm install can recreate them cleanly.
set -euo pipefail

KEYCLOAK_NS="keycloak"

echo "================================================"
echo "eSignet 1.7.1 - Keycloak Init Pre-install"
echo "================================================"

# Delete previous releases so helm install starts fresh.
# keycloak-host CM and keycloak-client-secrets secret are helm-managed — helm delete
# removes them automatically; no manual kubectl delete needed here.
helm -n "$KEYCLOAK_NS" delete esignet-keycloak-init 2>/dev/null || true
# Migration: remove old release from esignet ns if it was deployed there previously
helm -n esignet delete esignet-keycloak-init 2>/dev/null || true

# Fetch existing client secrets from keycloak namespace for DSF ${VAR} substitution.
# Empty on fresh install — helm chart generates them; existing values preserved on re-run.
PMS_CLIENT_SECRET_KEY="mosip_pms_client_secret"
MPARTNER_DEFAULT_AUTH_SECRET_KEY="mpartner_default_auth_secret"
IDA_CLIENT_SECRET_KEY="mosip_ida_client_secret"
DEPLOYMENT_CLIENT_SECRET_KEY="mosip_deployment_client_secret"
MPARTNER_DEFAULT_MOBILE_SECRET_KEY="mpartner_default_mobile_secret"

PMS_CLIENT_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${PMS_CLIENT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export PMS_CLIENT_SECRET_KEY PMS_CLIENT_SECRET_VALUE

MPARTNER_DEFAULT_AUTH_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${MPARTNER_DEFAULT_AUTH_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export MPARTNER_DEFAULT_AUTH_SECRET_KEY MPARTNER_DEFAULT_AUTH_SECRET_VALUE

IDA_CLIENT_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${IDA_CLIENT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export IDA_CLIENT_SECRET_KEY IDA_CLIENT_SECRET_VALUE

DEPLOYMENT_CLIENT_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${DEPLOYMENT_CLIENT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export DEPLOYMENT_CLIENT_SECRET_KEY DEPLOYMENT_CLIENT_SECRET_VALUE

MPARTNER_DEFAULT_MOBILE_SECRET_VALUE="$(kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets \
  -o jsonpath="{.data.${MPARTNER_DEFAULT_MOBILE_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || echo "")"
export MPARTNER_DEFAULT_MOBILE_SECRET_KEY MPARTNER_DEFAULT_MOBILE_SECRET_VALUE

echo "Pre-install setup complete. Helmsman will now deploy esignet-keycloak-init chart."
