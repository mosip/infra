output "certbot_role_arn" {
  value = aws_iam_role.certbot_role.arn
}

output "certbot_instance_profile_name" {
  value = aws_iam_instance_profile.certbot_profile.name
}
