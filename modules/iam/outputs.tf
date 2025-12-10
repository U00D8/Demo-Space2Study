# modules/iam/outputs.tf

output "k3s_master_instance_profile_name" {
  description = "K3s master instance profile name"
  value = aws_iam_instance_profile.k3s_master.name
}

output "k3s_worker_instance_profile_name" {
  description = "K3s worker instance profile name"
  value = aws_iam_instance_profile.k3s_worker.name
}

output "jenkins_controller_instance_profile_name" {
  description = "Jenkins controller instance profile name"
  value       = aws_iam_instance_profile.jenkins_controller.name
}

output "jenkins_agent_instance_profile_name" {
  description = "Jenkins agent instance profile name"
  value       = aws_iam_instance_profile.jenkins_agent.name
}

output "application_instance_profile_name" {
  description = "Application instance profile name"
  value       = aws_iam_instance_profile.application.name
}

output "vault_instance_profile_name" {
  description = "Vault instance profile name"
  value       = aws_iam_instance_profile.vault.name
}

output "jenkins_controller_role_arn" {
  description = "Jenkins controller IAM role ARN"
  value       = aws_iam_role.jenkins_controller.arn
}

output "jenkins_agent_role_arn" {
  description = "Jenkins agent IAM role ARN"
  value       = aws_iam_role.jenkins_agent.arn
}

output "snapshot_policy_id" {
  description = "DLM snapshot policy ID"
  value       = aws_dlm_lifecycle_policy.snapshots.id
}