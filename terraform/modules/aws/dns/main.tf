terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

locals {
  # api.<domain> / api-internal.<domain> — the two A records everything else CNAMEs to
  api_records = {
    API_DNS = {
      name            = "api.${var.cluster_env_domain}"
      type            = "A"
      records         = var.nginx_public_ip
      allow_overwrite = true
    }
    API_INTERNAL_DNS = {
      name            = "api-internal.${var.cluster_env_domain}"
      type            = "A"
      records         = var.nginx_private_ip
      allow_overwrite = true
    }
  }

  # Bare domain — CNAME to api-internal (landing page stays internal/admin-only)
  homepage_dns_record = {
    "${var.cluster_env_domain}" = {
      name            = var.cluster_env_domain
      type            = "CNAME"
      records         = "api-internal.${var.cluster_env_domain}"
      allow_overwrite = true
    }
  }

  public_dns_records = {
    for sub in var.subdomain_public :
    sub => {
      name            = "${sub}.${var.cluster_env_domain}"
      type            = "CNAME"
      records         = "api.${var.cluster_env_domain}"
      allow_overwrite = true
    }
  }

  internal_dns_records = {
    for sub in var.subdomain_internal :
    sub => {
      name            = "${sub}.${var.cluster_env_domain}"
      type            = "CNAME"
      records         = "api-internal.${var.cluster_env_domain}"
      allow_overwrite = true
    }
  }

  all_records = merge(
    local.api_records,
    local.homepage_dns_record,
    local.public_dns_records,
    local.internal_dns_records
  )
}

# No depends_on any status-check resource — the data source lookup for
# nginx's IPs (done by the calling root) already requires the instance to
# exist and be tagged; that's sufficient, per the decision to drop the
# null_resource status-check dependency this had in the pre-#273 monolith.
resource "aws_route53_record" "records" {
  for_each        = local.all_records
  name            = each.value.name
  type            = each.value.type
  zone_id         = var.zone_id
  ttl             = 300
  records         = [each.value.records]
  allow_overwrite = each.value.allow_overwrite
}
