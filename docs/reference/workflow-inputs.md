# Workflow inputs

Inputs of the two GitHub Actions workflows that provision and destroy infrastructure. Both run
on **your environment branch**; the branch name selects the GitHub environment (secrets) and
names the state files.

## terraform plan / apply

File: `.github/workflows/terraform.yml`

| Input | Type | Default | Values / description |
|---|---|---|---|
| `CLOUD_PROVIDER` | choice | — | `aws`, `azure`, `gcp`. Azure and GCP support `base-infra` only. |
| `COMPONENT` | choice | `all` | `all` — every component in order, then `configure`<br>`security`, `iam`, `compute`, `storage`, `dns` — one component<br>`configure` — Ansible only<br>`vm` — standalone EC2 + SG + IAM<br>`base-infra` — one-time VPC + WireGuard |
| `PROFILE` | choice | `mosip` | `mosip`, `esignet-standalone`, `observ`. Ignored for `base-infra`. |
| `BACKEND_TYPE` | choice | `local` | `local` (GPG-encrypted state committed to the branch) or `remote` |
| `REMOTE_BACKEND_CONFIG` | string | — | `aws:<bucket_base>:<region>` · `azure:<rg>:<storage_account>:<container>` · `gcp:<bucket>` |
| `ENABLE_STATE_LOCKING` | boolean | `false` | Lock state (recommended for remote backends) |
| `SSH_PRIVATE_KEY` | string | — | **Name** of the GitHub secret holding the nodes' SSH private key |
| `TERRAFORM_APPLY` | boolean | `false` | Unchecked = plan only. **Required** for `all` and `configure`. |
| `ENABLE_RANCHER_IMPORT` | boolean | `false` | Register the cluster in Rancher (needs `RANCHER_API_URL`, `RANCHER_API_TOKEN`) |
| `RANCHER_CLUSTER_NAME` | string | branch name | Name of the cluster in Rancher |
| `PUBLISH_KUBECONFIG` | boolean | `true` | After import, store the kubeconfig as the `KUBECONFIG` environment secret |
| `GRANT_GROUP_ACCESS` | boolean | `false` | Also grant the teams in `rancher-access-grants.json` (DEVOPS is always granted) |
| `RANCHER_CLUSTER_OWNER_GROUP_ENABLED` | boolean | `false` | Give one more group cluster-owner access |
| `RANCHER_CLUSTER_OWNER_GROUP` | string | — | That group's name, e.g. `QA` |
| `DNS_PROVIDER` | choice | `terraform-route53` | `terraform-route53`, `godaddy`, `cloudflare`, `rfc2136`, `manual` — see [DNS providers](../guides/dns-providers.md) |

!!! info "What `COMPONENT=all` runs"
    `security → iam → compute → storage → dns → configure`, each as its own job, stopping at the
    first failure. With a `DNS_PROVIDER` other than `terraform-route53`, the Route53-only `iam` and
    `dns` jobs are skipped and the Ansible `dns` role creates the records during `configure`.

## terraform destroy

File: `.github/workflows/terraform-destroy.yml`

| Input | Type | Default | Values / description |
|---|---|---|---|
| `CLOUD_PROVIDER` | choice | — | `aws`, `azure`, `gcp` |
| `COMPONENT` | choice | `all` | `all` — every component in **reverse** order (`dns → storage → compute → iam → security`, plus `vm`)<br>or one of `dns`, `storage`, `compute`, `iam`, `security`, `vm`, `base-infra` |
| `PROFILE` | choice | `mosip` | Must match the deployment |
| `BACKEND_TYPE` | choice | `local` | Must match the deployment |
| `REMOTE_BACKEND_CONFIG` | string | — | Must match the deployment |
| `ENABLE_STATE_LOCKING` | boolean | `false` | Must match the deployment |
| `SSH_PRIVATE_KEY` | string | — | Only needed for `base-infra` |
| `TERRAFORM_DESTROY` | boolean | `false` | **Confirm destruction.** Unchecked = `plan -destroy` only |
| `DNS_PROVIDER` | choice | `terraform-route53` | Must match the deployment; non-Route53 skips the `dns` and `iam` components |

!!! danger "`base-infra` is shared"
    Destroying `base-infra` removes the VPC and WireGuard server used by **every** environment in
    that account. Destroy all environments first.

## Secrets by feature

| Feature | Secrets (environment or repository) |
|---|---|
| Always | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `GH_INFRA_PAT`, the SSH key secret |
| Local backend | `GPG_PASSPHRASE` |
| `configure` | `TF_WG_CONFIG` |
| Rancher import | `RANCHER_API_URL`, `RANCHER_API_TOKEN` |
| `observ` profile | `RANCHER_BOOTSTRAP_PASSWORD` |
| `DNS_PROVIDER=godaddy` | `GODADDY_API_KEY`, `GODADDY_API_SECRET` |
| `DNS_PROVIDER=cloudflare` | `CLOUDFLARE_API_TOKEN` |
| `DNS_PROVIDER=rfc2136` | `DNS_RFC2136_SERVER`, `DNS_RFC2136_KEY_NAME`, `DNS_RFC2136_KEY_SECRET` |
| Optional | `SLACK_WEBHOOK_URL`; variable `DNS_ZONE` (zone apex for Ansible DNS) |
