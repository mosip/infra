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
