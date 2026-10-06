# profile.yml & hosts.yml

## profile.yml

`profiles/<profile>/profile.yml` describes a deployment shape. It is read by the inventory
generator (both paths) and by the Terraform `dns` component (subdomains).

```yaml
name: mosip
description: Full MOSIP platform
nginx_type: mosip                       # mosip | observability
configure_components:                   # which Ansible components run (order is fixed by site.yml)
  - nginx
  - rke2
  - rancher_import
  - nfs
  - postgresql
  - activemq
subdomain_public: [resident, prereg, esignet, healthservices, signup]
subdomain_internal: [admin, iam, activemq, kafka, kibana, postgres, smtp, pmp, minio, regclient, compliance]
ansible_vars:                           # lowest-precedence Ansible values
  k8s_infra_repo_url: https://github.com/mosip/k8s-infra.git
  k8s_infra_branch: release-1.2.1.x
  tls_mode: dns01
  dns01_provider: route53
```

| Key | Required | Description |
|---|:-:|---|
| `name` | ✓ | Profile name (folder name) |
| `nginx_type` | ✓ | `mosip` or `observability` |
| `configure_components` | ✓ | Any of `nginx`, `rke2`, `rancher_import`, `nfs`, `postgresql`, `activemq`, `rancher_keycloak` |
| `subdomain_public` / `subdomain_internal` | | DNS names → `api` / `api-internal` |
| `ansible_vars` | | Defaults for any [role variable](ansible-roles.md) |

On AWS, `postgresql` and `activemq` are also skipped automatically when the storage component
didn't create their disk.

## hosts.yml (data centre)

Written by the operator; turned into the inventory by
`generate.py --from-hosts`. Template: `ansible/inventory/hosts.example.yml`.

```yaml
vars:                                   # any Ansible variable
  cluster_name: soil38
  cluster_env_domain: soil38.mosip.gov.example
  tls_mode: byo
  tls_cert_file: /secure/fullchain.pem
  tls_key_file: /secure/privkey.pem
  nfs_storage_device: /dev/sdb
  ansible_user: ubuntu
  ansible_ssh_private_key_file: /secure/dc-key
nginx:
  address: 10.10.0.10                   # required
  public_ip: 203.0.113.10               # optional
control_plane: [10.10.1.10, 10.10.1.11, 10.10.1.12]   # required; first = RKE2 primary
etcd: [10.10.2.10]                      # optional
workers: [10.10.3.10]                   # optional
```

The generator checks: `cluster_name` and `cluster_env_domain` set, at least one control-plane
node, no duplicate addresses, valid `tls_mode` with its required values.

!!! tip
    Append new nodes at the end of a list. Host names follow list position
    (`<cluster>-CONTROL-PLANE-NODE-1`, …), so re-ordering renames nodes.

## Generated inventory

Both inputs produce the same structure:

```yaml
all:
  vars: { cluster_name, cluster_env_domain, configure_components, nginx_type,
          subdomain_public, subdomain_internal, public_domain_list,
          k8s_node_ips_joined, k8s_primary_control_plane_ip, nginx_public_ip, … }
  children:
    nginx:          { hosts: { <cluster>-NGINX-NODE: { ansible_host } } }
    control_plane:  { hosts: { <cluster>-CONTROL-PLANE-NODE-<n>: { ansible_host, node_role } } }
    etcd:           { … }
    workers:        { … }
    rke2_cluster:   { children: { control_plane, etcd, workers } }
```
