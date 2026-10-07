output "dns_target" {
  description = "The public entrypoint hostname everything else resolves through"
  value       = "api.${var.cluster_env_domain}"
}

output "record_names" {
  value = [for r in aws_route53_record.records : r.fqdn]
}

output "zone_ids" {
  description = "Resolved hosted zone ID per zone key — used to scope the certbot IAM policy"
  value       = local.zone_ids
}
