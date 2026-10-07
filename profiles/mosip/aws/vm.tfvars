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
