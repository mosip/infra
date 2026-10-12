# Ansible roles

`ansible/site.yml` runs the roles in a fixed order. A profile's `configure_components` selects
which run. Every role can also be run alone with `ansible/playbooks/<role>.yml`.

Variables are set, lowest to highest precedence: role defaults → profile `ansible_vars` →
`hosts.yml` `vars:` / tfvars identity values → `--set` / `-e`.

| Order | Role | Runs on | Purpose |
|:-:|---|---|---|
| 0 | `dns` | controller | DNS records via a provider (only when `dns_provider` ≠ `none`) |
| 1 | `preflight` | nginx | Read-only checks before any change |
| 2 | `tls` | nginx | Certificate into `/etc/letsencrypt/live/<domain>/` |
| 2 | `nginx` | nginx | k8s-infra nginx install |
| 3 | `rke2` | all nodes | RKE2 primary, then other nodes in parallel |
| 4 | `rancher_import` | primary node | Import into Rancher |
| 5 | `nfs` | nginx | NFS server on the data disk + NFS CSI |
| 6 | `postgresql` | nginx | PostgreSQL on its own disk, Kubernetes secret |
| 7 | `activemq` | nginx | ActiveMQ NFS storage + StorageClass |
| 8 | `rancher_keycloak` | primary node | Rancher UI + Keycloak (observ) |

## Key variables

### Common (every deployment)

| Variable | Where | Description |
|---|---|---|
| `cluster_name`, `cluster_env_domain` | tfvars / `hosts.yml` | Identity; host names derive from `cluster_name` |
| `k8s_infra_repo_url`, `k8s_infra_branch` | profile | k8s-infra source for nginx/RKE2 scripts |
| `configure_components` | profile | Components to run |
| `ansible_user` | generator | Must be `ubuntu` |

### dns

| Variable | Default | |
|---|---|---|
| `dns_provider` | `none` | `none`, `route53`, `godaddy`, `rfc2136`, `cloudflare`, `manual` |
| `dns_state` | `present` | `absent` removes the records |
| `dns_zone` | `cluster_env_domain` | Zone apex |
| `dns_ttl` | `300` | GoDaddy enforces a minimum of 600 |
| `dns_extra_records` | `[]` | `{name, type, value, ttl}` |
| `dns_godaddy_key`, `dns_godaddy_secret` | — | GoDaddy API |
| `dns_rfc2136_server`, `dns_rfc2136_key_name`, `dns_rfc2136_key_secret`, `dns_rfc2136_key_algorithm` | —, —, —, `hmac-sha256` | RFC 2136 / TSIG |
| `dns_cloudflare_api_token` | — | Cloudflare API |

### preflight

| Variable | Default | |
|---|---|---|
| `preflight_dns_check` | `auto` | `auto` (fail for http01, warn otherwise), `fail`, `warn`, `skip` |
| `dns_expected_ip` | `nginx_public_ip` | Address `api.<domain>` must resolve to |
| `preflight_dns_retries` | 30 with a DNS provider, else 0 | 10 s apart |

### tls

| Variable | Default | |
|---|---|---|
| `tls_mode` | `dns01` | `dns01`, `http01`, `byo` |
| `dns01_provider` | `route53` | Any certbot DNS plugin |
| `dns01_plugin_install` | `apt` | `pip` for plugins Ubuntu doesn't package (e.g. godaddy) |
| `dns01_credentials_file` | — | Plugin credentials (.ini) on the controller |
| `dns01_propagation_seconds` | `60` | |
| `tls_cert_file`, `tls_key_file` | — | `byo` certificate files on the controller |
| `certbot_email` | — | Required for `dns01` / `http01` |

### Data disks

| Variable | Default (AWS) | Role |
|---|---|---|
| `nfs_storage_device` | `/dev/nvme1n1` | nfs |
| `storage_device` | `/dev/nvme2n1` | postgresql |
| `activemq_storage_device` | `/dev/nvme3n1` | activemq |

!!! danger
    A data disk that isn't mounted yet is **formatted**. Set these to the real devices on your VMs.

### Others

| Role | Variables |
|---|---|
| nginx | `nginx_type` (`mosip` / `observability`), node ports `cluster_ingress_*_nodeport`, `observation_ingress_nodeport`, `working_dir` |
| rke2 | `rke2_version` (`v1.28.9+rke2r1`), `rke2_config_dir` |
| nfs | `nfs_server_location` (`/srv/nfs`), `helm_version` |
| postgresql | `postgresql_version` (`15`), `postgresql_port` (`5433`), `mount_point` (`/srv/postgres`) |
| activemq | `activemq_mount_point` (`/srv/activemq`), `activemq_nfs_allowed_hosts` (`*`), `activemq_storageclass_name` |
| rancher_import | `enable_rancher_import`, `rancher_import_url` |
| rancher_keycloak | `rancher_password` (required), `rancher_ui_version` (`2.8.3`), `rancher_hostname`, `keycloak_hostname` |

Full defaults: `ansible/roles/<role>/defaults/main.yml`.
