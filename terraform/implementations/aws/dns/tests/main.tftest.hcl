# Root-level behaviour: where subdomains and record targets come from.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "dns"
}

variables {
  cluster_name        = "dev1"
  aws_provider_region = "ap-south-1"
  cluster_env_domain  = "dev1.example.org"
  zone_id             = "Z0123456789ABCDEFGHI"
}

run "subdomains_come_from_the_profile_manifest" {
  command = plan

  variables {
    profile_manifest = "../../../../profiles/observ/profile.yml"
    nginx_public_ip  = "203.0.113.10"
  }

  assert {
    condition     = length(local.subdomain_public) == 0 && local.subdomain_internal == tolist(["rancher", "iam"])
    error_message = "observ profile subdomains must be read from profile.yml"
  }
  assert {
    condition     = length(module.dns.zone_ids) == 1
    error_message = "single zone_id should resolve to one default zone"
  }
}

run "tfvars_override_the_manifest" {
  command = plan

  variables {
    profile_manifest   = "../../../../profiles/mosip/profile.yml"
    subdomain_public   = ["only-this"]
    subdomain_internal = []
    nginx_public_ip    = "203.0.113.10"
  }

  assert {
    condition     = length(local.subdomain_public) == 1 && local.subdomain_public[0] == "only-this"
    error_message = "subdomain_public in tfvars must win over profile.yml"
  }
  assert {
    condition     = length(local.subdomain_internal) == 0
    error_message = "an explicit empty list must be respected, not replaced by the manifest"
  }
}

run "explicit_ip_serves_both_api_records" {
  command = plan

  variables {
    nginx_public_ip = "198.51.100.7"
  }

  assert {
    condition     = local.nginx_public_ip == "198.51.100.7" && local.nginx_private_ip == "198.51.100.7"
    error_message = "with only nginx_public_ip set, api-internal must point at the same address"
  }
  assert {
    condition     = length(data.aws_instance.nginx) == 0
    error_message = "no instance lookup when the IP is given"
  }
}

run "without_ip_the_nginx_instance_is_looked_up" {
  command = plan

  override_data {
    target = data.aws_instance.nginx[0]
    values = { public_ip = "203.0.113.20", private_ip = "10.0.0.20" }
  }

  assert {
    condition     = local.nginx_public_ip == "203.0.113.20" && local.nginx_private_ip == "10.0.0.20"
    error_message = "tag lookup must supply both addresses"
  }
}

# ── hosted zone in another AWS account (dns_role_arn) ───────────────────────

run "cross_account_role_plans_the_same_records" {
  command = plan

  variables {
    profile_manifest = "../../../../profiles/observ/profile.yml"
    nginx_public_ip  = "203.0.113.10"
    dns_role_arn     = "arn:aws:iam::123456789012:role/mosip-dns-team-a"
  }

  assert {
    condition     = length(module.dns.zone_ids) == 1 && local.subdomain_internal == tolist(["rancher", "iam"])
    error_message = "With dns_role_arn the same zone and records must be planned (through the aws.dns provider)"
  }
}

run "cross_account_rejects_bad_role_arn" {
  command = plan

  variables {
    nginx_public_ip = "203.0.113.10"
    dns_role_arn    = "role/mosip-dns"
  }

  expect_failures = [var.dns_role_arn]
}
