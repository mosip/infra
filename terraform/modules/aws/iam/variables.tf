variable "cluster_name" { type = string }

variable "route53_zone_ids" {
  description = "Hosted zones certbot may change records in (the zone(s) holding <cluster_env_domain>)"
  type        = list(string)

  validation {
    condition     = length(var.route53_zone_ids) > 0 && alltrue([for id in var.route53_zone_ids : can(regex("^[A-Z0-9]+$", id))])
    error_message = "route53_zone_ids must be a non-empty list of hosted zone IDs (e.g. Z0123456789ABCDEFGHI, without /hostedzone/)."
  }
}

variable "route53_role_arn" {
  description = "Role in another AWS account that owns the hosted zone; certbot assumes it instead of getting Route53 rights here. null = zone in this account"
  type        = string
  default     = null
  validation {
    condition     = var.route53_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", coalesce(var.route53_role_arn, "x")))
    error_message = "route53_role_arn must be an IAM role ARN: arn:aws:iam::<12-digit account>:role/<name>."
  }
}
