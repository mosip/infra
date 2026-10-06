# MOSIP Terraform Infrastructure

Terraform provisions cloud resources (Layers 1–2). Everything that runs *on*
the hosts — nginx, TLS, RKE2, NFS, PostgreSQL, ActiveMQ, Rancher/Keycloak — is
Ansible (Layer 3, [`../ansible`](../ansible)), which works the same on
Terraform-provisioned AWS hosts and on pre-created data-centre VMs.

See [docs/overview/deployment-sequence.md](../docs/overview/deployment-sequence.md) for the full
order and [docs/guides/profiles.md](../docs/guides/profiles.md) for deployment shapes.

## Layout

```
terraform/
├── base-infra/                    # one-time VPC, subnets, WireGuard jump server (aws/azure/gcp)
├── modules/aws/                   # reusable modules, each with tests/*.tftest.hcl
│   ├── security/                  # security groups: nginx, control-plane, etcd, worker
│   ├── compute/                   # EC2: nginx + RKE2 nodes (for_each by node name)
│   ├── iam/                       # certbot Route53 role + instance profile (zone-scoped)
│   ├── storage/                   # EBS data volumes on the nginx node (nfs / postgres / activemq)
│   ├── dns/                       # Route53 records: multi-zone, extra records
│   └── instance-group/            # generic EC2 + SG + IAM per workload (vm root)
└── implementations/               # roots — what CI applies; one state each
    ├── aws/
    │   ├── base-infra/
    │   └── security/  iam/  compute/  storage/  dns/  vm/
    ├── azure/base-infra/
    └── gcp/base-infra/
```

Values live outside `terraform/`, per deployment shape:
`profiles/<profile>/aws/{common,<component>}.tfvars`.

## Components

| Root | Creates | Needs first | Finds the previous layer by |
|------|---------|-------------|-----------------------------|
| `security` | 4 security groups | base-infra VPC | VPC `Name` tag |
| `iam` | certbot role + instance profile (Route53, scoped to the zone) | — | — |
| `compute` | nginx + RKE2 EC2 instances; nginx gets the certbot profile at creation | security, iam | SG tags `Cluster` + `Role`; profile name |
| `storage` | EBS volumes attached to nginx | compute | instance tags `Cluster` + `Role=nginx` |
| `dns` | Route53 records → nginx (any number of zones, extra records). Other DNS providers: the Ansible `dns` role (`DNS_PROVIDER`) | compute | instance tags (or explicit IPs) |
| `vm` | standalone EC2 groups, each with its own SG + IAM (`modules/aws/instance-group`) | base-infra VPC | VPC `Name` tag |

Components discover each other through tags, never shared state, so each can
be planned, applied or destroyed on its own. Only the order matters:
`security → iam → compute → storage → dns` to create, the reverse to destroy.
`vm` is independent and never part of `COMPONENT=all`.

## Running

Through GitHub Actions (**terraform plan / apply**):

| Input | Values |
|-------|--------|
| `COMPONENT` | `all` (everything in order + Ansible), one component, `configure` (Ansible only), `base-infra` |
| `PROFILE` | `mosip`, `esignet-standalone`, `observ` |
| `TERRAFORM_APPLY` | unchecked = plan only; required for `all` / `configure` |

Locally, from a root:

```bash
cd terraform/implementations/aws/compute
terraform init
terraform plan \
  -var-file=../../../../profiles/mosip/aws/common.tfvars \
  -var-file=../../../../profiles/mosip/aws/compute.tfvars
```

## State

Each root × profile × branch has its own state:
`{provider}-{component}-{profile}-{branch}-terraform.tfstate`
(`base-infra`: `{provider}-base-infra-{branch}-terraform.tfstate`).

- **Local backend (default):** the workflow GPG-encrypts the state
  (`GPG_PASSPHRASE` secret) and commits only the `.gpg` file to the branch,
  e.g. `terraform/implementations/aws/compute/profiles/mosip/aws-compute-mosip-<branch>-terraform.tfstate.gpg`.
  Plain `.tfstate` files are never committed.
- **Remote backend:** `REMOTE_BACKEND_CONFIG` = `aws:<bucket_base>:<region>`
  (or Azure / GCS). One bucket per component, state key as above; enable
  `ENABLE_STATE_LOCKING` for shared environments.

## Tests

Module tests use mocked providers and `command = plan`, so they need no
credentials:

```bash
cd terraform/modules/aws/dns && terraform init -backend=false && terraform test
```

CI runs them, `terraform fmt -check` and `terraform validate` on every root in
the `infra checks` workflow.

## Adding another provider

A provider (Azure, GCP, a hypervisor API, …) is a new
`modules/<provider>/<component>` + `implementations/<provider>/<component>`.
The only contract with Layer 3 is the compute outputs
(`nginx_public_ip`, `nginx_private_ip`, `k8s_node_ips` — see
`modules/aws/compute/outputs.tf`); `ansible/inventory/generate.py` turns them
into the inventory. Data-centre VMs that already exist need no provider at
all.
