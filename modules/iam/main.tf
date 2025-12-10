# modules/iam/main.tf

# IAM Role for K3s Master
resource "aws_iam_role" "k3s_master" {
  name = "${var.project_name}-k3s-master-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
  
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-master-role"
    }
  )
}

resource "aws_iam_role_policy" "k3s_master" {
  name = "${var.project_name}-k3s-master-policy"
  role = aws_iam_role.k3s_master.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.backup_bucket_arn}/k3s/*",
          "${var.backup_bucket_arn}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "${var.kms_key_arn}"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:RoleSessionName" = "k3s-vault-session"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k3s_master" {
  name = "${var.project_name}-k3s-master-profile"
  role = aws_iam_role.k3s_master.name

  tags = var.tags
}

# IAM Role for K3s Workers
resource "aws_iam_role" "k3s_worker" {
  name = "${var.project_name}-k3s-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-k3s-worker-role"
    }
  )
}

resource "aws_iam_role_policy" "k3s_worker" {
  name = "${var.project_name}-k3s-worker-policy"
  role = aws_iam_role.k3s_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "${var.kms_key_arn}"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:RoleSessionName" = "k3s-vault-session"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k3s_worker" {
  name = "${var.project_name}-k3s-worker-profile"
  role = aws_iam_role.k3s_worker.name

  tags = var.tags
}

# Jenkins Controller IAM Role
resource "aws_iam_role" "jenkins_controller" {
  name = "${var.project_name}-jenkins-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-jenkins-controller-role"
    }
  )
}

# Jenkins Controller IAM Policy
resource "aws_iam_role_policy" "jenkins_controller" {
  name = "${var.project_name}-jenkins-controller-policy"
  role = aws_iam_role.jenkins_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeRegions",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:RequestSpotInstances",
          "ec2:CancelSpotInstanceRequests",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeImages",
          "ec2:GetConsoleOutput"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.terraform_state_bucket_arn}",
          "${var.terraform_state_bucket_arn}/*",
          "${var.backup_bucket_arn}",
          "${var.backup_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.jenkins_agent.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          aws_iam_role.k3s_master.arn,
          aws_iam_role.k3s_worker.arn
        ]
      }
    ]
  })
}

# Jenkins Controller Instance Profile
resource "aws_iam_instance_profile" "jenkins_controller" {
  name = "${var.project_name}-jenkins-controller-profile"
  role = aws_iam_role.jenkins_controller.name

  tags = var.tags
}

# Jenkins Agent IAM Role
resource "aws_iam_role" "jenkins_agent" {
  name = "${var.project_name}-jenkins-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.jenkins_controller.arn
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-jenkins-agent-role"
    }
  )
}

# Jenkins Agent IAM Policy
resource "aws_iam_role_policy" "jenkins_agent" {
  name = "${var.project_name}-jenkins-agent-policy"
  role = aws_iam_role.jenkins_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${var.backup_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeRegions",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.jenkins_agent.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:GetConsoleOutput"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          aws_iam_role.k3s_master.arn,
          aws_iam_role.k3s_worker.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        
        Resource = "${var.kms_key_arn}"
      }
    ]
  })
}

# Jenkins Agent Instance Profile
resource "aws_iam_instance_profile" "jenkins_agent" {
  name = "${var.project_name}-jenkins-agent-profile"
  role = aws_iam_role.jenkins_agent.name

  tags = var.tags
}

# Application IAM Role (for Frontend, Backend, MongoDB)
resource "aws_iam_role" "application" {
  name = "${var.project_name}-application-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-application-role"
    }
  )
}

# Application IAM Policy
resource "aws_iam_role_policy" "application" {
  name = "${var.project_name}-application-policy"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.backup_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# Application Instance Profile
resource "aws_iam_instance_profile" "application" {
  name = "${var.project_name}-application-profile"
  role = aws_iam_role.application.name

  tags = var.tags
}

# Vault IAM Role
resource "aws_iam_role" "vault" {
  name = "${var.project_name}-vault-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vault-role"
    }
  )
}

# Vault IAM Policy
resource "aws_iam_role_policy" "vault" {
  name = "${var.project_name}-vault-policy"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "${var.backup_bucket_arn}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${var.backup_bucket_arn}/vault/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "${var.kms_key_arn}"
      }
    ]
  })
}

# Vault Instance Profile
resource "aws_iam_instance_profile" "vault" {
  name = "${var.project_name}-vault-profile"
  role = aws_iam_role.vault.name

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "ecr" {
  for_each   = toset(var.ecr_repositories)
  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# DLM (Data Lifecycle Manager) Policy for automatic snapshots
resource "aws_dlm_lifecycle_policy" "snapshots" {
  description        = "Automatic snapshots keeps last 7 snapshots"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    policy_type     = "EBS_SNAPSHOT_MANAGEMENT"

    schedule {
      name = "Hourly snapshots"

      create_rule {
        interval      = 12  
        interval_unit = "HOURS"
      }

      retain_rule {
        count = 5
      }

      tags_to_add = {
        SnapshotType = "DLM"
        Automated    = "true"
      }

      copy_tags = true
    }

    target_tags = {
      SnapshotSchedule = "hourly"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-snapshot"
    }
  )
}

# IAM Role for DLM
resource "aws_iam_role" "dlm_lifecycle_role" {
  name = "${var.project_name}-dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for DLM
resource "aws_iam_role_policy" "dlm_lifecycle_policy" {
  name = "${var.project_name}-dlm-lifecycle-policy"
  role = aws_iam_role.dlm_lifecycle_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:EnableFastSnapshotRestores",
          "ec2:DescribeFastSnapshotRestores",
          "ec2:DisableFastSnapshotRestores",
          "ec2:CopySnapshot",
          "ec2:ModifySnapshotAttribute",
          "ec2:DescribeSnapshotAttribute"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*::snapshot/*"
      }
    ]
  })
}
