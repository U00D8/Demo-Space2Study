# modules/route53/outputs.tf

output "private_hosted_zone_id" {
  description = "Private Route53 hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "private_hosted_zone_name" {
  description = "Private Route53 hosted zone name"
  value       = aws_route53_zone.private.name
}

output "vault_internal_fqdn" {
  description = "Vault internal FQDN"
  value       = aws_route53_record.vault.fqdn
}
