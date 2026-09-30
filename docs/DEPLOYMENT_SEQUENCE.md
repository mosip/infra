# Deployment sequence

MOSIP infrastructure is built in layers. Each Terraform component has its own
state and can be run on its own; Layer 3 is Ansible and runs identically on
AWS and on data-centre VMs.

```
            AWS (Terraform, one state each)                    Data centre
 ┌──────────────────────────────────────────────────┐   ┌─────────────────────┐
 │ security → compute → iam → storage → dns          │   │ pre-created VMs      │
 └───────────────┬──────────────────────────────────┘   │ + hosts.yml          │
                 │ terraform output (compute, storage)   └──────────┬──────────┘
                 ▼                                                  ▼
          ansible/inventory/generate.py --from-terraform | --from-hosts
                                   │  (same inventory either way)
                                   ▼
        ansible/site.yml:  preflight → tls+nginx → rke2 → rancher import
                           → nfs → postgresql → activemq → rancher+keycloak
```

The order is the legacy monolith's `depends_on` chain, kept on purpose:

| # | Step | AWS | Data centre | Must be true before the next step |
|---|------|-----|-------------|-----------------------------------|
| 1 | security | `COMPONENT=security` | firewall prepared by the DC team | security groups exist |
| 2 | compute | `COMPONENT=compute` | VMs handed over | hosts reachable over SSH |
| 3 | iam | `COMPONENT=iam` (certbot Route53 profile) | not needed; DNS-01 credentials replace it | nginx can update Route53 |
| 4 | storage | `COMPONENT=storage` (EBS) | disks already attached | data disks visible (`lsblk`) |
| 5 | **dns** | `COMPONENT=dns` | DNS team, or `COMPONENT=dns` if the zone is Route53 | `api.<domain>` resolves to nginx |
| 6 | tls + nginx | configure | `site.yml` | certificate in `/etc/letsencrypt/live/<domain>/` |
| 7 | rke2 | configure | `site.yml` | nodes `Ready` |
| 8 | rancher import / rancher+keycloak | configure | `site.yml` | |
| 9 | nfs → postgresql → activemq | configure | `site.yml` | |

`site.yml` owns the Layer-3 order. A profile only picks which components run
(`configure_components` in `profiles/<name>/profile.yml`).

## Why DNS comes before nginx

| TLS mode | Is DNS needed before nginx? |
|----------|-----------------------------|
| `http01` | **Yes, hard requirement.** Let's Encrypt connects to each name on port 80. Preflight fails the run if `api.<domain>` doesn't resolve to the expected address. |
| `dns01` (default) | Not for the certificate (the challenge only needs the zone + API access), but nginx vhosts and every app behind them do. Preflight warns. |
| `byo` | Same as dns01: not for the certificate, but for everything after. Preflight warns. |

Force the behaviour with `preflight_dns_check: fail | warn | skip`. On a NAT'd
data centre, set `dns_expected_ip` to the public address.

## AWS: running it

Actions → **terraform plan / apply**:

- `COMPONENT=all` + `TERRAFORM_APPLY` — everything above, in order, stopping at
  the first failure. Destroy is **terraform destroy** with `COMPONENT=all`
  (reverse order: dns → storage → iam → compute → security).
- `COMPONENT=<one>` — just that component. With `TERRAFORM_APPLY` unchecked it
  only plans. Use this for day-2 changes:
  - DNS records only → `COMPONENT=dns`
  - resize / add nodes → `COMPONENT=compute`, then `COMPONENT=configure`
  - re-run Ansible → `COMPONENT=configure`

Each Terraform component only calls AWS APIs; only `configure` needs
WireGuard (it SSHes into the private nodes).

## Data centre

No Terraform. On any machine that can SSH to the VMs:

```bash
cp ansible/inventory/hosts.example.yml my-hosts.yml   # IPs, disks, TLS mode, SSH key
python3 ansible/inventory/generate.py --profile profiles/mosip \
    --from-hosts my-hosts.yml -o inventory.yml
ansible-playbook -i inventory.yml ansible/site.yml
```

Requirements: Ansible ≥ 2.15 with PyYAML, Ubuntu 24.04 on the VMs, the DNS
records in place (step 5), and one of:

- `tls_mode: byo` + `tls_cert_file` / `tls_key_file` (national CA, purchased cert)
- `tls_mode: http01` (public port 80, no wildcard, public names only)
- `tls_mode: dns01` + `dns01_provider` + `dns01_credentials_file`
  (any certbot DNS plugin; GoDaddy needs `dns01_plugin_install: pip`)

Data disks default to AWS NVMe names; set `nfs_storage_device`,
`storage_device` (postgresql) and `activemq_storage_device` to your devices.
Preflight checks they exist before anything is changed.

Run a single component with its own playbook, e.g.
`ansible-playbook -i inventory.yml ansible/playbooks/nfs.yml` — but the first
run should always be `site.yml`.

## Checks

The `infra checks` workflow runs on every PR, with no credentials:

```bash
terraform fmt -check -recursive terraform
(cd terraform/modules/aws/<module> && terraform init -backend=false && terraform test)
(cd terraform/implementations/aws/<component> && terraform init -backend=false && terraform validate)
python3 -m unittest discover -s ansible/inventory/tests
python3 ansible/inventory/generate.py --profile profiles/mosip \
    --from-hosts ansible/inventory/hosts.example.yml -o /tmp/inv.yml
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i /tmp/inv.yml ansible/site.yml --syntax-check
```
