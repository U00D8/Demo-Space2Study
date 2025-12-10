# environments/dev/outputs.tf

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

output "jenkins_sg_id" {
  description = "Jenkins security group ID"
  value       = module.security_groups.jenkins_sg_id
}

output "vault_sg_id" {
  description = "Vault security group ID"
  value       = module.security_groups.vault_sg_id
}

output "jenkins_agent_sg_id" {
  description = "Jenkins agent security group ID"
  value       = module.security_groups.jenkins_agent_sg_id
}

# EC2 Outputs
output "ami_id" {
  description = "Amazon Linux 2023 AMI ID used"
  value       = module.ec2.ami_id
}

output "jenkins_instance_id" {
  description = "Jenkins instance ID"
  value       = module.ec2.jenkins_instance_id
}

output "jenkins_private_ip" {
  description = "Jenkins private IP address"
  value       = module.ec2.jenkins_private_ip
}

output "jenkins_volume_id" {
  description = "Jenkins home EBS volume ID"
  value       = module.ec2.jenkins_volume_id
}

output "jenkins_latest_snapshot_id" {
  description = "Latest Jenkins home snapshot ID (if exists)"
  value       = module.ec2.jenkins_latest_snapshot_id
}

output "vault_instance_id" {
  description = "Vault instance ID"
  value       = module.ec2.vault_instance_id
}

output "vault_private_ip" {
  description = "Vault private IP address"
  value       = module.ec2.vault_private_ip
}

output "vault_volume_id" {
  description = "Vault data EBS volume ID"
  value       = module.ec2.vault_volume_id
}

output "vault_latest_snapshot_id" {
  description = "Latest Vault data snapshot ID (if exists)"
  value       = module.ec2.vault_latest_snapshot_id
}

# IAM Outputs
output "jenkins_controller_role_arn" {
  description = "Jenkins controller IAM role ARN"
  value       = module.iam.jenkins_controller_role_arn
}

output "jenkins_agent_role_arn" {
  description = "Jenkins agent IAM role ARN"
  value       = module.iam.jenkins_agent_role_arn
}

output "jenkins_controller_instance_profile_name" {
  description = "Jenkins controller instance profile name"
  value       = module.iam.jenkins_controller_instance_profile_name
}

output "jenkins_agent_instance_profile_name" {
  description = "Jenkins agent instance profile name"
  value       = module.iam.jenkins_agent_instance_profile_name
}

output "application_instance_profile_name" {
  description = "Application instance profile name"
  value       = module.iam.application_instance_profile_name
}

output "vault_instance_profile_name" {
  description = "Vault instance profile name"
  value       = module.iam.vault_instance_profile_name
}

output "snapshot_policy_id" {
  description = "DLM snapshot policy ID"
  value       = module.iam.snapshot_policy_id
}

# Route53 Outputs
output "private_hosted_zone_id" {
  description = "Private Route53 hosted zone ID"
  value       = module.route53.private_hosted_zone_id
}

output "private_hosted_zone_name" {
  description = "Private Route53 hosted zone name"
  value       = module.route53.private_hosted_zone_name
}

output "vault_internal_fqdn" {
  description = "Vault internal FQDN"
  value       = module.route53.vault_internal_fqdn
}

# ALB Outputs
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = module.alb.alb_arn
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = module.alb.alb_zone_id
}

# K3S Cluster Outputs
output "k3s_master_ip" {
  description = "K3s master public IP"
  value       = module.k3s_cluster.master_public_ip
}

output "k3s_worker_ips" {
  description = "K3s worker public IPs"
  value       = module.k3s_cluster.worker_public_ips
}

output "k3s_master_instance_id" {
  description = "K3s master instance ID (for ALB target group)"
  value       = module.k3s_cluster.master_instance_id
}

output "k3s_worker_instance_ids" {
  description = "K3s worker instance IDs (for ALB target group)"
  value       = module.k3s_cluster.worker_instance_ids
}

