#!/bin/bash
set -e
kubectl create secret generic alertmanager-smtp -n monitoring \
  --from-literal=password="${SMTP_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
