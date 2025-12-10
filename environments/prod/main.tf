# environments/prod/main.tf

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 1.15"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region


  default_tags {
    tags = {
      Project     = "Space2Study"
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "mongodbatlas" {
  public_key  = var.mongodb_atlas_public_key
  private_key = var.mongodb_atlas_private_key
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway

  tags = var.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "../../modules/security"

  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  admin_cidr_blocks  = var.admin_cidr_blocks

  tags = var.common_tags
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  project_name                 = var.project_name
  terraform_state_bucket_arn   = "arn:aws:s3:::${var.project_name}-terraform-state"
  backup_bucket_arn            = "arn:aws:s3:::${var.project_name}-backups"
  kms_key_arn                  = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/${var.kms_key_id}"
  
  ecr_repositories = [
    aws_ecr_repository.frontend.name,
    aws_ecr_repository.backend.name,
  ]

  tags = var.common_tags
}

# ECR Repositories
resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}

# K3s Cluster Module - Master in AZ-a private subnet, Workers in AZ-b private subnet
module "k3s_cluster" {
  source = "../../modules/k3s"

  project_name         = var.project_name
  aws_region           = var.aws_region
  key_name             = var.key_name
  backup_bucket_name   = "${var.project_name}-backups"

  # Cluster configuration
  worker_count         = var.worker_count

  # K3s Master Node (in private subnet AZ-a: 10.0.10.0/24)
  master_instance_type      = var.master_instance_type
  master_subnet_id          = module.vpc.private_subnet_ids[0]
  master_security_group_id  = module.security_groups.k3s_master_sg_id
  master_instance_profile   = module.iam.k3s_master_instance_profile_name

  # K3s Worker Nodes (in private subnet AZ-b: 10.0.11.0/24)
  worker_instance_type      = var.worker_instance_type
  worker_subnet_id          = module.vpc.private_subnet_ids[1]
  worker_security_group_id  = module.security_groups.k3s_worker_sg_id
  worker_instance_profile   = module.iam.k3s_worker_instance_profile_name

  depends_on = [module.vpc, module.security_groups, module.iam]
}

# EC2 Module - Jenkins and Vault in private subnet AZ-a
module "ec2" {
  source = "../../modules/ec2"

  project_name         = var.project_name
  aws_region           = var.aws_region
  key_name             = var.key_name
  backup_bucket_name   = "${var.project_name}-backups"
  kms_key_id           = var.kms_key_id
  vault_addr           = var.vault_addr

  # Jenkins (in private subnet AZ-a: 10.0.10.0/24)
  jenkins_instance_type        = var.jenkins_instance_type
  jenkins_subnet_id            = module.vpc.private_subnet_ids[0]
  jenkins_security_group_id    = module.security_groups.jenkins_sg_id
  jenkins_instance_profile     = module.iam.jenkins_controller_instance_profile_name
  jenkins_agent_subnet_id      = module.vpc.private_subnet_ids[0]

  # Vault (in private subnet AZ-a: 10.0.10.0/24)
  vault_instance_type          = var.vault_instance_type
  vault_subnet_id              = module.vpc.private_subnet_ids[0]
  vault_security_group_id      = module.security_groups.vault_sg_id
  vault_instance_profile       = module.iam.vault_instance_profile_name

  jenkins_role_tag    = "role:jenkins"
  vault_role_tag      = "role:vault"

  # Application instance profile
  application_instance_profile = module.iam.application_instance_profile_name

  # K3s cluster IPs and token (for Jenkins kubeconfig generation)
  k3s_master_ip         = module.k3s_cluster.master_public_ip
  k3s_master_private_ip = module.k3s_cluster.master_private_ip
  k3s_token             = module.k3s_cluster.k3s_token

  tags = var.common_tags

  depends_on = [module.vpc, module.security_groups, module.iam, module.k3s_cluster]
}

# Route53 Private Hosted Zone Module
module "route53" {
  source = "../../modules/route53"

  domain_name = var.domain_name
  environment = "prod"
  vpc_id      = module.vpc.vpc_id

  vault_private_ip = module.ec2.vault_private_ip
  jenkins_private_ip  = module.ec2.jenkins_private_ip
  k3s_master_private_ip = module.k3s_cluster.master_private_ip
  k3s_worker_private_ips = module.k3s_cluster.worker_private_ips
  
  tags = var.common_tags

  depends_on = [module.vpc, module.ec2, module.k3s_cluster]
}

# ALB Module 
module "alb" {
  source = "../../modules/alb"

  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_sg_id

  # Target instances
  jenkins_instance_id   = module.ec2.jenkins_instance_id

  # K3s worker nodes for ingress target group (convert list to map with static keys)
  k3s_worker_instance_ids = {
    for idx, instance_id in module.k3s_cluster.worker_instance_ids :
    "worker-${idx + 1}" => instance_id
  }
  k3s_ingress_port       = 30080

  # SSL Certificate (use Cloudflare Origin Certificate)
  certificate_arn       = aws_acm_certificate.cloudflare_origin.arn
  domain_name           = var.domain_name
  enable_deletion_protection = true

  tags = var.common_tags

  depends_on = [module.vpc, module.ec2, module.security_groups, module.k3s_cluster]
}

# MongoDB Atlas Cluster Module
module "mongodb_atlas" {
  source = "../../modules/mongodb"

  mongodb_atlas_organization_id = var.mongodb_atlas_organization_id
  mongodb_atlas_public_key      = var.mongodb_atlas_public_key
  mongodb_atlas_private_key     = var.mongodb_atlas_private_key

  project_name         = var.project_name
  cluster_name         = var.mongodb_cluster_name
  cluster_tier         = "M0"
  mongodb_version      = "4.4"
  cloud_provider       = "AWS"
  region               = "EU_NORTH_1"
  database_name        = "space2study"
  database_username    = var.mongodb_admin_username
  database_password    = var.mongodb_admin_password

  nat_elastic_ips = module.vpc.nat_gateway_eips

  tags = var.common_tags

  depends_on = [module.vpc]
}

# Cloudflare DNS Module
module "cloudflare" {
  source = "../../modules/cloudflare"

  domain_name      = var.domain_name
  alb_dns_name     = module.alb.alb_dns_name

  create_api_record    = var.create_api_record
  enable_rate_limiting = var.enable_rate_limiting

  depends_on = [module.alb]
}

# Import Cloudflare Origin Certificate into ACM
resource "aws_acm_certificate" "cloudflare_origin" {
  private_key       = file("${path.module}/../../secrets/cloudflare_origin_key.pem")
  certificate_body  = file("${path.module}/../../secrets/cloudflare_origin_cert.pem")

  tags = merge(
    var.common_tags,
    {
      Name   = "${var.project_name}-cloudflare-origin-cert"
      Source = "Cloudflare"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}