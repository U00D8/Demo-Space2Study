output "ami_id" {
  description = "Amazon Linux 2023 AMI ID used"
  value       = data.aws_ami.amazon_linux_2023.id
}

output "jenkins_instance_id" {
  description = "Jenkins instance ID"
  value       = aws_instance.jenkins.id
}

output "jenkins_private_ip" {
  description = "Jenkins private IP"
  value       = aws_instance.jenkins.private_ip
}

output "jenkins_volume_id" {
  description = "Jenkins home EBS volume ID"
  value       = aws_ebs_volume.jenkins_home.id
}

output "jenkins_latest_snapshot_id" {
  description = "Latest Jenkins home snapshot ID (if exists)"
  value       = try(data.aws_ebs_snapshot.jenkins_home_latest.id, "No snapshot found")
}

output "vault_instance_id" {
  description = "Vault instance ID"
  value       = aws_instance.vault.id
}

output "vault_private_ip" {
  description = "Vault private IP"
  value       = aws_instance.vault.private_ip
}

output "vault_volume_id" {
  description = "Vault home EBS volume ID"
  value       = aws_ebs_volume.vault_data.id
}

output "vault_latest_snapshot_id" {
  description = "Latest Vault data snapshot ID (if exists)"
  value       = try(data.aws_ebs_snapshot.vault_data_latest.id, "No snapshot found")
}
