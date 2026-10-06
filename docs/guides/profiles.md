# Profiles

A **profile** is a deployment shape: which Layer-3 components run, the DNS
names, and (for AWS) the sizes. It is independent of where the deployment
runs — the same profile drives an AWS environment and a data-centre one.

```
profiles/<name>/
├── profile.yml            # shape — read by the inventory generator (both paths)
└── aws/                   # AWS values — read by the Terraform roots
    ├── common.tfvars      # shared by every component (cluster_name, domain, region, zone, ...)
    ├── security.tfvars
    ├── compute.tfvars     # instance types, node counts
    ├── iam.tfvars
    ├── storage.tfvars     # data volumes (0 = don't create)
    └── dns.tfvars         # optional: extra zones / records (subdomains are in profile.yml)
```

| Profile | Nodes (cp/etcd/worker) | Layer 3 | nginx |
|---------|------------------------|---------|-------|
| `mosip` | 3 / 3 / 1 | nginx, rke2, rancher_import, nfs, postgresql, activemq | mosip |
| `esignet-standalone` | 1 / 1 / 2 | nginx, rke2, rancher_import, nfs | mosip |
| `observ` | 1 / 0 / 0 | nginx, rke2, nfs, rancher_keycloak | observability |

`observ` used to be a separate `observ-infra` tree whose Terraform was
identical to `infra`; only its sizes and Layer-3 components differ, which is
exactly what a profile expresses.

## profile.yml

```yaml
name: mosip
nginx_type: mosip                 # mosip | observability (k8s-infra nginx flavour)
configure_components: [nginx, rke2, rancher_import, nfs, postgresql, activemq]
subdomain_public: [resident, prereg, ...]
subdomain_internal: [admin, iam, ...]
ansible_vars:                     # Ansible defaults for this shape (e.g. dns_provider)
  k8s_infra_branch: release-1.2.1.x
  tls_mode: dns01
  dns01_provider: route53
```

- `configure_components` selects components; `ansible/site.yml` decides the
  order. Valid names: `nginx`, `rke2`, `rancher_import`, `nfs`, `postgresql`,
  `activemq`, `rancher_keycloak`.
- On AWS, `postgresql` / `activemq` are also skipped automatically when the
  storage component didn't create their volume.
- `ansible_vars` are the lowest-precedence Ansible values. `hosts.yml` vars
  (data centre), tfvars identity values (AWS) and `--set` override them.

## Environments vs profiles

A profile is the shape; an environment is one deployment of it. As before,
an environment is a git branch (GitHub environment of the same name) with the
profile's placeholder values filled in. State keys include both
(`aws-<component>-<profile>-<branch>`), so an `observ` and a `mosip`
deployment on the same branch never share state.

## Adding a profile

1. Copy the closest `profiles/<name>/` directory.
2. Adjust `profile.yml` (components, subdomains) and the `aws/*.tfvars`
   (sizes, volumes).
3. Add the name to the `PROFILE` options in `.github/workflows/terraform.yml`
   and `terraform-destroy.yml`.
4. The `infra checks` workflow syntax-checks `site.yml` against every profile.

No Terraform or Ansible code changes are needed for a new shape.
