#!/bin/bash
# Vault Setup Script for Amazon Linux 2023

set -e

# Update system
dnf update -y

# Install and start SSM Agent (not pre-installed on AL2023)
dnf install -y amazon-ssm-agent
systemctl enable --now amazon-ssm-agent
systemctl status amazon-ssm-agent --no-pager

# Install Docker
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# Install useful tools
dnf install -y aws-cli jq

# Wait for EBS volume to be attached (Terraform attaches /dev/xvdf)
echo "Waiting for EBS volume /dev/xvdf to be attached..."
DEVICE="/dev/xvdf"
MAX_WAIT=60
WAITED=0
while [ ! -e "$DEVICE" ] && [ $WAITED -lt $MAX_WAIT ]; do
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ ! -e "$DEVICE" ]; then
    echo "ERROR: EBS volume $DEVICE not found after $${MAX_WAIT}s"
    exit 1
fi

# Check if volume is already formatted (has filesystem)
if ! blkid "$DEVICE" > /dev/null 2>&1; then
    echo "Formatting new volume $DEVICE with XFS..."
    mkfs -t xfs "$DEVICE"
else
    echo "Volume $DEVICE already formatted (restored from snapshot), skipping mkfs"
fi

# Create mount point
mkdir -p /vault/data
mkdir -p /vault/config
mkdir -p /vault/logs

# Mount the volume
echo "Mounting $DEVICE to /vault/data..."
mount "$DEVICE" /vault/data

# Get UUID for fstab (more reliable than device name)
UUID=$(blkid -s UUID -o value "$DEVICE")

# Add to /etc/fstab for automatic mount on reboot
if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID /vault/data xfs defaults,nofail 0 2" >> /etc/fstab
    echo "Added volume to /etc/fstab for automatic mounting"
fi

# Set ownership for vault user (UID 1000)
chown -R 100:1000 /vault/
chmod -R 0750 /vault/

# Create Vault configuration
cat > /vault/config/vault.hcl <<EOF
ui = true

storage "file" {
  path = "/vault/data"
}

seal "awskms" {
  region     = "${region}"
  kms_key_id = "${kms_key_id}"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://$(ec2-metadata --local-ipv4 | cut -d ' ' -f 2):8200"
EOF

# Configure Docker daemon
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker

# Pull Vault image
docker pull hashicorp/vault:latest

# Create Vault systemd service
cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=Vault Docker Container
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop vault
ExecStartPre=-/usr/bin/docker rm vault
ExecStart=/usr/bin/docker run --rm --name vault \
  --cap-add=IPC_LOCK \
  -v /vault/data:/vault/data \
  -v /vault/config:/vault/config \
  -v /vault/logs:/vault/logs \
  -p 8200:8200 \
  -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e AWS_REGION=${region} \
  -e AWS_DEFAULT_REGION=${region} \
  hashicorp/vault:latest vault server -config=/vault/config/vault.hcl

[Install]
WantedBy=multi-user.target
EOF

# Create node_exporter systemd service for Prometheus metrics collection
echo "=== Setting up node_exporter for Prometheus metrics ==="
cat > /etc/systemd/system/node-exporter.service <<EOF
[Unit]
Description=Node Exporter Docker Container
Documentation=https://github.com/prometheus/node_exporter
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
TimeoutStartSec=0

ExecStartPre=-/usr/bin/docker stop node-exporter
ExecStartPre=-/usr/bin/docker rm node-exporter

ExecStart=/usr/bin/docker run --rm \
  --name node-exporter \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  -e TZ=UTC \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host \
  --path.procfs=/host/proc \
  --path.sysfs=/host/sys \
  --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/) \
  --collector.netdev.device-exclude=^(veth.*)

ExecStopPost=-/usr/bin/docker stop node-exporter
ExecStopPost=-/usr/bin/docker rm node-exporter

MemoryLimit=256M
CPUQuota=100m

[Install]
WantedBy=multi-user.target
EOF

# Pull node_exporter image
docker pull quay.io/prometheus/node-exporter:latest

# Enable and start node_exporter
systemctl daemon-reload
systemctl enable node-exporter
systemctl start node-exporter

echo "node_exporter service created and started on port 9100"

# Enable and start Vault
systemctl enable vault
systemctl start vault

echo "Vault setup complete!"
