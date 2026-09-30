output "nfs_volume_id" {
  value = aws_ebs_volume.nfs.id
}

output "postgresql_volume_id" {
  value = length(aws_ebs_volume.postgresql) > 0 ? aws_ebs_volume.postgresql[0].id : null
}

output "activemq_volume_id" {
  value = length(aws_ebs_volume.activemq) > 0 ? aws_ebs_volume.activemq[0].id : null
}
