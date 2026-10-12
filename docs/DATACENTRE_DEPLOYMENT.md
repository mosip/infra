# Data-centre deployment (Ansible only, no Terraform)

Deploy the MOSIP cluster layer — nginx + TLS, RKE2, NFS, PostgreSQL, ActiveMQ,
Rancher import — onto **VMs that already exist** (a country data centre,
VMware/OpenStack hand-over, bare metal). No Terraform, no cloud API.

It runs exactly the same Ansible roles, in the same order, as the AWS path;
only the inventory comes from a file you write instead of Terraform outputs.

```
 your hosts.yml ──► ansible/inventory/generate.py --from-hosts ──► inventory.yml
                                                                      │
                     ansible/site.yml ◄───────────────────────────────┘
   preflight → tls + nginx → rke2 → rancher import → nfs → postgresql → activemq
```

After this, deploy MOSIP with the Helmsman workflows as usual.

> **Status:** the inventory generator is unit-tested (it produces the same
> inventory from a hosts file as from Terraform outputs) and `site.yml` is
> syntax-checked for every profile in CI. Do a trial run on throwaway VMs
> before a production deployment.

---

## 1. Prepare the VMs

| Role | Count | Suggested size (`mosip` profile) | Notes |
|------|-------|-----------------------------------|-------|
| nginx | 1 | 8 vCPU / 32 GB, 24 GB root | Reverse proxy, NFS server, PostgreSQL + ActiveMQ host. Needs the data disks below. |
| control-plane | 1 or 3 | 8 vCPU / 32 GB, 64 GB root | The first one listed is the RKE2 primary. |
| etcd | 0 or 3 | 8 vCPU / 32 GB, 64 GB root | Optional dedicated etcd nodes. |
| worker | ≥ 1 | 8 vCPU / 32 GB, 64 GB root | Optional when control-plane nodes run workloads. |

Node counts per profile are in [PROFILES.md](PROFILES.md); the `observ`
profile needs just nginx + one control-plane node.

Every VM must have:

- **Ubuntu 24.04.**
- A user named **`ubuntu`** with passwordless `sudo`, reachable over SSH with
  a key. The roles use `/home/ubuntu` and `become_user: ubuntu`.
- **Outbound internet** (HTTPS) to Ubuntu mirrors, `get.rke2.io`,
  `get.helm.sh`, `github.com` (k8s-infra), `apt.postgresql.org`,
  `releases.rancher.com`, and — for `http01` / `dns01` TLS — Let's Encrypt.
  Air-gapped installs aren't supported yet.
- Its own address unique across the inventory.

**Data disks on the nginx VM** — raw, unmounted block devices:

| Disk | Used by | Variable | Size (`mosip`) |
|------|---------|----------|----------------|
| NFS | always | `nfs_storage_device` | 300 GB |
| PostgreSQL | profiles listing `postgresql` | `storage_device` | 200 GB |
| ActiveMQ | profiles listing `activemq` | `activemq_storage_device` | 30 GB |

> ⚠️ **The roles format a data disk that isn't mounted yet.** Double-check
> each device path with `lsblk` on the nginx VM — a wrong path destroys that
> disk's data. The defaults (`/dev/nvme1n1` …) are AWS names and almost never
> right in a data centre.

**Network** — the same openings the AWS security groups
(`terraform/modules/aws/security`) create; hand this to your firewall team:

| Host | Inbound | Purpose |
|------|---------|---------|
| nginx | 80, 443 (users / internet) | HTTP(S) |
| nginx | 2049 tcp+udp, 5432, 5433, 61616, 9000 (from the cluster) | NFS, PostgreSQL, ActiveMQ, MinIO |
| control-plane | 6443, 9345 | Kubernetes API, RKE2 supervisor |
| control-plane, etcd | 2379, 2380, 2381 | etcd client, peer, metrics |
| all k8s nodes | 10250, 30000-32767, 8472/udp, 9099, 5433 | kubelet, node ports (nginx → ingress), Canal VXLAN + health |
| all | 22 (from the Ansible machine), ICMP | SSH, ping |

All hosts need outbound 80/443 and DNS (53 tcp/udp).

## 2. DNS records (before nginx)

Same order as the legacy deployment: **DNS before nginx.** Two ways:

**Automatic** — set `dns_provider` in `my-hosts.yml` and `site.yml` creates
the records first, then waits for them to resolve:

```yaml
vars:
  dns_provider: godaddy          # godaddy | rfc2136 | cloudflare | route53 | manual
  dns_zone: mosip.gov.example    # zone apex, if cluster_env_domain is a sub-domain of it
  dns_godaddy_key: "<key>"       # better: pass secrets with -e @secrets.yml (vault)
  dns_godaddy_secret: "<secret>"
  # rfc2136 (BIND / PowerDNS / Windows DNS): dns_rfc2136_server, dns_rfc2136_key_name, dns_rfc2136_key_secret
  # cloudflare: dns_cloudflare_api_token
```

`rfc2136` needs `dnspython` and `route53` needs `boto3` on the machine you run
Ansible from. `manual` prints the table below for your DNS team.

**By hand** — leave `dns_provider` unset and have your DNS team create:

| Record | Type | Points to |
|--------|------|-----------|
| `api.<domain>` | A | nginx public / NAT address |
| `api-internal.<domain>` | A | nginx internal address |
| `<domain>` | CNAME | `api-internal.<domain>` |
| each `subdomain_public` | CNAME | `api.<domain>` |
| each `subdomain_internal` | CNAME | `api-internal.<domain>` |

The subdomain lists are in `profiles/<profile>/profile.yml`.

## 3. Choose how nginx gets its TLS certificate

| `tls_mode` | Use when | You provide |
|------------|----------|-------------|
| `byo` | National CA, purchased or internal certificate | `tls_cert_file` (cert + intermediates) and `tls_key_file`, on the Ansible machine |
| `http01` | nginx reachable from the internet on port 80 | `certbot_email`. One cert for the public names only — no wildcard, internal names not covered. |
| `dns01` | Wildcard via your DNS provider's API | `certbot_email`, `dns01_provider`, `dns01_credentials_file` |

`dns01` works with any certbot DNS plugin. Ubuntu-packaged ones (`cloudflare`,
`route53`, `google`, `digitalocean`, `ovh`, `rfc2136`, `linode`, …) install
from apt; others install from pip:

```yaml
tls_mode: dns01
dns01_provider: godaddy
dns01_plugin_install: pip                  # installs certbot-dns-godaddy
dns01_credentials_file: /secure/godaddy.ini
certbot_email: ops@example.org
```

The credentials file is the plugin's own `.ini` format (see the plugin's
docs). For `route53` outside AWS, point it at an AWS shared-credentials file.

## 4. Write the hosts file

```bash
cp ansible/inventory/hosts.example.yml my-hosts.yml
```

```yaml
vars:
  cluster_name: soil38                       # names hosts and the kubeconfig
  cluster_env_domain: soil38.mosip.gov.example

  tls_mode: byo
  tls_cert_file: /secure/fullchain.pem
  tls_key_file: /secure/privkey.pem

  nfs_storage_device: /dev/sdb
  storage_device: /dev/sdc                   # postgresql
  activemq_storage_device: /dev/sdd          # activemq

  dns_expected_ip: 203.0.113.10              # public/NAT address api.<domain> resolves to

  ansible_user: ubuntu
  ansible_ssh_private_key_file: /secure/dc-key

nginx:
  address: 10.10.0.10                        # address Ansible connects to
control_plane: [10.10.1.10, 10.10.1.11, 10.10.1.12]   # first = RKE2 primary
etcd:          [10.10.2.10, 10.10.2.11, 10.10.2.12]   # omit if none
workers:       [10.10.3.10]
```

Anything under `vars:` overrides the profile's defaults
(`ansible_vars` in `profile.yml`) — e.g. `k8s_infra_branch`,
`postgresql_port`. Keep secrets (keys, certificates, passwords) outside the
repo and reference them by path.

## 5. Install Ansible on the machine you deploy from

Any Linux/macOS machine that can SSH to every VM:

```bash
python3 -m pip install ansible-core pyyaml
ansible-galaxy collection install -r ansible/requirements.yml   # community.general, ansible.posix
```

## 6. Generate the inventory

```bash
python3 ansible/inventory/generate.py \
  --profile profiles/mosip \
  --from-hosts my-hosts.yml \
  -o inventory.yml
```

It validates the input (required values, at least one control-plane node, no
duplicate addresses, TLS settings) and writes hosts named like the AWS path
(`soil38-NGINX-NODE`, `soil38-CONTROL-PLANE-NODE-1`, …). Override any value
without editing files with `--set key=value`.

## 7. Deploy

```bash
export ANSIBLE_CONFIG=$PWD/ansible/ansible.cfg
ansible-playbook -i inventory.yml ansible/site.yml
```

The first play, **preflight**, changes nothing. It fails early if a host is
unreachable, a required value is missing, a data disk doesn't exist, or (for
`http01`) `api.<domain>` doesn't resolve to `dns_expected_ip`. For other TLS
modes a DNS mismatch is only a warning. Force it with
`-e preflight_dns_check=fail|warn|skip`.

Then, in order: TLS + nginx → RKE2 → Rancher import (if enabled) → NFS →
PostgreSQL → ActiveMQ → Rancher + Keycloak (`observ` profile only). The
profile decides which of these run; the order never changes.

**Rancher import** (optional, into an existing Rancher):

```bash
ansible-playbook -i inventory.yml ansible/site.yml \
  -e enable_rancher_import=true \
  -e "rancher_import_url='kubectl apply -f https://rancher.example.org/v3/import/<token>.yaml'"
```

Get the command from Rancher UI → Cluster Management → Import Existing →
Generic.

**Observability cluster** (`--profile profiles/observ`): pass the Rancher
bootstrap password from a secret store, not a file in the repo:

```bash
ansible-playbook -i inventory.yml ansible/site.yml -e rancher_password="$RANCHER_BOOTSTRAP_PASSWORD"
```

## 8. After the run

```bash
# kubeconfig (server address = primary node's own IP)
scp -i /secure/dc-key ubuntu@10.10.1.10:/home/ubuntu/.kube/soil38-CONTROL-PLANE-NODE-1.yaml kubeconfig
KUBECONFIG=kubeconfig kubectl get nodes
```

For the Helmsman workflows, add that kubeconfig as the `KUBECONFIG`
environment secret of your branch, and set `ENV_NAME` / `DOMAIN_NAME` to
`cluster_name` / `cluster_env_domain`. The runners need a network path to
the cluster (WireGuard or a self-hosted runner in the data centre).

## Re-running and day-2

- `site.yml` is safe to re-run; completed steps are skipped (existing
  cluster, mounted disks, existing certificate).
- One component only: `ansible-playbook -i inventory.yml ansible/playbooks/<component>.yml`
  (`nginx`, `rke2`, `rancher_import`, `nfs`, `postgresql`, `activemq`,
  `rancher_keycloak`, `preflight`).
- **Add a node:** append its address to `my-hosts.yml`, regenerate the
  inventory, run `ansible/playbooks/rke2.yml`.
- **Rotate a `byo` certificate:** replace the files and re-run
  `ansible/playbooks/nginx.yml` (byo always re-copies).

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `ERROR: missing required variables` from generate.py | `cluster_name` / `cluster_env_domain` under `vars:`; `certbot_email` unless `tls_mode: byo` |
| Preflight: `Data disk(s) not found` | `lsblk` on the nginx VM; fix `*_storage_device` |
| Preflight: `api.<domain> resolves to [...]` | DNS records (step 2), or `dns_expected_ip` behind NAT |
| TLS task fails (`http01`) | Port 80 reachable from the internet, and DNS pointing at nginx |
| TLS task fails (`dns01`) | Plugin name / install method, credentials file format, `dns01_propagation_seconds` |
| RKE2 nodes don't join | Ports 9345 / 6443 between nodes; the first control-plane entry is reachable |
| Downloads time out | Outbound HTTPS to the hosts listed in step 1 |

## Related

- [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md) — order, AWS path, day-2 DNS
- [PROFILES.md](PROFILES.md) — what each profile deploys
- [`ansible/inventory/hosts.example.yml`](../ansible/inventory/hosts.example.yml) — annotated hosts file
