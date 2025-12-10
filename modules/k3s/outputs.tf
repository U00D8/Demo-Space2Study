output "master_instance_id" {
  description = "K3s master instance ID"
  value       = aws_instance.k3s_master.id
}

output "master_public_ip" {
  description = "Public IP of K3s master"
  value       = aws_instance.k3s_master.public_ip
}

output "master_private_ip" {
  description = "Private IP of K3s master"
  value       = aws_instance.k3s_master.private_ip
}

output "worker_instance_ids" {
  description = "Instance IDs of K3s workers"
  value       = aws_instance.k3s_workers[*].id
}

output "worker_public_ips" {
  description = "Public IPs of K3s workers"
  value       = aws_instance.k3s_workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of K3s workers"
  value       = aws_instance.k3s_workers[*].private_ip
}

output "k3s_token" {
  description = "K3s cluster token"
  value       = random_password.k3s_token.result
  sensitive   = true
}
