# ============================================================
# Shared identity values — observ-infra
# ============================================================
# Loaded via -var-file by every decoupled component under
# implementations/aws/observ-infra/ (security, compute, storage, dns, iam)
# in addition to that component's own aws.tfvars. No profiles/ subdirectory
# here — unlike infra (mosip/esignet-standalone), observ-infra is one fixed
# cluster shape, so this file sits flat, mirroring the legacy aws.tfvars'
# own identity values one level up.
# ============================================================

cluster_name        = "<cluster-name>"
cluster_env_domain  = "<cluster-env-domain>"
mosip_email_id      = "<email-id>"
ssh_key_name        = "<ssh-key-name>"
aws_provider_region = "ap-south-1"
zone_id             = "<zone-id>"

## UBUNTU 24.04
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
k8s_infra_branch   = "release-1.2.1.x"

# rancher-keycloak-setup config (observ-infra only — infra never reads
# these). Matches the same values the legacy observ-infra/aws.tfvars used.
rancher_hostname                    = "rancher.<cluster-env-domain>"
keycloak_hostname                   = "iam.<cluster-env-domain>"
rancher_bootstrap_password          = "admin"
rancher_ui_version                  = "2.8.3"
enable_rancher_keycloak_integration = true
