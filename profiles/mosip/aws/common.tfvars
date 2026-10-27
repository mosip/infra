# ============================================================
# Shared values — MOSIP profile, AWS
# ============================================================
# Loaded with -var-file by every AWS component root
# (terraform/implementations/aws/<component>), before that
# component's own ./<component>.tfvars. Roots ignore values they
# don't declare (Terraform prints an "undeclared variable" warning,
# which is expected here).
# ============================================================

# Environment name — tags every resource and names the Ansible hosts
cluster_name = "d273j21-mosip"

# MOSIP's domain (ex: sandbox.xyz.net)
cluster_env_domain = "d273j21-mosip.mosip.net"

# Email-ID used by certbot to notify SSL certificate expiry via email
mosip_email_id = "thisisbn46@gmail.com"

# SSH login key name for AWS node instances (ex: my-ssh-key)
ssh_key_name = "mosip-aws"

# The AWS region for resource creation
aws_provider_region = "ap-south-1"

# The Route 53 hosted zone ID
zone_id = "Z090954828SJIEL6P5406"

## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
ami = "ami-0ad21ae1d0696ad58"

# VPC Configuration - Existing VPC to use (discovered by Name tag)
vpc_name = "default"

# Security group CIDRs
network_cidr   = "172.31.0.0/16" # Use your actual VPC CIDR
WIREGUARD_CIDR = "172.31.0.0/16" # Use your actual WireGuard VPN CIDR
