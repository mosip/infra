# Introduction

MOSIP Infra prepares everything MOSIP needs underneath the application, so the MOSIP services can
be installed on top with Helmsman.

## What it sets up

- **Network and access** — VPC, subnets and a WireGuard VPN server *(AWS)*
- **Servers** — an nginx reverse-proxy host and the Kubernetes nodes
- **Firewall, disks and DNS** — security groups, data disks, DNS records
- **TLS** — a certificate for your domain
- **Kubernetes** — an RKE2 cluster, optionally registered in Rancher
- **Shared services** — NFS, external PostgreSQL and ActiveMQ storage *(per profile)*

## Who it's for

| You are… | Start here |
|---|---|
| Deploying a **dev / test environment on AWS** | [Quickstart: AWS](../getting-started/quickstart-aws.md) |
| A **country / data-centre team** with your own servers | [Quickstart: data centre](../getting-started/quickstart-datacentre.md) |
| **Operating** an existing environment | [How-to guides](../guides/dns-providers.md) |
| **Reviewing the design** | [Architecture](architecture.md) |

## Key ideas in one minute

1. **Two layers.** Terraform creates machines (AWS only). Ansible configures machines (anywhere).
2. **Independent components.** On AWS, `security`, `iam`, `compute`, `storage` and `dns` each have
   their own state — change one without touching the others.
3. **Profiles.** `mosip`, `esignet-standalone` and `observ` describe *what* to deploy; the same
   profile works on AWS and in a data centre.
4. **One branch per environment.** The branch name selects the secrets and names the state.
5. **Same order as before.** IAM before servers, DNS before nginx — checked automatically.

## What's new compared with the legacy setup

The single `aws-resource-creation` Terraform module has been retired. Setup steps moved from
Terraform to Ansible, data centres are supported without Terraform, DNS and TLS work with any
provider, and the observability cluster became a profile. See [Release notes](../release-notes/index.md).

**Next:** [Architecture](architecture.md)
