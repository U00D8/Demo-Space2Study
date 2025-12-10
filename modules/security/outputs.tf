# modules/security-groups/outputs.tf

output "alb_sg_id" {
  description = "ID of ALB security group"
  value       = aws_security_group.alb.id
}

output "jenkins_sg_id" {
  description = "ID of Jenkins security group"
  value       = aws_security_group.jenkins.id
}

output "vault_sg_id" {
  description = "ID of Vault security group"
  value       = aws_security_group.vault.id
}

output "jenkins_agent_sg_id" {
  description = "ID of Jenkins agent security group"
  value       = aws_security_group.jenkins_agent.id
}

output "k3s_master_sg_id" {
  description = "ID for K3s master security group"
  value = aws_security_group.k3s_master.id
}

output "k3s_worker_sg_id" {
  description = "ID for K3s worker security group"
  value = aws_security_group.k3s_workers.id
}