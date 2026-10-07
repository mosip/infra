output "instances" {
  value = module.vm.instances
}

output "security_group_ids" {
  value = module.vm.security_group_ids
}

output "iam_role_arns" {
  value = module.vm.iam_role_arns
}
