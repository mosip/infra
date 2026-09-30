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
