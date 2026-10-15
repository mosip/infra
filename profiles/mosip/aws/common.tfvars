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
cluster_name = "d273-mosip"

# MOSIP's domain (ex: sandbox.xyz.net)
cluster_env_domain = "d273-mosip.mosip.net"

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
vpc_name = "decouple-273-vpc"

# Security group CIDRs
network_cidr   = "10.73.0.0/16" # Use your actual VPC CIDR
WIREGUARD_CIDR = "10.73.0.0/16" # Use your actual WireGuard VPN CIDR

# Hosted zone in ANOTHER AWS account (optional). Use when this account has no
# Route53 zone for the domain and another account owns it (e.g. mosip.net).
# That account creates one role limited to the zone that trusts this account
# (see .github/workflows/README.md, "Domain in another AWS account"); zone_id
# above is the zone's ID in that account. DNS records (COMPONENT=dns) and the
# Let's Encrypt DNS-01 challenge then go through the role. Unset = zone here.
# dns_role_arn = "arn:aws:iam::<DNS-ACCOUNT-ID>:role/mosip-dns-<team>"
