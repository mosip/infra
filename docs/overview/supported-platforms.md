# Supported platforms

## Where you can deploy

| Platform | Creates servers | Configures servers | How |
|---|:-:|:-:|---|
| **AWS** | ✅ Terraform | ✅ Ansible | [Quickstart: AWS](../getting-started/quickstart-aws.md) — one workflow run |
| **Data centre** (VMware, OpenStack, bare metal) | — you provide VMs | ✅ Ansible | [Quickstart: data centre](../getting-started/quickstart-datacentre.md) |
| **Azure** | — you provide VMs *(base-infra is a placeholder)* | ✅ Ansible | Data-centre quickstart |
| **GCP** | — you provide VMs *(base-infra is a placeholder)* | ✅ Ansible | Data-centre quickstart |

VM requirements: Ubuntu 24.04, a `ubuntu` user with passwordless sudo, outbound internet.
Air-gapped installs are not supported yet.

## DNS providers

| Provider | Via | Notes |
|---|---|---|
| AWS Route53 | Terraform (default on AWS) or Ansible | Multiple zones, split-horizon, extra records |
| GoDaddy | Ansible | Needs GoDaddy production API access |
| BIND / PowerDNS / Windows DNS | Ansible (RFC 2136) | TSIG key recommended |
| Cloudflare | Ansible | Records are DNS-only (not proxied) |
| Anything else | Manual | Records printed for your DNS team |

See [DNS providers](../guides/dns-providers.md).

## TLS certificates

| Mode | Source | Wildcard | Needs |
|---|---|:-:|---|
| `dns01` (default) | Let's Encrypt, DNS challenge | ✅ | DNS provider API (any certbot plugin) |
| `http01` | Let's Encrypt, HTTP challenge | — | Port 80 open to the internet; public names only |
| `byo` | Your own certificate (national CA, purchased) | as issued | Certificate + key files |

See [TLS certificates](../guides/tls-certificates.md).

## Versions

| Component | Version |
|---|---|
| Ubuntu (hosts) | 24.04 |
| RKE2 | `v1.28.9+rke2r1` (role default) |
| PostgreSQL | 15 |
| Rancher UI | 2.8.3 |
| Terraform | 1.8.5 (CI) |
| AWS provider | 5.48.0 |
