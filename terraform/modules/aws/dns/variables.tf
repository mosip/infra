variable "cluster_env_domain" { type = string }

variable "nginx_public_ip" {
  description = "Target of api.<domain>"
  type        = string
}

variable "nginx_private_ip" {
  description = "Target of api-internal.<domain>"
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

# ---- zones ----------------------------------------------------------------

variable "zone_id" {
  description = "Single hosted zone for every record (legacy). Ignored when `zones` is set."
  type        = string
  default     = null
}

variable "zones" {
  description = <<-EOT
    Named hosted zones, any number, same AWS account. Each entry gives
    zone_id, or name (+ private = true for a private zone) to look it up.
    e.g. { public = { name = "mosip.example.org" },
           internal = { name = "mosip.example.org", private = true } }
  EOT
  type = map(object({
    zone_id = optional(string)
    name    = optional(string)
    private = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for z in values(var.zones) : (z.zone_id == null) != (z.name == null)])
    error_message = "Each zone needs exactly one of zone_id or name."
  }
}

variable "public_zone" {
  description = "Key in `zones` for api.<domain> and the public subdomains"
  type        = string
  default     = "default"
}

variable "internal_zone" {
  description = "Key in `zones` for api-internal.<domain>, the bare domain and internal subdomains"
  type        = string
  default     = "default"
}

# ---- record settings ------------------------------------------------------

variable "ttl" {
  description = "TTL for the managed (api/subdomain) records"
  type        = number
  default     = 300
}

variable "allow_overwrite" {
  description = "Take over existing records with the same name for the managed records (legacy behaviour; needed when adopting records a previous deployment created)"
  type        = bool
  default     = true
}

variable "extra_records" {
  description = <<-EOT
    Additional records in any zone, keyed by an arbitrary name:
    { verify = { name = "_verify.mosip.example.org", type = "TXT", records = ["abc"] } }
  EOT
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

check "zone_configured" {
  assert {
    condition     = var.zone_id != null || length(var.zones) > 0
    error_message = "Set zone_id or zones."
  }
}
