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

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = module.vpc.nat_gateway_id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

output "jenkins_sg_id" {
  description = "Jenkins security group ID"
  value       = module.security_groups.jenkins_sg_id
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

# MongoDB Atlas Outputs
output "mongodb_project_id" {
  description = "MongoDB Atlas Project ID"
  value       = module.mongodb_atlas.project_id
}

output "mongodb_cluster_id" {
  description = "MongoDB Atlas Cluster ID"
  value       = module.mongodb_atlas.cluster_id
}

output "mongodb_cluster_name" {
  description = "MongoDB Atlas Cluster name"
  value       = module.mongodb_atlas.cluster_name
}

output "mongodb_database_name" {
  description = "MongoDB database name"
  value       = module.mongodb_atlas.database_name
}

output "mongodb_database_username" {
  description = "MongoDB database username"
  value       = module.mongodb_atlas.database_username
}

output "mongodb_connection_string" {
  description = "MongoDB connection string (standard format)"
  value       = module.mongodb_atlas.cluster_connection_string
  sensitive   = true
}

output "mongodb_connection_string_srv" {
  description = "MongoDB connection string (SRV format)"
  value       = module.mongodb_atlas.cluster_connection_string_srv
  sensitive   = true
}

output "mongodb_full_connection_string" {
  description = "Full MongoDB connection string with credentials (for Vault/environment variables)"
  value       = module.mongodb_atlas.database_connection_string_srv
  sensitive   = true
}

