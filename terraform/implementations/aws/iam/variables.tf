# cluster_name/aws_provider_region/zone_id come from profiles/<profile>/aws/common.tfvars

variable "cluster_name" { type = string }
variable "aws_provider_region" { type = string }

variable "zone_id" {
  description = "Hosted zone of cluster_env_domain — certbot's DNS-01 challenge records go here"
  type        = string
}

variable "certbot_zone_ids" {
  description = "Override: every zone certbot may change (e.g. when the domain's public zone differs from zone_id). Set in iam.tfvars."
  type        = list(string)
  default     = null
}
