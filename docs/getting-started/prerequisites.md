# Prerequisites

What you need before your first deployment.

## Everyone

- [ ] A **GitHub** account and a fork of `mosip/infra`
- [ ] A **branch for your environment** (e.g. `soil38`) — one branch per environment
- [ ] A **domain** you control (e.g. `soil38.mosip.net`)
- [ ] Read the [Glossary](../glossary/index.md) if terms like WireGuard or DSF are new

## For AWS deployments

### AWS account and permissions

An AWS account with access keys allowed to manage:

- **VPC** — VPCs, subnets, internet / NAT gateways, route tables
- **EC2** — instances, security groups, key pairs, EBS volumes
- **Route 53** — hosted zones and records
- **IAM** — roles, policies, instance profiles
- **S3** *(remote backend only)* — state buckets

A broad policy for getting started:

```json
{
  "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow",
                  "Action": ["ec2:*", "route53:*", "iam:*", "s3:*"],
                  "Resource": "*" }]
}
```

!!! warning "Production"
    Use a narrower policy with specific resource ARNs and conditions for production accounts.

### In the AWS console

- [ ] An **EC2 key pair** in your region — its name is `ssh_key_name`
- [ ] A **Route 53 hosted zone** for your domain — its ID is `zone_id`
      *(not needed if you use another [DNS provider](../guides/dns-providers.md))*

### Instance sizes

| Role | Default | Smaller (dev) | Larger (load) |
|---|---|---|---|
| Kubernetes nodes | `t3a.2xlarge` (8 vCPU, 32 GiB) | `t3a.large` | `t3a.4xlarge` |
| nginx | `t3a.2xlarge` (hosts PostgreSQL) | `t3a.xlarge` without external PostgreSQL | — |

Set them in `profiles/<profile>/aws/compute.tfvars`.

## For data-centre deployments

- [ ] Ubuntu 24.04 VMs — see sizes in the [data-centre quickstart](quickstart-datacentre.md)
- [ ] A `ubuntu` user with passwordless sudo and SSH key access on every VM
- [ ] Outbound HTTPS from the VMs (packages, RKE2, Helm, GitHub)
- [ ] Raw data disks on the nginx VM (NFS, and PostgreSQL / ActiveMQ if used)
- [ ] Firewall rules between the VMs
- [ ] A machine with Ansible ≥ 2.15 and Python 3 that can SSH to all VMs

## Before you deploy

Check the services the deployment depends on are up:

- GitHub — [githubstatus.com](https://www.githubstatus.com)
- Let's Encrypt (for `dns01` / `http01`) — [letsencrypt.status.io](https://letsencrypt.status.io)

**Next:** [Secrets & configuration](secrets.md)
