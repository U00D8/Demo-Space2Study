#!/bin/bash
set -e

# K3s Worker Node Initialization Script
# This script sets up a K3s worker node with:
# - K3s agent installation
# - Connection to master node
# - SSM Session Manager for secure access

echo "=== K3s Worker Node Initialization Starting ==="

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
  jq

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

# Wait for master node to be ready
echo "=== Waiting for master node at ${master_ip} ==="

for i in {1..60}; do
  if nc -zv ${master_ip} 6443 2>/dev/null; then
    echo "Master node is reachable!"
    break
  fi
  echo "Waiting for master node... ($i/60)"
  sleep 5
done

# Enable IP forwarding for Flannel VXLAN
echo "=== Configuring network for Flannel ==="
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf

# Install K3s agent (worker node)
echo "=== Installing K3s Agent ==="

# K3s agent installation flags:
# --server: Master node URL (https://master_ip:6443)
# --token: Cluster token (must match master token)
# Note: flannel-backend is configured on master, not on agent

curl -sfL https://get.k3s.io | sh -s - agent \
  --server https://${master_ip}:6443 \
  --token="${cluster_token}"

# Wait for node to be registered
echo "=== Waiting for worker node to join cluster ==="

# Give K3s agent time to start
sleep 10

# Check if node is ready
for i in {1..60}; do
  if [ -f /var/lib/rancher/k3s/agent/kubelet.kubeconfig ]; then
    echo "Worker node joined cluster!"
    break
  fi
  echo "Waiting for worker to join... ($i/60)"
  sleep 5
done

# Enable systemd service for K3s agent (enable auto-restart)
systemctl enable k3s-agent

echo "=== K3s Worker Node Initialization Complete ==="
echo ""
echo "Worker node is ready and joined the cluster!"
echo ""
echo "To verify worker node from master:"
echo "  k3s kubectl get nodes"
echo ""
echo "To access this instance via SSM Session Manager:"
echo "  aws ssm start-session --target <instance-id> --region <region>"
echo ""

