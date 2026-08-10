#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - Notifier Post-install
# =============================================================================
# Based on: esignet-signup/deploy/kernel/install.sh
# Patches notifier deployment with SMS number length env vars after install.
# =============================================================================
set -euo pipefail

KERNEL_NS="kernel-go"

echo "================================================"
echo "eSignet Standalone 2.0.0 - Notifier Post-install"
echo "================================================"

# Source: deploy/kernel/install.sh - kubectl set env deployment/notifier
echo "Setting SMS number length env vars on notifier-go deployment"
kubectl -n "$KERNEL_NS" set env deployment/notifier-go \
  MOSIP_KERNEL_SMS_NUMBER_MIN_LENGTH=7 \
  MOSIP_KERNEL_SMS_NUMBER_MAX_LENGTH=10

echo "Notifier post-install completed."
