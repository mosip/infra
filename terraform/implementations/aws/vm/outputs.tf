output "instances" {
  value = module.vm.instances
}

output "security_group_ids" {
  value = module.vm.security_group_ids
}

output "iam_role_arns" {
  value = module.vm.iam_role_arns
}

output "instance_amis" {
  value = module.vm.instance_amis
}

output "data_volume_ids" {
  value = module.vm.data_volume_ids
}
