variable "cluster_env_domain" { type = string }
variable "zone_id" { type = string }

variable "nginx_public_ip" {
  description = "Looked up by tag from #275's compute component"
  type        = string
}

variable "nginx_private_ip" {
  description = "Looked up by tag from #275's compute component"
  type        = string
}

variable "subdomain_public" {
  description = "Public subdomains — CNAME to api.<domain>"
  type        = list(string)
  default     = []
}

variable "subdomain_internal" {
  description = "Internal subdomains — CNAME to api-internal.<domain>"
  type        = list(string)
  default     = []
}
