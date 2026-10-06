# Quickstart: AWS

Deploy a complete MOSIP-ready cluster on AWS with one workflow run.

!!! abstract "Before you begin"
    - The repository forked, and a **branch for your environment** (e.g. `soil38`). The branch name
      is the environment: it names the state files and selects the GitHub environment.
    - An AWS account with an **EC2 key pair** and a **Route53 hosted zone** for your domain.
    - Repository secrets set — see [Secrets & configuration](secrets.md):
      `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `GPG_PASSPHRASE`, `GH_INFRA_PAT`, and a secret
      named after your key pair holding its private key.

**Time:** about 45 minutes, most of it unattended.

## Step 1 — Create the network (once per account)

Edit `terraform/implementations/aws/base-infra/aws.tfvars`:

```hcl
jumpserver_name = "mosip-jump"
mosip_email_id  = "ops@example.org"
ssh_key_name    = "mosip-aws"
network_name    = "mosip-boxes"      # becomes vpc_name in step 3
network_cidr    = "10.0.0.0/16"
```

Run **Actions → terraform plan / apply** with:

| Input | Value |
|---|---|
| `COMPONENT` | `base-infra` |
| `CLOUD_PROVIDER` | `aws` |
| `TERRAFORM_APPLY` | ✅ |

## Step 2 — Connect WireGuard

The configuration step reaches the private nodes over WireGuard. Follow
[WireGuard access](../guides/wireguard.md) and add the client config as the **`TF_WG_CONFIG`**
environment secret of your branch.

## Step 3 — Fill in your profile

Choose a [profile](../guides/profiles.md) — `mosip` for the full platform. Edit
`profiles/mosip/aws/common.tfvars`:

```hcl
cluster_name        = "soil38"
cluster_env_domain  = "soil38.mosip.net"
mosip_email_id      = "ops@example.org"
ssh_key_name        = "mosip-aws"
aws_provider_region = "ap-south-1"
zone_id             = "Z0123456789ABCDEFGHI"
ami                 = "ami-0ad21ae1d0696ad58"   # Ubuntu 24.04 in this region
vpc_name            = "mosip-boxes"
network_cidr        = "10.0.0.0/16"
WIREGUARD_CIDR      = "10.0.0.0/16"
```

!!! warning "Three values must match"
    - `vpc_name` = `network_name` from step 1
    - `network_cidr` = the base-infra `network_cidr` (the template default `172.0.0.0/8` is a placeholder)
    - `ami` must be an Ubuntu 24.04 image **in the same region** — AMI IDs differ per region

Review, but usually keep: `compute.tfvars` (sizes, node counts), `storage.tfvars` (disks),
`profile.yml` (subdomains, TLS mode). Commit and push to your branch.

## Step 4 — Deploy

Run **Actions → terraform plan / apply** on your branch:

| Input | Value |
|---|---|
| `COMPONENT` | `all` |
| `PROFILE` | `mosip` |
| `SSH_PRIVATE_KEY` | name of your key-pair secret, e.g. `mosip-aws` |
| `TERRAFORM_APPLY` | ✅ (required for `all`) |
| `ENABLE_RANCHER_IMPORT` | ✅ if you run an [observability cluster](../guides/observability-rancher.md) |

The workflow runs, each as its own job, stopping at the first failure:

```
security → iam → compute → storage → dns → configure (Ansible)
```

## Step 5 — Verify

- [x] All jobs green in the workflow run.
- [x] `api.soil38.mosip.net` resolves and serves HTTPS.
- [x] With Rancher import: the cluster shows **Active** in Rancher and the `KUBECONFIG` environment
      secret is set. Without it, copy the kubeconfig from the primary node:

    ```bash
    scp -i mosip-aws.pem ubuntu@<k8s_primary_control_plane_ip>:/home/ubuntu/.kube/soil38-CONTROL-PLANE-NODE-1.yaml kubeconfig
    KUBECONFIG=kubeconfig kubectl get nodes
    ```

## Next steps

- [Deploy MOSIP services](deploy-mosip.md) with Helmsman.
- Day-2: [change DNS](../guides/dns-providers.md) · [add nodes](../guides/scaling-nodes.md) ·
  [destroy](../guides/destroy.md).
- Something failed? See the [error catalogue](../troubleshooting/errors.md).
