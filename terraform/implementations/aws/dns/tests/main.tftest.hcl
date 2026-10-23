# Root-level behaviour: where subdomains and record targets come from.

mock_provider "aws" {}

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

# ── additional_subdomain_* (append without repeating the profile list) ───────

run "additional_subdomains_are_appended" {
  command = plan

  variables {
    profile_manifest              = "../../../../profiles/observ/profile.yml"
    nginx_public_ip               = "203.0.113.10"
    additional_subdomain_internal = ["grafana"]
    additional_subdomain_public   = ["portal"]
  }

  assert {
    condition = (
      local.subdomain_internal == tolist(["rancher", "iam", "grafana"]) &&
      local.subdomain_public == tolist(["portal"])
    )
    error_message = "additional subdomains must be appended to the profile lists"
  }
}

run "additional_subdomain_already_listed_is_a_no_op" {
  command = plan

  variables {
    profile_manifest              = "../../../../profiles/observ/profile.yml"
    nginx_public_ip               = "203.0.113.10"
    additional_subdomain_internal = ["iam"]
  }

  assert {
    condition     = local.subdomain_internal == tolist(["rancher", "iam"])
    error_message = "a name already in the list must not be added twice"
  }
}

run "additional_subdomains_work_with_a_full_override" {
  command = plan

  variables {
    nginx_public_ip               = "203.0.113.10"
    subdomain_internal            = ["admin"]
    additional_subdomain_internal = ["grafana"]
  }

  assert {
    condition     = local.subdomain_internal == tolist(["admin", "grafana"])
    error_message = "additional subdomains must also append to an override"
  }
}

run "additional_subdomain_invalid_label_rejected" {
  command = plan

  variables {
    nginx_public_ip               = "203.0.113.10"
    additional_subdomain_internal = ["Grafana.example"]
  }

  expect_failures = [var.additional_subdomain_internal]
}

run "same_subdomain_public_and_internal_rejected" {
  command = plan

  variables {
    profile_manifest            = "../../../../profiles/observ/profile.yml"
    nginx_public_ip             = "203.0.113.10"
    additional_subdomain_public = ["iam"]
  }

  expect_failures = [output.record_names]
}
