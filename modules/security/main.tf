# modules/security-groups/main.tf

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-alb-sg"
    }
  )
}

# K3s Master Security Group
resource "aws_security_group" "k3s_master" {
  name        = "${var.project_name}-k3s-master-sg"
  description = "Security group for K3s Master nodes"
  vpc_id      = var.vpc_id

  # Kubernetes API Server (from Jenkins for kubectl, from workers to join cluster, from VPC)
  ingress {
    description = "K3s API server from Jenkins and workers"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # etcd client API (for cluster communication)
  ingress {
    description = "etcd client API from workers"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    self        = true
  }

  # Kubelet API (master kubelet accessible from workers and itself)
  ingress {
    description = "Kubelet API from VPC"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    self        = true
  }

  # Flannel VXLAN (pod networking overlay between master and workers)
  ingress {
    description = "Flannel VXLAN from VPC"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
    self        = true
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description     = "SSH from Jenkins controller (for kubeconfig retrieval)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    # security_groups = [aws_security_group.jenkins.id]
    security_groups = [aws_security_group.jenkins.id, aws_security_group.jenkins_agent.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-master-sg"
    }
  )

}

# K3s Worker Security Group
resource "aws_security_group" "k3s_workers" {
  name        = "${var.project_name}-k3s-workers-sg"
  description = "Security group for K3s Worker nodes"
  vpc_id      = var.vpc_id

  # Kubelet API (from master for pod management)
  ingress {
    description = "Kubelet API from master and VPC"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # nginx-ingress NodePorts (for ALB access)
  ingress {
    description     = "nginx-ingress NodePort HTTP from ALB"
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "nginx-ingress NodePort HTTPS from ALB"
    from_port       = 30443
    to_port         = 30443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Flannel VXLAN (pod networking overlay - master and workers)
  ingress {
    description = "Flannel VXLAN from master and other workers"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
    self        = true
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-worker-sg"
    }
  )
}

# Jenkins Controller Security Group
resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins controller"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Jenkins UI from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description = "Jenkins agent communication"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH from admin (optional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-jenkins-sg"
    }
  )
}

# External security group rule for node_exporter access from K3s (avoids dependency cycle)
resource "aws_security_group_rule" "jenkins_node_exporter_from_k3s" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_master.id
  security_group_id        = aws_security_group.jenkins.id
  description              = "node_exporter metrics from K3s master"
}

resource "aws_security_group_rule" "jenkins_node_exporter_from_k3s_workers" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_workers.id
  security_group_id        = aws_security_group.jenkins.id
  description              = "node_exporter metrics from K3s workers"
}

# Vault Security Group
resource "aws_security_group" "vault" {
  name        = "${var.project_name}-vault-sg"
  description = "Security group for HashiCorp Vault"
  vpc_id      = var.vpc_id

  ingress {
    description = "Vault API from ALB, Jenkins, K3s nodes (for pods), MongoDB, Frontend, Backend"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = concat([var.vpc_cidr], var.admin_cidr_blocks)
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vault-sg"
    }
  )
}

# External security group rule for node_exporter access from K3s (avoids dependency cycle)
resource "aws_security_group_rule" "vault_node_exporter_from_k3s" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_master.id
  security_group_id        = aws_security_group.vault.id
  description              = "node_exporter metrics from K3s master"
}

resource "aws_security_group_rule" "vault_node_exporter_from_k3s_workers" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_workers.id
  security_group_id        = aws_security_group.vault.id
  description              = "node_exporter metrics from K3s workers"
}

# Jenkins Agent Security Group
resource "aws_security_group" "jenkins_agent" {
  name        = "${var.project_name}-jenkins-agent-sg"
  description = "Security group for ephemeral Jenkins agents"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from Jenkins controller"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  ingress {
    description     = "ICMP Echo Request from Jenkins controller (for health checks)"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-jenkins-agent-sg"
    }
  )
}
