variable "cluster_name" {
  description = "Cluster identifier — used for tagging every security group"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the security groups belong to (looked up by the calling root via vpc_name, not created here)"
  type        = string
}

variable "network_cidr" {
  description = "VPC CIDR block for internal communication and DNS rules"
  type        = string
}

variable "wireguard_cidr" {
  description = "CIDR block for WireGuard VPN server(s) — currently unused here (no WireGuard-specific ingress on these groups), kept for parity with the shared identity contract"
  type        = string
  default     = ""
}

variable "extra_ingress_rules" {
  description = <<-EOT
    Extra ingress rules per security group, added after the built-in ones.
    Keys: nginx, control_plane, etcd, worker. Empty (default) = no change.
  EOT
  type = map(list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
  })))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.extra_ingress_rules) : contains(["nginx", "control_plane", "etcd", "worker"], k)])
    error_message = "extra_ingress_rules keys must be nginx, control_plane, etcd or worker."
  }
  validation {
    condition = alltrue(flatten([
      for rules in values(var.extra_ingress_rules) : [
        for r in rules : length(r.cidr_blocks) + length(r.ipv6_cidr_blocks) > 0 && r.from_port <= r.to_port
      ]
    ]))
    error_message = "Each extra ingress rule needs cidr_blocks and/or ipv6_cidr_blocks, and from_port <= to_port."
  }
}
