output "certbot_role_arn" {
  value = module.iam.certbot_role_arn
}

output "certbot_instance_profile_name" {
  value = module.iam.certbot_instance_profile_name
}
