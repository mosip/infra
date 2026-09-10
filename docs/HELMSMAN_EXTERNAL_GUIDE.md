# Helmsman External Deployment Guide

Deploy prerequisites and external dependencies (databases, queues, storage, monitoring) before any MOSIP or eSignet services.

## Overview

The `helmsman_external.yml` workflow runs **two DSFs in parallel**:

| DSF | Deploys |
|-----|---------|
| `prereq-dsf.yaml` | Rancher monitoring, Elasticsearch, Kibana, Istio, httpbin, global configmap |
| `external-dsf.yaml` | PostgreSQL, Redis, Kafka, SoftHSM, Keycloak, ClamAV, MinIO, ActiveMQ, Captcha |

**Time required:** 20–40 minutes

**Auto-trigger:** On successful completion, this workflow automatically triggers `helmsman_mosip.yml` — but only for MOSIP platform profiles. For the `esignet-standalone` profile, MOSIP is not triggered.

---

## Profile Selection

Choose the profile that matches your deployment target:

| Profile | Use when |
|---------|----------|
| `esignet-standalone` | eSignet standalone — up to 4 parallel instances (esignet-mock, esignet-mosipid1, esignet-mosipid2, esignet-sunbird). mosipid2 is optional via `enable_mosipid2` toggle. No full MOSIP stack. |
| `mosip-platform-1.2.0.x` | Full MOSIP platform with Java 11 |
| `mosip-platform-1.2.1.x` | Full MOSIP platform with Java 21 |

The workflow selects `Helmsman/dsf/<profile>/prereq-dsf.yaml` and `Helmsman/dsf/<profile>/external-dsf.yaml` based on this input.

---

## Required Secrets

All secrets are **Environment Secrets** — configure at **Repository → Settings → Environments → `<branch-name>` → Secrets**.

### All profiles

| Secret | Description |
|--------|-------------|
| `KUBECONFIG` | Raw YAML kubeconfig (not base64 encoded) |
| `CLUSTER_WIREGUARD_WG0` | WireGuard VPN config for cluster access |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (optional — for alerting) |

### eSignet standalone profile only

| Secret | Description |
|--------|-------------|
| `ESIGNET_CAPTCHA_SITE_KEY` | Google reCAPTCHA site key for the main esignet namespace |
| `ESIGNET_CAPTCHA_SECRET_KEY` | Google reCAPTCHA secret key for the main esignet namespace |

> For MOSIP-ID1, MOSIP-ID2, and Sunbird namespace captcha secrets, see [ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md](ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md).

### MOSIP platform profiles only

reCAPTCHA v2 keys for each MOSIP service domain — add as **Environment Secrets**:

| Secret | Domain |
|--------|--------|
| `PREREG_CAPTCHA_SITE_KEY` / `PREREG_CAPTCHA_SECRET_KEY` | `prereg.<your-domain>` |
| `ADMIN_CAPTCHA_SITE_KEY` / `ADMIN_CAPTCHA_SECRET_KEY` | `admin.<your-domain>` |
| `RESIDENT_CAPTCHA_SITE_KEY` / `RESIDENT_CAPTCHA_SECRET_KEY` | `resident.<your-domain>` |

> Get reCAPTCHA keys from [Google reCAPTCHA Admin Console](https://www.google.com/recaptcha/admin/create). Create reCAPTCHA v2 (Invisible) type. See [RECAPTCHA_SETUP_GUIDE.md](RECAPTCHA_SETUP_GUIDE.md) for detailed steps.

---

## Workflow Inputs

| Input | Description | Example |
|-------|-------------|---------|
| `profile` | Deployment profile | `esignet-standalone` / `mosip-platform-1.2.0.x` / `mosip-platform-1.2.1.x` |
| `mode` | Helmsman mode | Always `apply` — dry-run will fail |
| `domain_name` | Base domain for this environment | `soil38.mosip.net` |
| `env_name` | Environment name | `soil38` |
| `clusterid` | Rancher cluster ID (for rancher-monitoring) | `c-m-abc12xyz` |
| `slack_channel_name` | Slack channel for alerting (optional) | `#mosip-alerts` |
| `db_port` | External postgres port — MOSIP platform only | `5433` |
| `esignet_db_port` | eSignet container postgres port | `5432` |

> If not provided as inputs, values fall back to GitHub Environment Variables (`vars.DOMAIN_NAME`, `vars.ENV_NAME`, etc.).

---

## Step-by-Step: Run the Workflow

![Deploy External Services - Helmsman](_images/helmsman-external-services.png)

- **(1)** Go to **Actions** (top of the repository page) → click **"Deploy External services of mosip using Helmsman"** in the list on the left.
  > Can't find it? Search for "External" in the workflows list.
- **(2)** Click the **Run workflow** dropdown button (top right) — this opens the form shown above.
- **(3)** **Branch** — pick the branch you're deploying from (e.g., `MOSIP-44613`).
- **(4)** **Deployment profile to use** — pick the profile you want (e.g., `mosip-platform-1.2.0.x` for full MOSIP, or `esignet-standalone` for eSignet standalone).
- **(5)** **Choose Helmsman mode: dry-run or apply** — always pick **`apply`**. (`dry-run` is not a safe preview here — it will fail because required resources don't exist yet.)
- **(6)** **Domain name for this environment** — type the web domain this environment should use (e.g., `example.xyz.net`).
- **(7)** **PostgreSQL port for MOSIP platform external postgres** — only fill this in if you picked a `mosip-platform-*` profile in step 4. Type `5433` (or whatever port your external PostgreSQL uses).
- **(8)** **PostgreSQL port for esignet standalone container postgres** — only fill this in if you picked the `esignet-standalone` profile in step 4. Type `5432`.
- **(9)** **Environment name** — a short nickname for this environment (e.g., `sandbox`, `dev`, `staging`).
- **(10)** **Slack channel name for alerting** (optional) — the Slack channel that should receive alerts (e.g., `#mosip-alerts`). Leave blank if you don't want Slack alerts.
- **(11)** **Slack webhook URL for alerting** (optional) — leave this blank; it's normally already saved as the `SLACK_WEBHOOK_URL` secret in your GitHub environment.
- **(12)** **Rancher cluster ID for rancher-monitoring** — only needed if your cluster is imported into Rancher (`rancher_import = true` in your Terraform config). Find it in the Rancher URL (looks like `c-m-xxxxx`) or run `kubectl get setting cluster-id -n cattle-system -o jsonpath='{.value}'`.
- **(13)** Click the green **Run workflow** button to start the deployment.

> **Note:** Steps 7 and 8 both always appear in the form regardless of which profile you picked — just fill in the one that matches your profile and leave the other blank.

---

## What Gets Deployed

**prereq-dsf.yaml** (monitoring, mesh, logging):
- ✅ Rancher monitoring stack (Prometheus, Grafana)
- ✅ Istio service mesh
- ✅ Elasticsearch + Kibana (logging)
- ✅ httpbin (health check endpoint)
- ✅ Global configmap

**external-dsf.yaml** (data layer):
- ✅ PostgreSQL (container mode) or external Terraform-provisioned PostgreSQL
- ✅ Redis
- ✅ Kafka + Kafka UI
- ✅ SoftHSM
- ✅ Keycloak + Keycloak init
- ✅ MinIO (object storage)
- ✅ ActiveMQ
- ✅ ClamAV (antivirus)
- ✅ Captcha service

---

## After This Workflow

- **MOSIP platform profiles** → `helmsman_mosip.yml` is auto-triggered. See [HELMSMAN_MOSIP_GUIDE.md](HELMSMAN_MOSIP_GUIDE.md).
- **eSignet profile** → run `helmsman_esignet.yml` manually. See [ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md](ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md).

---

## Verify

```bash
# Check all external service pods
kubectl get pods -n postgres
kubectl get pods -n redis
kubectl get pods -n kafka
kubectl get pods -n keycloak
kubectl get pods -n minio
kubectl get pods -n softhsm

# Check Istio
kubectl get pods -n istio-system

# Confirm namespace label set on success
kubectl get ns default --show-labels | grep external-dsf
```
