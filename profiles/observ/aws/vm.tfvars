# Standalone EC2 workloads — COMPONENT=vm. Each group gets its own security
# group, IAM role/profile (when it has policies) and instances, in the
# base-infra VPC; tagged Cluster=<cluster_name>, Role=<group>. Not part of
# COMPONENT=all. vpc_name / ami / ssh_key_name come from ./common.tfvars.

instance_groups = {}

# instance_groups = {
#   bastion = {
#     instance_type = "t3a.small"
#     subnet        = "public"                 # public | private (default)
#     ingress       = [{ port = 22, cidrs = ["203.0.113.0/24"], description = "office SSH" }]
#     iam_managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
#   }
#   reports-db = {
#     count          = 1
#     instance_type  = "t3a.large"
#     root_volume_gb = 50
#     ingress        = [{ port = 5432, source_groups = ["bastion"] }]  # from another group
#     iam_policy_json = <<-JSON
#       { "Version": "2012-10-17",
#         "Statement": [{ "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"],
#                         "Resource": "arn:aws:s3:::reports-backup/*" }] }
#     JSON
#   }
# }
#
# Guardrails: IMDSv2 required, encrypted root volumes, SSH from 0.0.0.0/0
# rejected unless allow_ssh_from_anywhere = true, group names can't reuse the
# cluster roles (nginx, control-plane, etcd, worker).
#
# Outbound (optional): every group allows all outbound by default
# (egress_all = true). To restrict it, set egress_all = false and list the
# allowed destinations, then run COMPONENT=vm:
#   reports-db = {
#     instance_type = "t3a.large"
#     egress_all    = false
#     egress        = [{ port = 443, cidrs = ["0.0.0.0/0"], description = "HTTPS" },
#                      { port = 5432, cidrs = ["10.73.3.0/24"] }]
#   }
# Inbound works the same way with ingress = [...] (see the examples above).
#
# ═══ Optional — AMI, data disks, VPC (commented out = today's behaviour) ═══
# AMI lookup per group (instead of a fixed AMI ID): the newest image of that
# owner whose name matches, for the instance type's CPU architecture (x86 or
# ARM). The owner is required — never pick an image by name alone.
#   tools = {
#     instance_type = "t3a.large"
#     ami_owner     = "099720109477"                                       # Canonical
#     ami_name      = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-*-server-*"
#   }
#   Other owners: "amazon" + "al2023-ami-2023.*-kernel-*" (Amazon Linux 2023),
#   "309956199498" + "RHEL-9.*_HVM-*" (Red Hat). Default (no ami_name): the
#   group's ami, else ami from common.tfvars. Existing instances are never
#   replaced when a newer image appears — only new ones get it.
#
# Data disks per group: encrypted EBS volumes attached at /dev/sdf, /dev/sdg,
# ... (not formatted — on the VM: /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<vol>):
#   reports-db = { instance_type = "t3a.large", data_volumes = [{ size_gb = 100 }, { size_gb = 50, type = "io2", iops = 3000 }] }
#   Grow: raise size_gb (or root_volume_gb) and run COMPONENT=vm — resized in
#   place, then grow the filesystem on the VM (growpart + resize2fs /
#   xfs_growfs). Grow only; one change per volume every 6 h. Removing an entry
#   DELETES that volume.
#
# VPC (default: vpc_name from common.tfvars = the base-infra VPC). At most one:
# vm_use_default_vpc = true              # region's default VPC (public = default-for-az subnets;
#                                        #   private only if tagged Type = Private)
# vm_vpc_id          = "vpc-0123456789abcdef0"
# vm_vpc_name        = "shared-tools-vpc"
# Subnets are found by tag Type = Public / Private; for VPCs without those
# tags give them explicitly:
# vm_public_subnet_ids  = ["subnet-0aaaaaaaaaaaaaaaa"]
# vm_private_subnet_ids = ["subnet-0bbbbbbbbbbbbbbbb"]
#
# Power state per group (optional) — add state = "running" | "stopped" to a
# group, then run COMPONENT=vm:
#   bastion = { instance_type = "t3a.small", state = "stopped" }
# Default (no state): started at creation, then left alone — stop/start with
#   the "instances start / stop" workflow. With state set, every vm run
#   enforces it. Back to default: set "running" and apply, then remove state.
