# ============================================================
# Shared values — observability profile, AWS
# ============================================================
# Loaded with -var-file by every AWS component root
# (terraform/implementations/aws/<component>), before that
# component's own ./<component>.tfvars. Roots ignore values they
# don't declare (Terraform prints an "undeclared variable" warning,
# which is expected here).
#
# The Rancher bootstrap password is no longer kept here: CI reads it
# from the RANCHER_BOOTSTRAP_PASSWORD secret at configure time.
# ============================================================

# Environment name — tags every resource and names the Ansible hosts
cluster_name = "<cluster-name>"

# Observability cluster domain; Rancher is rancher.<domain>, Keycloak iam.<domain>
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
