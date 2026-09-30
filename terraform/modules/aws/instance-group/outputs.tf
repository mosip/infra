output "instances" {
  description = "<group>-<n> => { id, group, private_ip, public_ip }"
  value = {
    for k, i in aws_instance.vm : k => {
      id         = i.id
      group      = i.tags["Role"]
      private_ip = i.private_ip
      public_ip  = i.public_ip
    }
  }
}

output "security_group_ids" {
  value = { for g, sg in aws_security_group.group : g => sg.id }
}

output "iam_role_arns" {
  value = { for g, r in aws_iam_role.group : g => r.arn }
}
