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

output "instance_amis" {
  description = "<group>-<n> => AMI ID the instance was created from"
  value       = { for k, i in aws_instance.vm : k => i.ami }
}

output "data_volume_ids" {
  description = "<group>-<n>/<index> => EBS volume ID (on the VM: /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<id without dash>)"
  value       = { for k, v in aws_ebs_volume.data : k => v.id }
}
