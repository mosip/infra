variable "cluster_name" { type = string }

variable "nginx_instance_id" {
  description = "Instance to attach the certbot IAM profile to — looked up by tag from #275's compute component"
  type        = string
}

variable "route53_zone_ids" {
  description = "Hosted zones certbot may change records in (the zone(s) holding <cluster_env_domain>)"
  type        = list(string)

  validation {
    condition     = length(var.route53_zone_ids) > 0 && alltrue([for id in var.route53_zone_ids : can(regex("^[A-Z0-9]+$", id))])
    error_message = "route53_zone_ids must be a non-empty list of hosted zone IDs (e.g. Z0123456789ABCDEFGHI, without /hostedzone/)."
  }
}
