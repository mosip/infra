# ============================================================
# Shared identity values — eSignet standalone profile
# ============================================================
# Loaded via -var-file by every decoupled component under
# implementations/aws/infra/ (security, compute, storage, dns, iam)
# in addition to that component's own profiles/esignet-standalone/aws.tfvars.
# Single source of truth for values needed by more than one
# component — change once here instead of in every component's
# own tfvars file.
# ============================================================

# Environment name — used for tagging every resource across every component
cluster_name = "<cluster-name>"

# eSignet's domain (ex: esignet.xyz.net)
cluster_env_domain = "<cluster-env-domain>"

# Email-ID used by certbot to notify SSL certificate expiry via email
mosip_email_id = "<email-id>"

# SSH login key name for AWS node instances (ex: my-ssh-key)
ssh_key_name = "<ssh-key-name>"

# The AWS region for resource creation
aws_provider_region = "ap-south-1"

# The Route 53 hosted zone ID
zone_id = "<route53_zone_id>"

## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
ami = "ami-0ad21ae1d0696ad58"

# VPC Configuration - Existing VPC to use (discovered by Name tag)
vpc_name = "<vpc-name>"

# Security group CIDRs
network_cidr   = "172.0.0.0/8" # Use your actual VPC CIDR
WIREGUARD_CIDR = "172.0.0.0/8" # Use your actual WireGuard VPN CIDR

# ------------------------------------------------------------
# Ansible-only values below — no Terraform component declares
# these as variables (they're read directly by the `configure`
# workflow job, not passed via -var-file to any of the 5
# provisioning components). Terraform will emit a harmless
# "Values for undeclared variables" warning when this file is
# used as a -var-file; that's expected and not a real problem.
# ------------------------------------------------------------
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
k8s_infra_branch   = "main"
