# eSignet Standalone Deployment Guide

This guide walks you through deploying eSignet standalone on your Kubernetes cluster using GitHub Actions.
You do **not** need to run any commands on your local machine — everything runs in the cloud via GitHub workflows.

**What gets deployed:**
- 4 parallel eSignet instances (esignet, esignet-cre, esignet-qa11, esignet-sunbird)
- OIDC UI for each instance
- Mock Relying Party service and UI
- Supporting infrastructure: Postgres, Redis, Kafka, Keycloak, SoftHSM, Captcha, MinIO

**Estimated time:** ~45–60 minutes end to end (external services ~20 min, eSignet ~25 min).

---

## Table of Contents

1. [Before You Start](#1-before-you-start)
2. [One-time GitHub Environment Setup](#2-one-time-github-environment-setup)
   - [Secrets](#a-secrets)
   - [Environment Variables](#b-environment-variables)
3. [Deployment Steps](#3-deployment-steps)
   - [Step 1 — Deploy External Services](#step-1--deploy-external-services)
   - [Step 2 — Deploy eSignet](#step-2--deploy-esignet)
   - [Step 3 — Deploy Signup (in progress)](#step-3--deploy-signup)
   - [Step 4 — Deploy Testrigs (optional)](#step-4--deploy-testrigs-optional)
4. [Re-deploying or Re-running](#4-re-deploying-or-re-running)
5. [Verifying Deployment](#5-verifying-deployment)

---

## 1. Before You Start

Complete this checklist before triggering any workflow:

- [ ] Kubernetes cluster is up and running
- [ ] `KUBECONFIG` file is available for your cluster
- [ ] DNS records for all domain names are pointed to your cluster's load balancer
- [ ] Google reCAPTCHA v2 keys are generated — you need **5 separate site/secret key pairs**:
  - one for `esignet` namespace
  - one for `esignet-cre` namespace
  - one for `esignet-qa11` namespace
  - one for `esignet-sunbird` namespace
  - one for `signup` namespace
  - See [reCAPTCHA Setup Guide](RECAPTCHA_SETUP_GUIDE.md)
- [ ] Mock Relying Party PEM key pair is generated (client private key + JWE private key)
- [ ] GitHub Environment named after your branch (e.g. `MOSIP-44613`) exists under:
  `Repository → Settings → Environments`

---

## 2. One-time GitHub Environment Setup

GitHub has two places to store secrets. It is important to put each secret in the **right place** — putting a secret in the wrong place will cause the workflow to fail.

| Type | Where to configure | Who can see it |
|---|---|---|
| **Repository secret** | `Settings → Secrets and variables → Actions → Repository secrets` | All workflows in the repo, regardless of environment |
| **Environment secret** | `Settings → Environments → <branch-name> → Secrets` | Only workflows that run in that specific environment (i.e. your branch) |

---

### A. Secrets

> Secrets are sensitive values (passwords, keys, tokens). They are masked in logs.

#### Repository Secret — one secret, configured once for the whole repo

| Secret Name | What it is | Required scopes | How to create |
|---|---|---|---|
| `GH_INFRA_PAT` | GitHub Fine-grained Personal Access Token | **Contents**: Read and write<br>**Actions**: Read and write<br>**Environments**: Read and write<br>**Variables**: Read and write<br>**Metadata**: Read-only | GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens |

**Why `GH_INFRA_PAT` is a repository secret (not environment secret):**
It is used to save workflow inputs back to environment variables via the GitHub API, and to dispatch the signup workflow. It needs to work across environments so it lives at the repo level.

> ⚠️ **Common mistake:** Using a Classic token instead of a Fine-grained token, or setting `Contents` to Read-only — both cause a `403` error when the workflow tries to push commits or update environment variables.

Path to create: `Your profile → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token`
- **Resource owner**: your organisation (e.g. `mosip`)
- **Repository access**: Only select repositories → choose this infra repo
- Set the permissions listed above, then generate and copy the token

---

#### Environment Secrets — configured per branch under `Settings → Environments → <branch-name> → Secrets`

**Cluster access — required by all Helmsman workflows:**

| Secret Name | What it is | Notes |
|---|---|---|
| `KUBECONFIG` | Raw kubeconfig YAML | Paste the raw YAML — **do not** base64 encode it |
| `CLUSTER_WIREGUARD_WG0` | WireGuard VPN client config | See [Secret Generation Guide](SECRET_GENERATION_GUIDE.md) |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL | From your Slack app's Incoming Webhooks settings |

**For `helmsman_external.yml` (profile = `esignet`):**

| Secret Name | What it is |
|---|---|
| `ESIGNET_CAPTCHA_SITE_KEY` | reCAPTCHA **site** key for the main `esignet` namespace |
| `ESIGNET_CAPTCHA_SECRET_KEY` | reCAPTCHA **secret** key for the main `esignet` namespace |

**For `helmsman_esignet.yml`:**

| Secret Name | What it is |
|---|---|
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY` | Base64-encoded PEM — mock relying party client private key |
| `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | Base64-encoded PEM — JWE userinfo private key |
| `ESIGNET_CRE_CAPTCHA_SITE_KEY` | reCAPTCHA **site** key for `esignet-cre` namespace |
| `ESIGNET_CRE_CAPTCHA_SECRET_KEY` | reCAPTCHA **secret** key for `esignet-cre` namespace |
| `ESIGNET_QA11_CAPTCHA_SITE_KEY` | reCAPTCHA **site** key for `esignet-qa11` namespace |
| `ESIGNET_QA11_CAPTCHA_SECRET_KEY` | reCAPTCHA **secret** key for `esignet-qa11` namespace |
| `ESIGNET_SUNBIRD_CAPTCHA_SITE_KEY` | reCAPTCHA **site** key for `esignet-sunbird` namespace |
| `ESIGNET_SUNBIRD_CAPTCHA_SECRET_KEY` | reCAPTCHA **secret** key for `esignet-sunbird` namespace |
| `CRE_POSTGRES_PASSWORD` | Postgres superuser password for the CRE remote environment |
| `QA11_POSTGRES_PASSWORD` | Postgres superuser password for the QA11 remote environment |
| `CRE_KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password for the CRE remote environment |
| `QA11_KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password for the QA11 remote environment |

> ⚠️ `CRE_KEYCLOAK_ADMIN_PASSWORD` and `QA11_KEYCLOAK_ADMIN_PASSWORD` are the admin passwords of the **remote** CRE and QA11 Keycloak instances (not the local one deployed by this stack). The preinstall hook calls those Keycloak REST APIs to fetch client secrets. A wrong domain or wrong password here will cause the preinstall to fail with a curl error.

**For `helmsman_signup.yml` (set now even though signup is not yet active):**

| Secret Name | What it is |
|---|---|
| `MOSIP_SIGNUP_CAPTCHA_SITE_KEY` | reCAPTCHA **site** key for the `signup` namespace |
| `MOSIP_SIGNUP_CAPTCHA_SECRET_KEY` | reCAPTCHA **secret** key for the `signup` namespace |

---

### B. Environment Variables

> Variables are non-sensitive configuration values visible in workflow logs.

Navigate to: `Repository → Settings → Environments → <your-branch-name> → Variables`

| Variable Name | Example Value | Required | Description |
|---|---|---|---|
| `DOMAIN_NAME` | `sandbox.xyz.net` | **Yes** | Base domain — all service hostnames are built from this |
| `ESIGNET_DB_PORT` | `5432` | **Yes** | Postgres port — always `5432` for standalone |
| `ENV_NAME` | `sandbox` | **Yes** | Short environment label shown on the landing page |
| `CLUSTER_ID` | `c-xxxxx` | **Yes** | Rancher cluster ID used by monitoring setup |
| `SLACK_CHANNEL_NAME` | `#mosip-alerts` | **Yes** | Slack channel name for alert notifications |
| `CRE_DOMAIN_NAME` | `cre.xyz.net` | Optional | Base domain for the CRE eSignet instance |
| `QA11_DOMAIN_NAME` | `qa11.xyz.net` | Optional | Base domain for the QA11 eSignet instance |
| `ESIGNET_CRE_SPRING_CONFIG_LABEL` | `develop` | Optional | Git branch/tag for CRE config-server (defaults to `develop`) |
| `ESIGNET_QA11_SPRING_CONFIG_LABEL` | `develop` | Optional | Git branch/tag for QA11 config-server (defaults to `develop`) |
| `ESIGNET_STANDALONE_MODE` | `true` | Optional | Set to `true` to skip the MOSIP DSF completion check |

---

## 3. Deployment Steps

There are **4 steps** in total. Run them in the order shown below. **Do not start the next step until the current one shows a green tick (✅) in GitHub Actions.**

```
Step 1 → Deploy External Services   (helmsman_external.yml)   ~20 min
Step 2 → Deploy eSignet             (helmsman_esignet.yml)    ~25 min
Step 3 → Deploy Signup              (helmsman_signup.yml)     ⚠️  IN PROGRESS — not ready yet
Step 4 → Deploy Testrigs (optional) (helmsman_testrigs.yml)   ~10 min
```

---

### Step 1 — Deploy External Services

> **What this does:** Sets up all the background infrastructure that eSignet needs to run — database (PostgreSQL), cache (Redis), messaging (Kafka), identity provider (Keycloak), hardware security module (SoftHSM), captcha service, and file storage (MinIO).
> You must complete this step before anything else.

**GitHub Actions workflow name:** `Deploy External services of mosip using Helmsman`

**How to run:**
1. Go to your repository on GitHub
2. Click the **Actions** tab at the top
3. In the left sidebar, click **`Deploy External services of mosip using Helmsman`**
4. Click the **`Run workflow`** button (top right of the workflow runs list)
5. Fill in the fields exactly as shown:

| Field | Value to enter |
|---|---|
| `profile` | `esignet` |
| `mode` | `apply` |
| `domain_name` | your base domain — e.g. `sandbox.xyz.net` |
| `db_port` *(MOSIP platform external postgres)* | leave blank — not used by the `esignet` profile |
| `esignet_db_port` *(esignet container postgres)* | `5432` |
| `clusterid` | your Rancher cluster ID — e.g. `c-xxxxx` |
| `env_name` | a short label for your environment — e.g. `sandbox` |
| `slack_channel_name` | your Slack channel — e.g. `#mosip-alerts` |

> **Note:** The form always shows both `db_port` and `esignet_db_port` fields regardless of profile — for `esignet`, fill in only `esignet_db_port` and leave `db_port` blank.

6. Click the green **`Run workflow`** button

![Deploy External Services - Helmsman](_images/helmsman-external-services.png)

**How to know it succeeded:** Click into the running workflow. Wait for all jobs to show a green tick. Then run:
```bash
kubectl get pods -n postgres && kubectl get pods -n keycloak && kubectl get pods -n kafka
```
All pods should show `Running` or `Completed`.

---

### Step 2 — Deploy eSignet

> **What this does:** Deploys the eSignet application itself — 4 separate instances (main, CRE, QA11, Sunbird), the OIDC login UI for each, and the Mock Relying Party service for testing.
> Only run this after Step 1 is fully complete.

**GitHub Actions workflow name:** `Deploy eSignet using Helmsman`

**How to run:**
1. Go to **Actions** → click **`Deploy eSignet using Helmsman`** in the left sidebar
2. Click **`Run workflow`**
3. Fill in the fields:

| Field | Value to enter |
|---|---|
| `profile` | `esignet` |
| `mode` | `apply` |
| `skip_mosip_dsf_check` | **tick this** — standalone has no MOSIP deployment to wait for |
| `delete_existing_jobs` | tick only if re-running after a failure; leave unticked on first deploy |
| `domain_name` | your base domain — e.g. `sandbox.xyz.net` |
| `esignet_db_port` | `5432` |
| `cre_domain_name` | CRE base domain — e.g. `cre.xyz.net` *(leave blank if not using CRE)* |
| `qa11_domain_name` | QA11 base domain — e.g. `qa11.xyz.net` *(leave blank if not using QA11)* |
| `env_name` | your environment name — e.g. `sandbox` |

> **Important:** Always tick `skip_mosip_dsf_check` for standalone eSignet — without it, the workflow waits for a `mosip-dsf=completed` namespace label that will never appear (there is no full MOSIP deployment in this mode), and the workflow will fail.

4. Click the green **`Run workflow`** button

![Deploy eSignet - Helmsman](_images/esignet.png)

**How to know it succeeded:**
```bash
kubectl get pods -n esignet && kubectl get pods -n esignet-cre && kubectl get pods -n esignet-qa11 && kubectl get pods -n esignet-sunbird
```
All pods should show `Running`.

---

### Step 3 — Deploy Signup

> ⚠️ **Signup deployment is currently in progress and not yet available.**
>
> The `helmsman_signup.yml` workflow exists but the signup configuration (DSF and hook scripts) is still being finalised and tested. The automatic trigger that was meant to fire signup after Step 2 has been **temporarily disabled** until this work is complete.
>
> **What you need to do right now:** Nothing — skip this step for now. However, make sure the signup secrets (`MOSIP_SIGNUP_CAPTCHA_SITE_KEY` and `MOSIP_SIGNUP_CAPTCHA_SECRET_KEY`) are already added to the GitHub Environment (see Section 2) so you are ready when signup is enabled.
>
> This section will be updated with full instructions once signup deployment is ready.

---

### Step 4 — Deploy Testrigs (Optional)

> **What this does:** Deploys automated API and UI test jobs that run against the deployed eSignet instances to verify everything is working correctly. This step is optional — only run it if you want to validate the deployment with automated tests.
> Only run this after Steps 1 and 2 are complete and **all pods are in `Running` state**.

**GitHub Actions workflow name:** `Deploy Testrigs of mosip using Helmsman`

**How to run:**
1. Go to **Actions** → click **`Deploy Testrigs of mosip using Helmsman`** in the left sidebar
2. Click **`Run workflow`**
3. Fill in the fields:

| Field | Value to enter |
|---|---|
| `profile` | `esignet` |
| `mode` | `apply` |
| `domain_name` | your base domain — e.g. `sandbox.xyz.net` |
| `cre_domain_name` | CRE base domain *(if CRE was deployed in Step 2)* |
| `qa11_domain_name` | QA11 base domain *(if QA11 was deployed in Step 2)* |
| `db_port` *(MOSIP platform external postgres)* | leave blank — not used by the `esignet` profile |
| `esignet_db_port` *(esignet container postgres)* | `5432` |
| `env_name` | your environment name |
| `slack_channel_name` | your Slack channel |

4. Click the green **`Run workflow`** button

![Deploy Test Rigs - Helmsman](_images/helmsman-testrigs.png)

**How to know it succeeded:** The workflow log should show all Helmsman releases applied without errors. Verify that test cronjobs were created:
```bash
kubectl get cronjobs -n esignet
kubectl get cronjobs -n esignet-cre
kubectl get cronjobs -n esignet-qa11
kubectl get cronjobs -n esignet-sunbird
```

---

## 4. Re-deploying or Re-running

If a workflow fails or you need to re-run a deployment:

- **Always tick `delete_existing_jobs`** in the `helmsman_esignet.yml` inputs on re-runs — this removes stale Kubernetes Jobs that would otherwise block the deployment
- If re-running `helmsman_external.yml`, MinIO will reuse the existing password automatically — no action needed
- If a workflow fails mid-way, check the failed step's logs first — most failures are missing secrets or DNS not yet propagated

---

## 5. Verifying Deployment

Run these commands against your cluster to confirm everything is healthy:

```bash
# Check all pods across eSignet namespaces
kubectl get pods -n esignet
kubectl get pods -n esignet-cre
kubectl get pods -n esignet-qa11
kubectl get pods -n esignet-sunbird

# Check Istio virtual services (confirms domain routing)
kubectl get virtualservice -n esignet

# Check Helm releases
helm list -n esignet
helm list -n keycloak

# Quick health check — should return no non-Running pods
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed | grep -v Terminating
```

**Expected URLs after deployment** (replace `sandbox.xyz.net` with your domain):

| Service | URL |
|---|---|
| eSignet OIDC UI | `https://esignet.sandbox.xyz.net` |
| Mock Relying Party UI | `https://healthservices.sandbox.xyz.net` |
| Keycloak | `https://iam.sandbox.xyz.net` |
| CRE eSignet | `https://esignet-mosipid-cre.sandbox.xyz.net` |
| QA11 eSignet | `https://esignet-mosipid-qa11.sandbox.xyz.net` |
| Sunbird eSignet | `https://esignet-sunbird.sandbox.xyz.net` |
