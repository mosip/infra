# Values below come from profiles/<profile>/aws/common.tfvars (shared across every
# decoupled component) — this component has no security-group-specific values of
# its own beyond what's already common, so its own profiles/<profile>/aws/<component>.tfvars
# is intentionally near-empty.

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

  # Private (RFC 1918) ranges only: these CIDRs open the cluster ports (RKE2
  # 9345, Kubernetes API, etcd, kubelet ...) — a public range such as
  # 172.0.0.0/8 would expose them to the internet.
  validation {
    condition = can(cidrhost(var.network_cidr, 0)) && try(
      (startswith(var.network_cidr, "10.") && tonumber(split("/", var.network_cidr)[1]) >= 8) ||
      (startswith(var.network_cidr, "192.168.") && tonumber(split("/", var.network_cidr)[1]) >= 16) ||
      (startswith(var.network_cidr, "172.") && tonumber(split("/", var.network_cidr)[1]) >= 12 &&
      tonumber(split(".", var.network_cidr)[1]) >= 16 && tonumber(split(".", var.network_cidr)[1]) <= 31)
    , false)
    error_message = "network_cidr must be a private (RFC 1918) range inside 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16, e.g. your VPC CIDR."
  }
}

variable "WIREGUARD_CIDR" {
  description = "CIDR block for WireGuard VPN server(s)"
  type        = string

  # Private (RFC 1918) ranges only: these CIDRs open the cluster ports (RKE2
  # 9345, Kubernetes API, etcd, kubelet ...) — a public range such as
  # 172.0.0.0/8 would expose them to the internet.
  validation {
    condition = can(cidrhost(var.WIREGUARD_CIDR, 0)) && try(
      (startswith(var.WIREGUARD_CIDR, "10.") && tonumber(split("/", var.WIREGUARD_CIDR)[1]) >= 8) ||
      (startswith(var.WIREGUARD_CIDR, "192.168.") && tonumber(split("/", var.WIREGUARD_CIDR)[1]) >= 16) ||
      (startswith(var.WIREGUARD_CIDR, "172.") && tonumber(split("/", var.WIREGUARD_CIDR)[1]) >= 12 &&
      tonumber(split(".", var.WIREGUARD_CIDR)[1]) >= 16 && tonumber(split(".", var.WIREGUARD_CIDR)[1]) <= 31)
    , false)
    error_message = "WIREGUARD_CIDR must be a private (RFC 1918) range inside 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16, e.g. your VPC CIDR."
  }
}

variable "ingress_rules" {
  description = "Inbound rules per security group (nginx, control_plane, etcd, worker) — see profiles/<profile>/aws/security.tfvars"
  type = map(list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
  })))
}

variable "egress_rules" {
  description = "Outbound rules for every security group — see profiles/<profile>/aws/security.tfvars"
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
  }))
}

variable "extra_ingress_rules" {
  description = "Extra ingress rules per security group (nginx, control_plane, etcd, worker) — see profiles/<profile>/aws/security.tfvars"
  type = map(list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
  })))
  default = {}
}

variable "extra_egress_rules" {
  description = "Extra egress rules per security group (nginx, control_plane, etcd, worker) — see profiles/<profile>/aws/security.tfvars"
  type = map(list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
  })))
  default = {}
}
