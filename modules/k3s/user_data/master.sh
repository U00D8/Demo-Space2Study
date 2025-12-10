#!/bin/bash
set -e

# K3s Master Node Initialization Script
# This script sets up a K3s master node with:
# - K3s server installation
# - SSM Session Manager for secure access
# - nginx-ingress controller
# - cert-manager for TLS

echo "=== K3s Master Node Initialization Starting ==="

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
  curl \
  wget \
  git \
  vim \
  net-tools \
  htop \
  jq \
  e2fsprogs

# Install Amazon SSM Agent for secure Session Manager access
echo "=== Installing Amazon SSM Agent ==="

# For Ubuntu/Debian, SSM agent comes pre-installed on official Ubuntu AMIs
# Verify it's installed and running
if command -v snap &> /dev/null; then
  # Install via snap if not already installed
  if ! snap list amazon-ssm-agent &> /dev/null; then
    snap install amazon-ssm-agent --classic
  fi
else
  # Alternative: Install from package manager or pre-compiled binary
  # Download and install the SSM agent
  cd /tmp
  wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
  dpkg -i -E ./amazon-ssm-agent.deb
  cd -
fi

# Ensure SSM agent is running
if snap list amazon-ssm-agent &> /dev/null; then
  snap services amazon-ssm-agent
fi

# Verify SSM agent is active
echo "=== Verifying SSM Agent Status ==="
SSM_STATUS=$(snap services amazon-ssm-agent 2>/dev/null | grep amazon-ssm-agent | awk '{print $2}')
if [ "$SSM_STATUS" = "active" ]; then
  echo "✓ SSM Agent is running (via snap)"
else
  echo "⚠ Waiting for SSM Agent to start (may take a few seconds)..."
  sleep 5
  SSM_STATUS=$(snap services amazon-ssm-agent 2>/dev/null | grep amazon-ssm-agent | awk '{print $2}')
  if [ "$SSM_STATUS" = "active" ]; then
    echo "✓ SSM Agent is now running"
  else
    echo "⚠ SSM Agent installation completed, status: $SSM_STATUS"
  fi
fi

echo "=== SSH Access Ready ==="

# Mount EBS volume for monitoring data
echo "=== Mounting EBS volume for monitoring data ==="

echo "Waiting for EBS volume to be attached..."
# Modern AWS instances use NVMe naming (/dev/nvme1n1) for secondary volumes
DEVICE=""
MAX_WAIT=180
WAITED=0

while [ -z "$DEVICE" ] && [ $WAITED -lt $MAX_WAIT ]; do
    if [ -e "/dev/nvme1n1" ]; then
        DEVICE="/dev/nvme1n1"
        echo "Found EBS volume: /dev/nvme1n1"
        break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ -z "$DEVICE" ]; then
    echo "ERROR: EBS volume not found after $${MAX_WAIT}s"
    exit 1
fi

# Check if volume is already formatted (has filesystem)
if ! blkid "$DEVICE" > /dev/null 2>&1; then
    echo "Formatting new volume $DEVICE with XFS..."
    mkfs -t xfs "$DEVICE"
else
    echo "Volume $DEVICE already formatted (restored from snapshot), skipping mkfs"
fi

# Set proper permissions for monitoring directory
mkdir -p /data/monitoring
echo "Mounting $DEVICE to /data/monitoring..."
mount "$DEVICE" /data/monitoring

# Get UUID for fstab (more reliable than device name)
UUID=$(blkid -s UUID -o value "$DEVICE")

# Add to /etc/fstab for automatic mount on reboot
if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID /data/monitoring xfs defaults,nofail 0 2" >> /etc/fstab
    echo "Added volume to /etc/fstab for automatic mounting"
fi

# Set full read/write/execute permissions for monitoring directory so all pods can access
chmod 777 /data/monitoring

echo "=== EBS volume mounted successfully ==="

# Install K3s server (master node)
echo "=== Installing K3s Server ==="

# K3s installation flags:
# --server: Run K3s in server mode (master)
# --cluster-init: Initialize cluster (standalone master)
# --token: Cluster token for worker node joining
# --disable servicelb: Disable K3s default service load balancer (we use ALB + nginx-ingress)
# --disable traefik: Disable Traefik ingress controller (we use nginx-ingress)
# --disable local-storage: Disable local-path provisioner (optional, remove if needed)
# --datastore-endpoint: Point to local etcd (already at /var/lib/rancher/k3s/server/db)

curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --token="${cluster_token}" \
  --disable=servicelb \
  --disable=traefik \
  --disable=local-storage \
  --flannel-backend=vxlan

# Wait for K3s to be ready
echo "=== Waiting for K3s to be ready ==="
for i in {1..60}; do
  if /usr/local/bin/k3s kubectl get nodes &>/dev/null; then
    echo "K3s is ready!"
    break
  fi
  echo "Waiting for K3s... ($i/60)"
  sleep 5
done

# Get kubeconfig and make it readable
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
echo "K3s kubeconfig: /etc/rancher/k3s/k3s.yaml"

# Set kubeconfig for helm and kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Install nginx-ingress controller via Helm
echo "=== Installing nginx-ingress controller ==="

# Install Helm if not present
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Add nginx-ingress Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx-ingress on port 30080/30443
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.metrics.enabled=true \
  --wait

echo "=== nginx-ingress installed ==="

# Install cert-manager for TLS certificate management (needed by nginx-ingress)
echo "=== Installing cert-manager ==="

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait

echo "=== cert-manager installed ==="

# Create namespace for applications
echo "=== Creating application namespace ==="
kubectl create namespace space2study --dry-run=client -o yaml | kubectl apply -f -



# Enable IP forwarding for Flannel VXLAN
echo "=== Configuring network for Flannel ==="
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf

# Create systemd service for K3s (enable auto-restart)
systemctl enable k3s

echo "=== K3s Master Node Initialization Complete ==="
echo ""
echo "Master node is ready!"
echo "To access the cluster:"
echo "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
echo "  k3s kubectl get nodes"
echo ""
echo "To access this instance via SSM Session Manager:"
echo "  aws ssm start-session --target <instance-id> --region <region>"
echo ""
echo "nginx-ingress is running on:"
echo "  HTTP:  30080"
echo "  HTTPS: 30443"
echo ""
