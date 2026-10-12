# Terraform components

Every AWS component is a Terraform root under `terraform/implementations/aws/<component>/` with
its own state. Values come from `profiles/<profile>/aws/common.tfvars` (shared) plus
`profiles/<profile>/aws/<component>.tfvars`. Roots ignore shared values they don't declare.

Apply order: `security → iam → compute → storage → dns`. Destroy in reverse. `vm` is independent.

## security

Creates the four security groups: nginx, control-plane, etcd and worker.

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | required | Tags every security group |
| `aws_provider_region` | required | AWS region |
| `vpc_name` | required | VPC `Name` tag (created by base-infra) |
| `network_cidr` | required | VPC CIDR, for internal rules |
| `WIREGUARD_CIDR` | required | CIDR your WireGuard clients come from |

**Outputs:** `nginx_sg_id`, `k8s_control_plane_sg_id`, `k8s_etcd_sg_id`, `k8s_worker_sg_id`

## iam

Creates the certbot role, a Route53 policy scoped to your zone(s), and the instance profile
`<cluster_name>-certbot-instance-profile`.

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | required | Names the role and profile |
| `aws_provider_region` | required | AWS region |
| `zone_id` | required | Hosted zone of `cluster_env_domain` |
| `certbot_zone_ids` | `null` | Override: every zone certbot may change |

**Outputs:** `certbot_role_arn`, `certbot_instance_profile_name`

## compute

Creates the nginx instance and the RKE2 nodes (keyed by name, so adding a node never recreates
others).

| Variable | Default | Description |
|---|---|---|
| `cluster_name`, `aws_provider_region`, `vpc_name`, `ami`, `ssh_key_name` | required | Shared values |
| `specific_availability_zones` | `[]` | Pin AZs; empty uses all (avoids capacity errors) |
| `nginx_instance_type`, `k8s_instance_type` | required | Instance types |
| `nginx_node_root_volume_size`, `k8s_instance_root_volume_size` | required | Root disk sizes (GB) |
| `k8s_control_plane_node_count`, `k8s_etcd_node_count`, `k8s_worker_node_count` | required | Node counts |
| `attach_certbot_profile` | `true` | Give nginx the certbot instance profile from `iam` |

**Outputs:** `nginx_public_ip`, `nginx_private_ip`, `nginx_instance_id`, `k8s_node_ips`,
`k8s_node_ips_by_role`, `k8s_primary_control_plane_ip`. The inventory generator reads these.

## storage

Creates the data disks on the nginx host and attaches them after the instance exists.

| Variable | Default | Description |
|---|---|---|
| `cluster_name`, `aws_provider_region` | required | Shared values |
| `nginx_node_ebs_volume_size` | required | NFS disk (GB) |
| `nginx_node_ebs_volume_size_2` | `0` | PostgreSQL disk; `0` = none (PostgreSQL step skipped) |
| `nginx_node_ebs_volume_size_3` | `0` | ActiveMQ disk; `0` = none |
| `enable_activemq_setup` | `false` | Must also be `true` for the ActiveMQ disk |

**Outputs:** `nfs_volume_id`, `postgresql_volume_id`, `activemq_volume_id`

## dns

Creates the Route53 records. See [DNS providers](../guides/dns-providers.md).

| Variable | Default | Description |
|---|---|---|
| `cluster_name`, `aws_provider_region`, `cluster_env_domain` | required | Shared values |
| `zone_id` | `null` | Single zone for every record (ignored when `zones` is set) |
| `zones` | `{}` | Named zones by `zone_id` or `name` (+ `private`) |
| `public_zone` / `internal_zone` | `"default"` | Zone for public / internal records |
| `ttl` | `300` | TTL of the managed records |
| `allow_overwrite` | `true` | Take over existing records with the same name |
| `extra_records` | `{}` | Any other record (TXT, MX, CAA, A …) in any zone |
| `subdomain_public` / `subdomain_internal` | `null` | Override the lists in `profile.yml` |
| `nginx_public_ip` / `nginx_private_ip` | `null` | Fixed targets instead of the tagged nginx instance |
| `profile_manifest` | `null` | Path to `profile.yml` (set by CI) |

**Outputs:** `dns_target`, `record_names`, `zone_ids`

## vm

Standalone EC2 workloads. See [Standalone VM](../guides/standalone-vm.md).

| Variable | Default | Description |
|---|---|---|
| `cluster_name`, `aws_provider_region`, `vpc_name`, `ami`, `ssh_key_name` | required | Shared values |
| `instance_groups` | `{}` | One entry per workload |
| `allow_ssh_from_anywhere` | `false` | Permit SSH from `0.0.0.0/0` |

**Outputs:** `instances`, `security_group_ids`, `iam_role_arns`

## base-infra

One-time network: VPC, public/private subnets, NAT, WireGuard jump server. Values in
`terraform/implementations/aws/base-infra/aws.tfvars`; run with `COMPONENT=base-infra`.
