#!/bin/bash
set -e
SMTP_PASS="$1"

kubectl create secret generic alertmanager-smtp -n monitoring \
  --from-literal=password="$SMTP_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
