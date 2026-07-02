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
| `esignet-standalone` | `esignet-apitestrig` into up to 4 namespaces; optional signup apitestrig + uitestrig | `esignet-mock`, `esignet-mosipid1`, `esignet-mosipid2` *(if enabled)*, `esignet-sunbird`, `signup` |
| `mosip-platform-1.2.0.x` | API testrig, UI testrig, DSL testrig | MOSIP testrig namespaces |
| `mosip-platform-1.2.1.x` | Same as above | MOSIP testrig namespaces |

> **eSignet standalone (`esignet-standalone` profile):** Requires `mosipid1_domain_name` for the MOSIP-ID1 apitestrig endpoint. `mosipid2_domain_name` is only required if mosipid2 was enabled during eSignet deployment (`enable_mosipid2: true`).

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
| `profile` | Deployment profile | `esignet-standalone` / `mosip-platform-1.2.0.x` / `mosip-platform-1.2.1.x` |
| `mode` | Helmsman mode | Always `apply` — dry-run will fail |
| `domain_name` | Base domain for this environment | `soil38.mosip.net` |
| `db_port` | External postgres port — MOSIP platform only | `5433` |
| `esignet_db_port` | eSignet container postgres port — eSignet profile only | `5432` |
| `env_name` | Environment name | `soil38` |
| `slack_channel_name` | Slack channel for alerting (optional) | `#mosip-alerts` |

### eSignet standalone profile additionally

| Input | Description | Example |
|-------|-------------|---------|
| `mosipid1_domain_name` | Domain for the MOSIP-ID1 eSignet instance | `mosipid1.mosip.net` |
| `mosipid2_domain_name` | Domain for the MOSIP-ID2 eSignet instance — only required if mosipid2 was enabled (`enable_mosipid2: true`) during eSignet deployment | `mosipid2.mosip.net` |

> If not provided as inputs, values fall back to GitHub Environment Variables: `vars.MOSIPID1_DOMAIN_NAME` and `vars.MOSIPID2_DOMAIN_NAME`.

---

## Step-by-Step: Run the Workflow

![Deploy Test Rigs - Helmsman](_images/helmsman-testrigs.png)

- **(1)** Go to **Actions** (top of the repository page) → click **"Deploy Testrigs of mosip using Helmsman"** in the list on the left.
  > Can't find it? Search for "Testrig" or "Testrigs" in the workflows list.
- **(2)** Click the **Run workflow** dropdown button (top right) — this opens the form shown above.
- **(3)** **Branch** — pick the branch you're deploying from (e.g., `MOSIP-44613`).
- **(4)** **Deployment profile to use** — pick the profile you want (e.g., `mosip-platform-1.2.0.x` or `esignet-standalone`).
- **(5)** **Choose Helmsman mode: dry-run or apply** — always pick **`apply`**.
- **(6)** **Domain name for this environment** — type the web domain this environment should use (e.g., `example.xyz.net`).
- **(7)** **MOSIP-ID1 domain name** *(eSignet profile only)* — type the base domain used by the MOSIP-ID1 eSignet instance (e.g., `mosipid1.xyz.net`). Leave blank for MOSIP platform profiles.
- **(8)** **QA base domain name** *(eSignet profile only)* — type the base domain used by the MOSIP-ID2 eSignet instance (e.g., `mosipid2.xyz.net`). Leave blank for MOSIP platform profiles.
- **(9)** **PostgreSQL port for MOSIP platform external postgres** — only fill this in if you picked a `mosip-platform-*` profile in step 4. Type `5433` (or whatever port your external PostgreSQL uses).
- **(10)** **PostgreSQL port for esignet standalone container postgres** — only fill this in if you picked the `esignet-standalone` profile in step 4. Type `5432`.
- **(11)** **Environment name** — a short nickname for this environment (e.g., `sandbox`, `dev`, `staging`).
- **(12)** **Slack channel name for alerting** (optional) — the Slack channel that should receive test result notifications (e.g., `#mosip-alerts`). Leave blank if you don't want Slack alerts.
- **(13)** **Slack webhook URL for alerting** (optional) — leave this blank; it's normally already saved as the `SLACK_WEBHOOK_URL` secret in your GitHub environment.
- **(14)** Click the green **Run workflow** button to start the deployment.

> **Note:** Steps 7–10 all appear in the form regardless of which profile you picked — fill in only the ones that match your profile (MOSIP-ID1/MOSIP-ID2 domains for `esignet-standalone`, PostgreSQL port for `mosip-platform-*`) and leave the rest blank.

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
kubectl get cronjobs -n esignet-mosipid1
kubectl get cronjobs -n esignet-mosipid2
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
kubectl get pods -n esignet-mosipid1
kubectl get pods -n esignet-mosipid2
kubectl get pods -n esignet-sunbird
kubectl get pods -n signup       # signup-apitestrig (if enabled)
```
