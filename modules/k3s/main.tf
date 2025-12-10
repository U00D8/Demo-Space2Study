# Data source for Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

# K3s Master Node
resource "aws_instance" "k3s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = var.key_name
  subnet_id              = var.master_subnet_id
  vpc_security_group_ids = [var.master_security_group_id]
  iam_instance_profile   = var.master_instance_profile

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    delete_on_termination = true
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data/master.sh", {
    cluster_token = random_password.k3s_token.result
  })

  tags = {
    Name        = "${var.project_name}-k3s-master"
    Role        = "k3s-master"
  }
}

# K3s Worker Nodes
resource "aws_instance" "k3s_workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  subnet_id              = var.worker_subnet_id
  vpc_security_group_ids = [var.worker_security_group_id]
  iam_instance_profile   = var.worker_instance_profile

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data/worker.sh", {
    master_ip     = aws_instance.k3s_master.private_ip
    cluster_token = random_password.k3s_token.result
  })

  depends_on = [aws_instance.k3s_master]

  tags = {
    Name        = "${var.project_name}-k3s-worker-${count.index + 1}"
    # Environment = var.environment
    Role        = "k3s-worker"
  }
}

# Generate random token for K3s cluster
# Use keepers to prevent regeneration on every apply
resource "random_password" "k3s_token" {
  length  = 32
  special = false

  keepers = {
    project = var.project_name
  }
}

# Data source to find latest monitoring data snapshot (optional - may not exist on first run)
data "aws_ebs_snapshot" "monitoring_data_latest" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-monitoring-data"]
  }

  filter {
    name   = "status"
    values = ["completed"]
  }
}


# Monitoring Data EBS Volume (10GB for Prometheus + Loki + Grafana)
resource "aws_ebs_volume" "monitoring_data" {
  availability_zone = aws_instance.k3s_master.availability_zone
  size              = 10
  type              = "gp3"
  encrypted         = true

  # Restore from latest snapshot if available (null on first run)
  snapshot_id = try(data.aws_ebs_snapshot.monitoring_data_latest.id, null)

  tags = {
    Name             = "${var.project_name}-monitoring-data"
    Component        = "monitoring"
    SnapshotSchedule = "hourly"
  }

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [snapshot_id]
  }
}

# Attach monitoring EBS volume to K3s master
resource "aws_volume_attachment" "monitoring_data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.monitoring_data.id
  instance_id = aws_instance.k3s_master.id
}
