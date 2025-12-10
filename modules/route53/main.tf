# modules/route53/main.tf

resource "aws_route53_zone" "private" {
  name    = "internal.${var.domain_name}"
  comment = "Private hosted zone for internal services (Vault, MongoDB, etc.)"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(
    var.tags,
    {
      Name        = "internal.${var.domain_name}"
      Environment = var.environment
      Type        = "Private"
    }
  )
}

# A Record - Vault (internal only, accessible only within VPC)
resource "aws_route53_record" "vault" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "vault.internal.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.vault_private_ip]
}

# A Record - Jenkins (internal, if you want private access)
resource "aws_route53_record" "jenkins" {
  # count   = var.jenkins_private_ip != "" ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "jenkins.internal.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.jenkins_private_ip]
}

# A Record - K3s Master (internal, if you want private access)
resource "aws_route53_record" "k3s_master" {
  # count   = var.k3s_master_private_ip != "" ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "k3s-master.internal.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.k3s_master_private_ip]
}

# A Record - K3s Worker (internal, resolves to all worker IPs for load balancing)
resource "aws_route53_record" "k3s_worker" {
  # count   = length(var.k3s_worker_private_ips) > 0 ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "k3s-worker.internal.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = var.k3s_worker_private_ips
}