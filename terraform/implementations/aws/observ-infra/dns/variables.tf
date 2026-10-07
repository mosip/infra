# cluster_name/aws_provider_region/zone_id/cluster_env_domain come from
# ../common.tfvars

variable "cluster_name" { type = string }
variable "aws_provider_region" { type = string }
variable "zone_id" { type = string }
variable "cluster_env_domain" { type = string }

variable "subdomain_public" {
  type    = list(string)
  default = []
}

variable "subdomain_internal" {
  type    = list(string)
  default = []
}
