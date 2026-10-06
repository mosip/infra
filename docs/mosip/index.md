# Deploy MOSIP services

Once the cluster is ready, Helmsman installs the MOSIP services from Desired State Files (DSF).
This page is the overview; each step has its own guide.

!!! abstract "Before you begin"
    - A running cluster from [Quickstart: AWS](../getting-started/quickstart-aws.md) or
      [Quickstart: data centre](../getting-started/quickstart-datacentre.md).
    - The **`KUBECONFIG`** environment secret on your branch (raw YAML, not base64) — set
      automatically with Rancher import + `PUBLISH_KUBECONFIG`, otherwise copy it from the
      primary node: `/home/ubuntu/.kube/<cluster_name>-CONTROL-PLANE-NODE-1.yaml`.
    - **`CLUSTER_WIREGUARD_WG0`** (and optionally `CLUSTER_WIREGUARD_WG1`) environment secrets —
      see [WireGuard access](../guides/wireguard.md).

## The flow

=== "MOSIP platform"

    ```
    External + Prereqs  →  MOSIP services (auto)  →  eSignet (manual)  →  Test rigs (manual)
    ```

=== "eSignet standalone"

    ```
    External + Prereqs  →  eSignet (manual)  →  Signup (auto)  →  Test rigs (manual)
    ```

| Step | Workflow | Trigger | Guide |
|:-:|---|---|---|
| 1 | External + Prereqs | Manual | [External services](external-services.md) |
| 2 | MOSIP services | Auto after step 1 (MOSIP platform) | [MOSIP services](mosip-services.md) |
| 3 | eSignet | Manual | [eSignet](esignet.md) · [eSignet standalone](esignet-standalone.md) |
| 4 | Test rigs | Manual | [Test rigs](testrigs.md) |

!!! warning "Always use `apply` mode"
    `dry-run` fails: MOSIP services reference ConfigMaps and Secrets from other namespaces that
    don't exist at dry-run time.

## Configure the environment

You don't edit DSF files per environment. Values are substituted at deploy time (`${VAR}`), from
workflow inputs or, for push-triggered runs, from **Settings → Environments → `<branch>` →
Variables**:

| Variable | Example | Used by |
|---|---|---|
| `DOMAIN_NAME` | `soil38.mosip.net` | All DSFs — host names, Istio, DB hosts. Must equal `cluster_env_domain`. |
| `ENV_NAME` | `soil38` | Landing page, test-rig user. Must equal `cluster_name`. |
| `CLUSTER_ID` | `c-m-abc12xyz` | `prereq-dsf.yaml` (Rancher monitoring) |
| `SLACK_CHANNEL_NAME` | `#mosip-alerts` | `prereq-dsf.yaml` (alerting) |
| `DB_PORT` | `5433` | MOSIP platform external PostgreSQL |
| `ESIGNET_DB_PORT` | `5432` | eSignet container PostgreSQL |

Find `CLUSTER_ID` in the Rancher cluster URL (`c-m-…`) or with
`kubectl get setting cluster-id -n cattle-system -o jsonpath='{.value}'`.

## Secrets for MOSIP services

| Secret | For | Guide |
|---|---|---|
| `KUBECONFIG`, `CLUSTER_WIREGUARD_WG0`, `CLUSTER_WIREGUARD_WG1` | all | above |
| `PREREG_CAPTCHA_SITE_KEY` / `_SECRET_KEY`, `ADMIN_…`, `RESIDENT_…` | MOSIP platform | [reCAPTCHA](recaptcha.md) |
| `ESIGNET_CAPTCHA_SITE_KEY` / `_SECRET_KEY` | eSignet | [eSignet](esignet.md) |
| `MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY`, `MOCK_RELYING_PARTY_JWE_PRIVATE_KEY` | eSignet mock RP | [eSignet](esignet.md) |
| `SLACK_WEBHOOK_URL` | alerting | — |

```yaml
# Example values — placeholders, never commit real keys
ESIGNET_CAPTCHA_SITE_KEY: "<recaptcha-site-key>"
ESIGNET_CAPTCHA_SECRET_KEY: "<recaptcha-secret-key>"
MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY: "<base64 PEM>"
```

## PostgreSQL choice

The one DSF decision left is `postgres.enabled` in `external-dsf.yaml`:

| Your profile's `configure_components` | `postgres.enabled` |
|---|---|
| lists `postgresql` (external PostgreSQL on the nginx host) | `false` |
| doesn't list it | `true` (in-cluster PostgreSQL) |

For the MOSIP platform also set `gitRepo.dbBranch` in `mosip-dsf.yaml` to your MOSIP version.
Details: [DSF configuration](dsf-configuration.md).

## Verify

```bash
kubectl get nodes
kubectl get pods -A          # everything Running / Completed
kubectl get svc -n istio-system
```

Partner onboarding sometimes needs a manual re-run — see [Partner onboarding](partner-onboarding.md).
To remove services without touching the infrastructure, see [Remove MOSIP services](destroy-services.md).
