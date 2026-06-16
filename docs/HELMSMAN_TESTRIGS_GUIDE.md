# Helmsman Testrigs Deployment Guide

Deploy API, UI, and DSL test rigs after all services are running and partner onboarding is complete.

## Overview

**Workflow:** `helmsman_testrigs.yml`  
**DSF:** `Helmsman/dsf/<profile>/testrigs-dsf.yaml`  
**Time required:** 10–20 minutes

---

## Profile Differences

| Profile | What deploys | Namespaces |
|---------|-------------|------------|
| `esignet` | `esignet-apitestrig` into 4 namespaces; optional signup apitestrig + uitestrig | `esignet`, `esignet-cre`, `esignet-qa11`, `esignet-sunbird`, `signup` |
| `mosip-platform-1.2.0.x` | API testrig, UI testrig, DSL testrig | MOSIP testrig namespaces |
| `mosip-platform-1.2.1.x` | Same as above | MOSIP testrig namespaces |

> **eSignet standalone (`esignet` profile):** Requires two additional workflow inputs — `cre_domain_name` and `qa11_domain_name` — for the CRE and QA11 apitestrig endpoints. The workflow validates these are provided before running.

---

## Prerequisites

**All profiles:**
- All service pods from previous steps are in `Running` state
- Partner onboarding completed successfully (MOSIP platform profiles)

**eSignet standalone profile additionally:**
- eSignet DSF completed (`kubectl get ns default --show-labels | grep esignet-dsf`)
- Signup DSF completed if testing signup (`kubectl get ns default --show-labels | grep signup-dsf`)

---

## Required Secrets

All secrets are **Environment Secrets** — configure at **Repository → Settings → Environments → `<branch-name>` → Secrets**.

### All profiles

| Secret | Description |
|--------|-------------|
| `KUBECONFIG` | Raw YAML kubeconfig (not base64 encoded) |
| `CLUSTER_WIREGUARD_WG0` | WireGuard VPN config for cluster access |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (optional — for test result notifications) |

### eSignet standalone profile only

No additional secrets required for testrigs — captcha and keycloak secrets were already created during eSignet deployment and are available in each namespace.

### MOSIP platform profiles only

No additional secrets required — MinIO root password is read automatically from the `minio` secret in the `minio` namespace (`kubectl -n minio get secret minio`).

---

## Workflow Inputs

### All profiles

| Input | Description | Example |
|-------|-------------|---------|
| `profile` | Deployment profile | `esignet` / `mosip-platform-1.2.0.x` / `mosip-platform-1.2.1.x` |
| `mode` | Helmsman mode | Always `apply` — dry-run will fail |
| `domain_name` | Base domain for this environment | `soil38.mosip.net` |
| `env_name` | Environment name | `soil38` |
| `slack_channel_name` | Slack channel for alerting (optional) | `#mosip-alerts` |

### eSignet standalone profile additionally

| Input | Description | Example |
|-------|-------------|---------|
| `cre_domain_name` | Domain for the CRE eSignet instance | `cre.mosip.net` |
| `qa11_domain_name` | Domain for the QA11 eSignet instance | `qa11.mosip.net` |

> If not provided as inputs, values fall back to GitHub Environment Variables: `vars.CRE_DOMAIN_NAME` and `vars.QA11_DOMAIN_NAME`.

---

## Step-by-Step: Run the Workflow

![Deploy Test Rigs - Helmsman](_images/helmsman-testrigs.png)

- **(1)** Go to **Actions** → **"Deploy Testrigs of mosip using Helmsman"**
  > Can't find it? Search for "Testrig" or "Testrigs" in the workflows list.
- **(2)** Click **Run workflow** button in the top right corner
- **(3)** **Branch** — select your deployment branch (e.g., `MOSIP-44613`)
- **(4)** **Deployment profile** — select your profile (e.g., `mosip-platform-1.2.0.x` or `esignet`)
- **(5)** **Helmsman mode** — select `apply` (dry-run will fail)
- **(6)** **Domain name** — enter your base domain (e.g., `soil38.mosip.net`)
- **(7)** **Environment name** — enter your env name (e.g., `soil38`)
- **(8)** **Slack channel name** (optional) — e.g., `#mosip-alerts`
- **(9)** **Slack webhook URL** (optional) — your Slack incoming webhook URL
- **(10)** *(eSignet profile only)* **CRE domain name** — e.g., `cre.mosip.net`
- **(11)** *(eSignet profile only)* **QA11 domain name** — e.g., `qa11.mosip.net`
- **(12)** Click **Run workflow** green button

> **Important:** Always pass `--keep-untracked-releases` — without it Helmsman will delete releases from previous DSFs (esignet, oidc-ui, etc.) that aren't listed in `testrigs-dsf.yaml`. The workflow handles this automatically.

---

## Post-Deployment Steps

After testrigs deploy successfully:

**1. Update cron schedules**

Update the cron time for CronJobs in the testrig namespaces to match your desired schedule:

```bash
# List all cronjobs across testrig namespaces
kubectl get cronjobs -n apitestrig
kubectl get cronjobs -n uitestrig
kubectl get cronjobs -n dslrig

# For eSignet standalone
kubectl get cronjobs -n esignet
kubectl get cronjobs -n esignet-cre
kubectl get cronjobs -n esignet-qa11
kubectl get cronjobs -n esignet-sunbird
```

**2. Trigger DSL orchestrator (MOSIP platform profiles)**

```bash
kubectl create job --from=cronjob/cronjob-dslorchestrator-full dslrig-manual-run -n dslrig
```

> This job runs for 3+ hours. Monitor progress:
> ```bash
> kubectl logs -f job/dslrig-manual-run -n dslrig
> ```

**3. Trigger eSignet test jobs (eSignet standalone profile)**

The `trigger-test-jobs-esignet.sh` postInstall hook fires automatically after the last testrig deploys — it triggers all cronjobs across all 4 esignet namespaces sequentially and optionally signup/signup-uitestrig if deployed.

To trigger manually:

```bash
export KUBECONFIG=/path/to/kubeconfig
export WORKDIR=/path/to/Helmsman
./hooks/esignet-standalone/trigger-test-jobs-esignet.sh
```

---

## Verify

```bash
# Check testrig pods (MOSIP platform)
kubectl get pods -n apitestrig
kubectl get pods -n uitestrig
kubectl get pods -n dslrig

# Check testrig pods (eSignet standalone)
kubectl get pods -n esignet      # esignet-apitestrig cronjob
kubectl get pods -n esignet-cre
kubectl get pods -n esignet-qa11
kubectl get pods -n esignet-sunbird
kubectl get pods -n signup       # signup-apitestrig (if enabled)
```
