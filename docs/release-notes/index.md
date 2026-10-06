# Release notes

## Infra decoupling (#273) — next release

A new way to deploy MOSIP infrastructure: independent components, provider-agnostic setup, and
support for data centres. Released as a **new feature** — new environments use the new layout;
no migration is involved.

### Highlights

- **Deploy anywhere.** Terraform creates servers on AWS; Ansible configures any Ubuntu VMs —
  AWS, data centre, Azure or GCP.
- **Independent components.** `security`, `iam`, `compute`, `storage`, `dns` — each with its own
  state. `COMPONENT=all` runs them in order; destroy runs in reverse.
- **Profiles.** `mosip`, `esignet-standalone`, `observ` describe the deployment shape; the
  observability cluster is now a profile instead of a separate code tree.
- **DNS with any provider.** Route53 (multi-zone, extra records) via Terraform, or GoDaddy,
  Cloudflare, BIND / PowerDNS / Windows DNS (RFC 2136) and manual via Ansible.
- **TLS your way.** Own certificate, Let's Encrypt HTTP-01, or DNS-01 through any provider.
- **Standalone VMs.** `COMPONENT=vm` creates servers with their own security group and IAM.
- **Safer runs.** Pre-flight checks (SSH, values, disks, DNS) before any change; IAM before
  compute; certbot IAM limited to your zone; Rancher password moved out of git.
- **Documentation site.** This site.

### Changed

- Workflow inputs: `COMPONENT` and `PROFILE` replace `TERRAFORM_COMPONENT`,
  `PROVISIONING_COMPONENT` and `INFRA_PROFILE`. New: `DNS_PROVIDER`.
- Values moved to `profiles/<profile>/aws/*.tfvars` and `profiles/<profile>/profile.yml`.

### Removed

- The `aws-resource-creation` monolith, the `terraform/infra` and `terraform/observ-infra`
  wrappers, and the setup modules that ran scripts from Terraform.
- Azure/GCP `infra` placeholder roots (they created no resources).

### Fixed

- Ansible role defaults were never loaded.
- Self-referencing Rancher/Keycloak variables.
- Decoupled components had no destroy path.
- Rancher bootstrap password committed in tfvars.
- certbot IAM policy allowed changes to every hosted zone.

### Pull requests

| PR | Issues |
|---|---|
| [#406](https://github.com/mosip/infra/pull/406) Decoupled Terraform roots + tests | #274–#277 |
| [#407](https://github.com/mosip/infra/pull/407) Agnostic Ansible layer | #278–#281, #301 |
| [#408](https://github.com/mosip/infra/pull/408) Per-component roots, profiles, new CI | #282 |
| [#409](https://github.com/mosip/infra/pull/409) Multi-zone Route53, scoped certbot IAM | #353 |
| [#410](https://github.com/mosip/infra/pull/410) IAM before compute, standalone VM | #405 |
| [#411](https://github.com/mosip/infra/pull/411) Data-centre guide, docs aligned | #352 |
| [#415](https://github.com/mosip/infra/pull/415) DNS records with any provider | #414 |
| Documentation site | #416 |
