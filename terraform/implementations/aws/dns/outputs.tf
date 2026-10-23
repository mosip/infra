output "dns_target" {
  value = module.dns.dns_target
}

output "record_names" {
  value = module.dns.record_names

  # A name can't be both public (CNAME → api) and internal (→ api-internal).
  # Checked here — variable validations can't compare two variables in
  # Terraform 1.8 — so no extra resource is added to the plan.
  precondition {
    condition     = length(setintersection(toset(local.subdomain_public), toset(local.subdomain_internal))) == 0
    error_message = "These subdomains are both public and internal: ${join(", ", setintersection(toset(local.subdomain_public), toset(local.subdomain_internal)))}. Keep each in one list."
  }
}

output "zone_ids" {
  value = module.dns.zone_ids
}
