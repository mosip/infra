#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Config-Server eSignet Pre-install
# =============================================================================
# Based on: esignet/deploy/config-server/install.sh
#
# Prepares esignet namespace for config-server deployment:
#   1. Ensures namespace exists with Istio injection enabled
#   2. Copies db-common-secrets from postgres ns
#   3. Creates esignet-domain-config ConfigMap from workflow env vars
#      (domain_name set by helmsman_esignet.yml; available as shell env var
#      in all hooks run within the same workflow step)
#   4. Pre-creates empty esignet-misp-onboarder-key secret as placeholder
#      (MISP onboarder at priority -6 writes the real key; config-server is
#      restarted by esignet-misp-onboarder-postinstall.sh afterwards)
#
# NOTE: esignet-softhsm secret is NOT copied here — the softhsm helm chart
# installs directly into the esignet namespace, so no cross-namespace copy needed.
#
# NOTE: keycloak resources (keycloak-host, keycloak-env-vars, keycloak,
# keycloak-client-secrets) are NOT copied here. They are populated in all
# esignet namespaces by esignet-postinstall-keycloak-init.sh which runs as
# part of external-dsf (esignet-keycloak-init at priority -11 in keycloak ns).
# By the time esignet-dsf runs, these resources are already present.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
#   domain_name  - base domain (set by workflow, e.g. sandbox.example.net)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
POSTGRES_NS="postgres"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Config-Server eSignet Pre-install"
echo "================================================"

# --- Step 1: Ensure namespace with Istio ---
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Copy db-common-secrets ---
# NOTE: esignet-softhsm secret is NOT copied here — the softhsm helm chart
# creates it directly in the esignet namespace as a helm-managed resource.
echo "Copying db-common-secrets from $POSTGRES_NS"
$COPY_UTIL secret db-common-secrets "$POSTGRES_NS" "$ESIGNET_NS"

# --- Step 3: Create esignet-domain-config from workflow env vars ---
# domain_name is exported by the helmsman_esignet.yml workflow step
echo "Creating esignet-domain-config configmap (domain_name=${domain_name:-UNSET})"
kubectl -n "$ESIGNET_NS" create configmap esignet-domain-config \
  --from-literal=installation-domain="${domain_name}" \
  --from-literal=mosip-api-host="api.${domain_name}" \
  --from-literal=mosip-api-internal-host="api-internal.${domain_name}" \
  --from-literal=mosip-esignet-host="esignet.${domain_name}" \
  --from-literal=mosip-iam-external-host="iam.${domain_name}" \
  --from-literal=mosip-kafka-host="kafka.${domain_name}" \
  --from-literal=mosip-postgres-host="postgres.${domain_name}" \
  --from-literal=mosip-signup-host="signup.${domain_name}" \
  --from-literal=mosip-smtp-host="smtp.${domain_name}" \
  --from-literal=mosip-version="develop" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "esignet-domain-config created/updated."

# --- Step 4: Pre-create empty MISP key secret as placeholder ---
# Allows config-server pod to start. Real value written by MISP onboarder (-6).
# esignet-misp-onboarder-postinstall.sh restarts config-server after writing.
if ! kubectl -n "$ESIGNET_NS" get secret esignet-misp-onboarder-key &>/dev/null; then
  kubectl -n "$ESIGNET_NS" create secret generic esignet-misp-onboarder-key \
    --from-literal=mosip-esignet-misp-key=""
  echo "esignet-misp-onboarder-key placeholder created."
else
  echo "esignet-misp-onboarder-key already exists, skipping placeholder."
fi

echo "Config-server eSignet pre-install completed."
