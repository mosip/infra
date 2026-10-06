terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# ── zones ─────────────────────────────────────────────────────────────────
# Any number of hosted zones, in the same AWS account, each given by ID or
# looked up by name (+ private flag, so a public and a private zone can share
# a name — split-horizon). Without `zones`, the single legacy `zone_id` is
# the "default" zone and every record lands there, exactly as before.
locals {
  zones = length(var.zones) > 0 ? var.zones : {
    default = { zone_id = var.zone_id, name = null, private = false }
  }
}

data "aws_route53_zone" "by_name" {
  for_each     = { for k, z in local.zones : k => z if z.zone_id == null }
  name         = each.value.name
  private_zone = each.value.private
}

locals {
  zone_ids = {
    for k, z in local.zones :
    k => z.zone_id != null ? z.zone_id : data.aws_route53_zone.by_name[k].zone_id
  }
}

# ── records ───────────────────────────────────────────────────────────────
# Keys are unchanged from the single-zone module (API_DNS, API_INTERNAL_DNS,
# <domain>, <subdomain>), so existing state keeps its addresses.
locals {
  api_records = {
    API_DNS = {
      name    = "api.${var.cluster_env_domain}"
      type    = "A"
      records = [var.nginx_public_ip]
      zone    = var.public_zone
    }
    API_INTERNAL_DNS = {
      name    = "api-internal.${var.cluster_env_domain}"
      type    = "A"
      records = [var.nginx_private_ip]
      zone    = var.internal_zone
    }
  }

  # Bare domain — CNAME to api-internal (landing page stays internal/admin-only)
  homepage_dns_record = {
    "${var.cluster_env_domain}" = {
      name    = var.cluster_env_domain
      type    = "CNAME"
      records = ["api-internal.${var.cluster_env_domain}"]
      zone    = var.internal_zone
    }
  }

  public_dns_records = {
    for sub in var.subdomain_public :
    sub => {
      name    = "${sub}.${var.cluster_env_domain}"
      type    = "CNAME"
      records = ["api.${var.cluster_env_domain}"]
      zone    = var.public_zone
    }
  }

  internal_dns_records = {
    for sub in var.subdomain_internal :
    sub => {
      name    = "${sub}.${var.cluster_env_domain}"
      type    = "CNAME"
      records = ["api-internal.${var.cluster_env_domain}"]
      zone    = var.internal_zone
    }
  }

  managed_records = {
    for k, r in merge(
      local.api_records,
      local.homepage_dns_record,
      local.public_dns_records,
      local.internal_dns_records,
    ) :
    k => merge(r, { ttl = var.ttl, allow_overwrite = var.allow_overwrite })
  }

  # Anything else: TXT/MX/CAA/SRV, A records to other hosts, records in
  # other zones. Prefixed so a key can never collide with a subdomain.
  extra_records = {
    for k, r in var.extra_records :
    "extra/${k}" => {
      name            = r.name
      type            = r.type
      records         = r.records
      zone            = r.zone
      ttl             = r.ttl
      allow_overwrite = r.allow_overwrite
    }
  }

  all_records = merge(local.managed_records, local.extra_records)
}

resource "aws_route53_record" "records" {
  for_each        = local.all_records
  name            = each.value.name
  type            = each.value.type
  zone_id         = local.zone_ids[each.value.zone]
  ttl             = each.value.ttl
  records         = each.value.records
  allow_overwrite = each.value.allow_overwrite

  lifecycle {
    precondition {
      condition     = contains(keys(local.zone_ids), each.value.zone)
      error_message = "Record ${each.value.name} targets zone '${each.value.zone}', which isn't in var.zones (${join(", ", keys(local.zone_ids))})."
    }
  }
}
