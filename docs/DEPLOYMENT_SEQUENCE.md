# Deployment sequence

MOSIP infrastructure is built in layers. Each Terraform component has its own
state and can be run on its own; Layer 3 is Ansible and runs identically on
AWS and on data-centre VMs.

```
            AWS (Terraform, one state each)                    Data centre
 ┌──────────────────────────────────────────────────┐   ┌─────────────────────┐
 │ security → iam → compute → storage → dns          │   │ pre-created VMs      │
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
| 2 | iam | `COMPONENT=iam` (certbot Route53 profile) | not needed; DNS-01 credentials replace it | instance profile exists |
| 3 | compute | `COMPONENT=compute` (nginx gets the profile at creation) | VMs handed over | hosts reachable over SSH |
| 4 | storage | `COMPONENT=storage` (EBS) | disks already attached | data disks visible (`lsblk`) |
| 5 | **dns** | `COMPONENT=dns` (Route53), or the Ansible `dns` play for other providers | Ansible `dns` play (`dns_provider`), or the DNS team | `api.<domain>` resolves to nginx |
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
  (reverse order: dns → storage → compute → iam → security).
- `COMPONENT=<one>` — just that component. With `TERRAFORM_APPLY` unchecked it
  only plans. Use this for day-2 changes:
  - DNS records only → `COMPONENT=dns`
  - resize / add nodes → `COMPONENT=compute`, then `COMPONENT=configure`
  - re-run Ansible → `COMPONENT=configure`

Each Terraform component only calls AWS APIs; only `configure` needs
WireGuard (it SSHes into the private nodes).

## Day-2: DNS only

`COMPONENT=dns` touches nothing but Route53 records (its own state):

- **Subdomains:** edit `subdomain_public` / `subdomain_internal` in
  `profiles/<profile>/profile.yml` (single source for AWS and data centre).
- **Other zones:** any number of hosted zones in the same account, by ID or
  by name, in `profiles/<profile>/aws/dns.tfvars`:

  ```hcl
  zones = {
    public   = { name = "mosip.example.org" }
    internal = { name = "mosip.example.org", private = true }  # split-horizon
    partner  = { zone_id = "Z0123456789ABCDEFGHI" }
  }
  public_zone   = "public"    # api + public subdomains
  internal_zone = "internal"  # api-internal, bare domain, internal subdomains
  ```

  Moving internal names into a private zone stops publishing private IPs in
  public DNS. A record's name must be inside its zone's domain.
- **Any other record** (TXT, MX, CAA, A to another host):
  `extra_records = { verify = { name = "...", type = "TXT", records = ["..."], zone = "partner" } }`.
  These default to `allow_overwrite = false`.
- **Targets:** the running nginx instance by tag, or `nginx_public_ip` /
  `nginx_private_ip` — e.g. a data-centre nginx whose domain is in Route53.
- **Certbot:** the `iam` component only lets nginx change records in
  `zone_id` (or `certbot_zone_ids`) — list the zone that holds
  `cluster_env_domain` if you split zones.

## Standalone EC2 (`COMPONENT=vm`)

For machines outside the cluster — bastion, tools box, a reporting DB —
`profiles/<profile>/aws/vm.tfvars` holds `instance_groups`. Each group gets
its own security group (ingress by CIDR or from another group), IAM role and
instance profile (managed policy ARNs and/or inline JSON) and `count`
instances, all in one apply and one state. IMDSv2 and encrypted root volumes
are enforced; SSH from `0.0.0.0/0` is rejected unless
`allow_ssh_from_anywhere = true`. Instances are tagged `Cluster` /
`Role=<group>`, so `extra_records` in the dns component can name them.
`vm` is never part of `COMPONENT=all`; `terraform destroy` with
`COMPONENT=all` does remove it.

## DNS providers

Who creates the records is one setting — `DNS_PROVIDER` in the workflow, or
`dns_provider` in Ansible (profile `ansible_vars`, `hosts.yml`, or `-e`):

| Provider | Records created by | Needs |
|----------|--------------------|-------|
| `terraform-route53` (workflow default) / `none` (Ansible default) | Terraform `dns` component on AWS, or your DNS team | Route53 zone (`zone_id`) |
| `route53` | Ansible `dns` role (`amazon.aws.route53`) | AWS credentials + boto3 on the controller |
| `godaddy` | Ansible `dns` role (GoDaddy REST API) | `GODADDY_API_KEY`, `GODADDY_API_SECRET` |
| `rfc2136` | Ansible `dns` role (`nsupdate`) — BIND, PowerDNS, Windows DNS, most enterprise DNS | `DNS_RFC2136_SERVER` (+ TSIG `DNS_RFC2136_KEY_NAME` / `_KEY_SECRET`), dnspython |
| `cloudflare` | Ansible `dns` role | `CLOUDFLARE_API_TOKEN` |
| `manual` | your DNS team — the play prints the exact table | — |

- The `dns` play runs first in `site.yml`, so the order stays DNS → nginx;
  preflight then waits (up to ~5 min) for the records to resolve.
- Same records as the Terraform module (api, api-internal, bare domain,
  subdomains from `profile.yml`), plus `dns_extra_records`. Set `dns_zone`
  when the zone apex differs from `cluster_env_domain`.
- On AWS with a non-Route53 provider, `COMPONENT=all` skips the Route53-only
  `iam` and `dns` components and nginx gets no certbot Route53 profile. With
  the profile's default `tls_mode: dns01` the certificate is issued through
  the same provider (CI writes the certbot credentials). For `manual`, set
  `tls_mode` to `byo` or `http01` in the profile.
- Remove records: `ansible-playbook -i inventory.yml ansible/playbooks/dns.yml -e dns_state=absent`.

## Data centre

Step-by-step guide: **[DATACENTRE_DEPLOYMENT.md](DATACENTRE_DEPLOYMENT.md)**. In short — no Terraform; on any machine that can SSH to the VMs:

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
