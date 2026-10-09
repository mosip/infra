# Repository tree

State files (`*.tfstate*`, `*.gpg`), `.terraform/` caches and lockfiles are
omitted. For the deployment order see [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md);
for Ansible-only deployment onto existing VMs see [DATACENTRE_DEPLOYMENT.md](DATACENTRE_DEPLOYMENT.md).

## Top level

```
.
├── .github/          # workflows + backend/state/Rancher helper scripts
├── ansible/          # Layer 3 — provider-agnostic configuration (AWS and data centre)
├── profiles/         # deployment shapes: mosip, esignet-standalone, observ
├── terraform/        # Layers 1–2 — cloud provisioning (AWS today)
├── Helmsman/         # Desired State Files, hooks and values for MOSIP services
├── Rancher-keycloak-integration/
├── docs/
└── README.md
```

## `profiles/`

```
profiles/<mosip|esignet-standalone|observ>/
├── profile.yml                  # components to configure, subdomains (single source), Ansible defaults
└── aws/                         # Terraform values for the AWS roots
    ├── common.tfvars            # cluster_name, domain, region, zone, AMI, VPC, CIDRs
    ├── security.tfvars  iam.tfvars
    ├── compute.tfvars           # instance types, node counts
    ├── storage.tfvars           # EBS data volumes (0 = off)
    ├── dns.tfvars               # optional: extra zones / records
    └── vm.tfvars                # optional: standalone EC2 groups (COMPONENT=vm)
```

## `terraform/`

```
terraform/
├── base-infra/                  # one-time VPC/subnets/WireGuard module (aws, azure, gcp)
├── modules/aws/
│   ├── security/  iam/  compute/  storage/  dns/
│   │   └── {main,variables,outputs}.tf + tests/main.tftest.hcl
│   ├── instance-group/          # generic EC2 + SG + IAM per workload (used by the vm root)
│   └── compute/rke-user-data.sh.tpl
└── implementations/             # roots — one state each
    ├── aws/{base-infra,security,iam,compute,storage,dns,vm}/   # dns and vm have tests/ too
    ├── azure/base-infra/
    └── gcp/base-infra/
```

## `ansible/`

```
ansible/
├── ansible.cfg                  # roles_path = ./roles
├── site.yml                     # ordered entrypoint: preflight → nginx → rke2 → rancher import
│                                #   → nfs → postgresql → activemq → rancher+keycloak
├── inventory/
│   ├── generate.py              # --from-terraform (AWS) | --from-hosts (data centre)
│   ├── hosts.example.yml        # what a data-centre operator fills in
│   └── tests/test_generate.py
├── playbooks/                   # one per component, for running a single step
│   └── dns.yml preflight.yml nginx.yml rke2.yml rancher_import.yml nfs.yml
│       postgresql.yml activemq.yml rancher_keycloak.yml
└── roles/
    ├── dns/                     # DNS records via godaddy | rfc2136 | cloudflare | route53 | manual (+ tests/)
    ├── preflight/               # SSH, required vars, data disks, DNS gate
    ├── tls/                     # byo | http01 | dns01 (any certbot DNS plugin)
    ├── nginx/  rke2/  rancher_import/  nfs/  postgresql/  activemq/
    └── rancher_keycloak/        # Rancher UI + Keycloak (observ profile)
```

## `.github/`

```
.github/
├── workflows/
│   ├── terraform.yml            # dispatch: all | one component | configure | vm | base-infra
│   ├── terraform-destroy.yml    # dispatch: reverse-order destroy
│   ├── terraform-component.yml  # reusable: plan/apply/destroy one root
│   ├── infra-checks.yml         # PR checks: fmt, validate, terraform test, generator tests, syntax
│   ├── helmsman_*.yml, k8s_health_check.yml, keycloak-rancher-integration.yml, wg-onboard.yml, ...
│   └── README.md
└── scripts/
    ├── configure-backend.sh, setup-cloud-storage.sh, cleanup-state-locking.sh
    ├── setup-gpg.sh, encrypt-state.sh, decrypt-state.sh
    ├── rancher-register-cluster.sh, rancher-grant-cluster-access.sh, rancher-fetch-kubeconfig.sh
    ├── wg-env.sh, wg-peer-allocation.tsv
    ├── test-state-locking.sh, test-cleanup-state-locking.sh
    └── README.md
```

## Not done yet

- Azure / GCP component roots (only `base-infra` exists). Data-centre VMs are
  covered without Terraform through `--from-hosts`.
- Terraform DNS providers other than Route53. TLS already works with any
  certbot DNS plugin (GoDaddy, Cloudflare, …); DNS records for those
  registrars are created outside Terraform for now.
