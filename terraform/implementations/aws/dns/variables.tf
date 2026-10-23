# cluster_name/aws_provider_region/zone_id/cluster_env_domain come from
# profiles/<profile>/aws/common.tfvars; the rest from profiles/<profile>/aws/dns.tfvars.
variable "cluster_name" { type = string }
variable "aws_provider_region" { type = string }
variable "cluster_env_domain" { type = string }

variable "zone_id" {
  description = "Single hosted zone (default). Ignored when `zones` is set."
  type        = string
  default     = null
}

variable "zones" {
  description = "Named hosted zones by zone_id or name (+ private). See modules/aws/dns."
  type = map(object({
    zone_id = optional(string)
    name    = optional(string)
    private = optional(bool, false)
  }))
  default = {}
}

variable "public_zone" {
  type    = string
  default = "default"
}

variable "internal_zone" {
  type    = string
  default = "default"
}

variable "ttl" {
  type    = number
  default = 300
}

variable "allow_overwrite" {
  type    = bool
  default = true
}

variable "extra_records" {
  type = map(object({
    name            = string
    type            = string
    records         = list(string)
    zone            = optional(string, "default")
    ttl             = optional(number, 300)
    allow_overwrite = optional(bool, false)
  }))
  default = {}
}

variable "profile_manifest" {
  description = "Path to profiles/<profile>/profile.yml; CI sets it via TF_VAR_profile_manifest"
  type        = string
  default     = null
}

variable "subdomain_public" {
  description = "Overrides the profile's subdomain_public"
  type        = list(string)
  default     = null
}

variable "subdomain_internal" {
  description = "Overrides the profile's subdomain_internal"
  type        = list(string)
  default     = null
}

variable "nginx_public_ip" {
  description = "Target of api.<domain>. Null = the running nginx instance tagged Cluster=<cluster_name>, Role=nginx."
  type        = string
  default     = null
}

variable "nginx_private_ip" {
  description = "Target of api-internal.<domain>. Null = the nginx instance's private IP (or nginx_public_ip when that's set)."
  type        = string
  default     = null
}

# Add subdomains for this environment without repeating the profile's list
# (subdomain_public / subdomain_internal above REPLACE it).
variable "additional_subdomain_public" {
  description = "Extra public subdomains, appended to the profile's subdomain_public"
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.additional_subdomain_public : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", s))])
    error_message = "additional_subdomain_public: lowercase DNS labels only (a-z, 0-9, '-'), e.g. \"portal\"."
  }
}

variable "additional_subdomain_internal" {
  description = "Extra internal subdomains, appended to the profile's subdomain_internal"
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.additional_subdomain_internal : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", s))])
    error_message = "additional_subdomain_internal: lowercase DNS labels only (a-z, 0-9, '-'), e.g. \"grafana\"."
  }
}
