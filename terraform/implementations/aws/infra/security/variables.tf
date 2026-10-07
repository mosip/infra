# Values below come from ../profiles/<profile>/common.tfvars (shared across every
# decoupled component) — this component has no security-group-specific values of
# its own beyond what's already common, so its own profiles/<profile>/aws.tfvars
# is intentionally near-empty. See CLAUDE.md's tfvars-maintenance section.

variable "cluster_name" {
  description = "Cluster identifier — used for tagging every security group"
  type        = string
}

variable "aws_provider_region" {
  description = "AWS region for the provider"
  type        = string
}

variable "vpc_name" {
  description = "Existing VPC name tag to discover (created once by base-infra)"
  type        = string
}

variable "network_cidr" {
  description = "VPC CIDR block for internal communication and DNS rules"
  type        = string
}

variable "WIREGUARD_CIDR" {
  description = "CIDR block for WireGuard VPN server(s)"
  type        = string
}
