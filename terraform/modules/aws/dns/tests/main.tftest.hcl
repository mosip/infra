# Verifies the decoupled `dns` module produces the same Route53 records as
# the legacy monolith's combination of aws-resource-creation/variables.tf's
# MAP_DNS_TO_IP (API_DNS/API_INTERNAL_DNS) and aws-main.tf's dns_records
# local (homepage/public/internal) — now merged into one module instead of
# split across two files, but with identical record shapes.
#
# NOTE: `records` on aws_route53_record is a TypeSet in the AWS provider
# schema (DNS record values are inherently unordered), so membership is
# checked with contains(...), never positional indexing like records[0].

mock_provider "aws" {}

variables {
  cluster_env_domain = "test.example.com"
  zone_id            = "Z0123456789ABCDEFGHI"
  nginx_public_ip    = "203.0.113.10"
  nginx_private_ip   = "10.0.1.10"
  subdomain_public   = ["resident", "prereg", "esignet"]
  subdomain_internal = ["admin", "iam", "kafka"]
}

run "api_and_api_internal_A_records_match_legacy" {
  command = plan

  assert {
    condition     = aws_route53_record.records["API_DNS"].name == "api.test.example.com"
    error_message = "API_DNS record name doesn't match legacy's api.<domain> convention"
  }
  assert {
    condition     = aws_route53_record.records["API_DNS"].type == "A" && contains(aws_route53_record.records["API_DNS"].records, "203.0.113.10")
    error_message = "API_DNS must be an A record pointing at nginx's public IP (legacy: MAP_DNS_TO_IP.API_DNS)"
  }
  assert {
    condition     = aws_route53_record.records["API_INTERNAL_DNS"].name == "api-internal.test.example.com"
    error_message = "API_INTERNAL_DNS record name doesn't match legacy convention"
  }
  assert {
    condition     = aws_route53_record.records["API_INTERNAL_DNS"].type == "A" && contains(aws_route53_record.records["API_INTERNAL_DNS"].records, "10.0.1.10")
    error_message = "API_INTERNAL_DNS must be an A record pointing at nginx's private IP (legacy: MAP_DNS_TO_IP.API_INTERNAL_DNS)"
  }
}

run "homepage_cname_matches_legacy" {
  command = plan

  assert {
    condition     = aws_route53_record.records["test.example.com"].type == "CNAME"
    error_message = "bare domain must be a CNAME (legacy: homepage_dns_record)"
  }
  assert {
    condition     = contains(aws_route53_record.records["test.example.com"].records, "api-internal.test.example.com")
    error_message = "bare domain must CNAME to api-internal, not api (legacy: landing page stays internal/admin-only)"
  }
}

run "public_subdomains_cname_to_api_not_api_internal" {
  command = plan

  assert {
    condition     = aws_route53_record.records["resident"].name == "resident.test.example.com"
    error_message = "public subdomain record name doesn't match sub.<domain> convention"
  }
  assert {
    condition = alltrue([
      for sub in ["resident", "prereg", "esignet"] :
      aws_route53_record.records[sub].type == "CNAME" && contains(aws_route53_record.records[sub].records, "api.test.example.com")
    ])
    error_message = "every subdomain_public entry must CNAME to api.<domain>, not api-internal (legacy: public_dns_records)"
  }
}

run "internal_subdomains_cname_to_api_internal_not_api" {
  command = plan

  assert {
    condition = alltrue([
      for sub in ["admin", "iam", "kafka"] :
      aws_route53_record.records[sub].type == "CNAME" && contains(aws_route53_record.records[sub].records, "api-internal.test.example.com")
    ])
    error_message = "every subdomain_internal entry must CNAME to api-internal.<domain>, not api (legacy: internal_dns_records)"
  }
}

run "total_record_count_matches_inputs" {
  command = plan

  # 2 (api/api-internal A records) + 1 (homepage CNAME) + 3 (public) + 3 (internal) = 9
  assert {
    condition     = length(aws_route53_record.records) == 9
    error_message = "total DNS record count doesn't match 2 fixed A records + 1 homepage + len(subdomain_public) + len(subdomain_internal)"
  }
  assert {
    condition     = alltrue([for r in aws_route53_record.records : r.zone_id == "Z0123456789ABCDEFGHI" && r.ttl == 300 && r.allow_overwrite == true])
    error_message = "every record must share the same zone_id, ttl=300, allow_overwrite=true (legacy convention)"
  }
}

run "empty_subdomain_lists_still_create_the_3_fixed_records" {
  command = plan

  variables {
    subdomain_public   = []
    subdomain_internal = []
  }

  assert {
    condition     = length(aws_route53_record.records) == 3
    error_message = "with no subdomains configured, only the 2 A records + homepage CNAME should exist"
  }
}

# ── multi-zone ─────────────────────────────────────────────────────────────

run "split_horizon_public_and_private_zones_by_id" {
  command = plan

  variables {
    zone_id = null
    zones = {
      public   = { zone_id = "ZPUBLIC000000000000" }
      internal = { zone_id = "ZPRIVATE00000000000" }
    }
    public_zone   = "public"
    internal_zone = "internal"
  }

  assert {
    condition = alltrue([
      for k in ["API_DNS", "resident", "prereg", "esignet"] :
      aws_route53_record.records[k].zone_id == "ZPUBLIC000000000000"
    ])
    error_message = "api + public subdomains must go to the public zone"
  }
  assert {
    condition = alltrue([
      for k in ["API_INTERNAL_DNS", "test.example.com", "admin", "iam", "kafka"] :
      aws_route53_record.records[k].zone_id == "ZPRIVATE00000000000"
    ])
    error_message = "api-internal, bare domain + internal subdomains must go to the internal zone"
  }
}

run "zone_looked_up_by_name" {
  command = plan

  override_data {
    target = data.aws_route53_zone.by_name["public"]
    values = { zone_id = "ZLOOKEDUP0000000000" }
  }

  variables {
    zone_id       = null
    zones         = { public = { name = "example.com" } }
    public_zone   = "public"
    internal_zone = "public"
  }

  assert {
    condition     = aws_route53_record.records["API_DNS"].zone_id == "ZLOOKEDUP0000000000"
    error_message = "a zone given by name must resolve through the aws_route53_zone lookup"
  }
  assert {
    condition     = output.zone_ids["public"] == "ZLOOKEDUP0000000000"
    error_message = "zone_ids output must expose the resolved ID (used to scope certbot IAM)"
  }
}

run "extra_records_any_type_any_zone" {
  command = plan

  variables {
    zone_id = null
    zones = {
      default = { zone_id = "Z0123456789ABCDEFGHI" }
      partner = { zone_id = "ZPARTNER00000000000" }
    }
    extra_records = {
      verify = { name = "_verify.partner.org", type = "TXT", records = ["token-123"], zone = "partner", ttl = 60 }
      mail   = { name = "test.example.com", type = "MX", records = ["10 mx.example.com"] }
    }
  }

  assert {
    condition     = aws_route53_record.records["extra/verify"].type == "TXT" && aws_route53_record.records["extra/verify"].zone_id == "ZPARTNER00000000000"
    error_message = "extra TXT record must land in the zone it names"
  }
  assert {
    condition     = aws_route53_record.records["extra/verify"].ttl == 60 && aws_route53_record.records["extra/verify"].allow_overwrite == false
    error_message = "extra records take their own ttl and default to allow_overwrite = false"
  }
  assert {
    condition     = aws_route53_record.records["extra/mail"].zone_id == "Z0123456789ABCDEFGHI"
    error_message = "extra records default to the 'default' zone"
  }
  assert {
    condition     = length(aws_route53_record.records) == 11
    error_message = "9 managed records + 2 extra records expected"
  }
}

run "record_in_unknown_zone_is_rejected" {
  command = plan

  variables {
    extra_records = {
      bad = { name = "x.example.com", type = "A", records = ["192.0.2.1"], zone = "nope" }
    }
  }

  expect_failures = [aws_route53_record.records]
}

run "zone_needs_exactly_one_of_id_or_name" {
  command = plan

  variables {
    zones = { both = { zone_id = "Z1", name = "example.com" } }
  }

  expect_failures = [var.zones]
}
