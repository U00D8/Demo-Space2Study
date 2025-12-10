# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Jenkins Controller Instance
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.jenkins_instance_type
  key_name               = var.key_name
  subnet_id              = var.jenkins_subnet_id
  vpc_security_group_ids = [var.jenkins_security_group_id]
  iam_instance_profile   = var.jenkins_instance_profile

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-jenkins-root"
      }
    )
  }

  user_data = templatefile("${path.module}/user_data/jenkins.sh", {
    backup_bucket           = var.backup_bucket_name
    region                  = var.aws_region
    jenkins_agent_subnet_id  = var.jenkins_agent_subnet_id
    project_name             = var.project_name
    account_id               = data.aws_caller_identity.current.account_id
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-jenkins-controller"
      Role = "Jenkins"
    }
  )

  lifecycle {
    ignore_changes = [ami]
  }
}

# Data source to find the latest snapshot of Jenkins home volume
data "aws_ebs_snapshot" "jenkins_home_latest" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-jenkins-home"]
  }

  filter {
    name   = "status"
    values = ["completed"]
  }
}

# Create EBS volume from latest snapshot (if exists) or create new empty volume
resource "aws_ebs_volume" "jenkins_home" {
  availability_zone = aws_instance.jenkins.availability_zone
  size              = 5
  type              = "gp3"
  encrypted         = true
  
  # Restore from latest snapshot if available
  snapshot_id = try(data.aws_ebs_snapshot.jenkins_home_latest.id, null)
  
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-jenkins-home"
      SnapshotSchedule = "hourly"
    }
  )

  lifecycle {
    prevent_destroy = false  # Allow destroy since we have snapshots
    ignore_changes  = [snapshot_id]  # Don't recreate if snapshot changes
  }
}

resource "aws_volume_attachment" "jenkins_home_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.jenkins_home.id
  instance_id = aws_instance.jenkins.id
}


# Vault Instance
resource "aws_instance" "vault" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.vault_instance_type
  key_name               = var.key_name
  subnet_id              = var.vault_subnet_id
  vpc_security_group_ids = [var.vault_security_group_id]
  iam_instance_profile   = var.vault_instance_profile

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-vault-root"
      }
    )
  }

  user_data = templatefile("${path.module}/user_data/vault.sh", {
    backup_bucket     = var.backup_bucket_name
    region            = var.aws_region
    kms_key_id        = var.kms_key_id
    project_name      = var.project_name
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vault"
      Role = "Vault"
    }
  )

  lifecycle {
    ignore_changes = [ami]
  }
}

# Data source to find the latest snapshot of Vault data volume
data "aws_ebs_snapshot" "vault_data_latest" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vault-data"]
  }

  filter {
    name   = "status"
    values = ["completed"]
  }
}

# Vault Data EBS Volume
resource "aws_ebs_volume" "vault_data" {
  availability_zone = aws_instance.vault.availability_zone
  size              = 5
  type              = "gp3"
  encrypted         = true

  # Restore from latest snapshot if available
  snapshot_id = try(data.aws_ebs_snapshot.vault_data_latest.id, null)

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vault-data"
      SnapshotSchedule = "hourly"
    }
  )

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [snapshot_id, kms_key_id]  # Don't recreate if snapshot or key changes
  }
}

# Attach Vault Data Volume
resource "aws_volume_attachment" "vault_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.vault_data.id
  instance_id = aws_instance.vault.id
}
