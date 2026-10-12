# Concepts

Six ideas explain how MOSIP Infra works.

## Layers

| Layer | Tool | Does | Where |
|---|---|---|---|
| 1–2 | Terraform | **Creates** network, servers, disks, DNS, IAM | AWS only |
| 3 | Ansible | **Configures** the servers (TLS, nginx, RKE2, NFS, PostgreSQL, ActiveMQ) | Any Ubuntu VM |
| 4 | Helmsman | **Deploys** MOSIP services on Kubernetes | Any cluster |

## Components

On AWS, Terraform is split into components, each with its own state:
`security`, `iam`, `compute`, `storage`, `dns` — plus `vm` for standalone servers and
`base-infra` for the one-time network. A component finds the ones before it through AWS tags,
never through their state, so each can be changed or destroyed on its own.
See [Terraform components](../reference/terraform-components.md).

## Profiles

A **profile** is a deployment shape — sizes, which setup steps run, and the DNS names:

| Profile | Nodes (control-plane / etcd / worker) | Setup steps |
|---|---|---|
| `mosip` | 3 / 3 / 1 | nginx, rke2, rancher_import, nfs, postgresql, activemq |
| `esignet-standalone` | 1 / 1 / 2 | nginx, rke2, rancher_import, nfs |
| `observ` | 1 / 0 / 0 | nginx, rke2, nfs, rancher_keycloak |

A profile works the same on AWS and in a data centre. See [Choose or add a profile](../guides/profiles.md).

## Environments

**One Git branch = one environment.** The branch name selects the GitHub environment (its
secrets), names the Terraform state, and is the default Rancher cluster name. Profile values on
the branch hold that environment's settings.

## Inventory

Ansible needs to know the servers. `ansible/inventory/generate.py` builds one inventory format
from either Terraform outputs (AWS) or a `hosts.yml` file (data centre). The roles never know
which one was used. See [profile.yml & hosts.yml](../reference/schemas.md).

## Order

The setup order is fixed and matches the legacy deployment:

```
security → iam → compute → storage → dns → [dns provider] → preflight → tls + nginx
  → rke2 → rancher import → nfs → postgresql → activemq → rancher + keycloak
```

Pre-flight checks enforce the important constraints (DNS before nginx, disks present).
See [Deployment sequence](deployment-sequence.md).
