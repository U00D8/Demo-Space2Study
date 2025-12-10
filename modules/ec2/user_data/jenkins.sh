#!/bin/bash
# Jenkins Controller Setup Script for Amazon Linux 2023

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
dnf install -y git htop vim aws-cli jq

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
mkdir -p /var/jenkins_home

# Mount the volume
echo "Mounting $DEVICE to /var/jenkins_home..."
mount "$DEVICE" /var/jenkins_home

# Get UUID for fstab (more reliable than device name)
UUID=$(blkid -s UUID -o value "$DEVICE")

# Add to /etc/fstab for automatic mount on reboot
if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID /var/jenkins_home xfs defaults,nofail 0 2" >> /etc/fstab
    echo "Added volume to /etc/fstab for automatic mounting"
fi

# Set ownership for Jenkins user (UID 1000)
chown -R 1000:1000 /var/jenkins_home

# Configure Docker daemon
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker

# Pull Jenkins LTS image
docker pull jenkins/jenkins:lts

# Create JCasC directory
mkdir -p /var/jenkins_home/casc_configs
chown -R 1000:1000 /var/jenkins_home/casc_configs

# Get the subnet ID from terraform and inject into JCasC YAML
SUBNET_ID="${jenkins_agent_subnet_id}"

# Create Jenkins Configuration as Code YAML
cat > /var/jenkins_home/casc_configs/jenkins.yaml <<'EOFCASC'
jenkins:
  clouds:
    - amazonEC2:
        name: "aws-eu-north-1"
        region: "${region}"
        useInstanceProfileForCredentials: true
        roleArn: "arn:aws:iam::${account_id}:role/${project_name}-jenkins-agent-role"
        sshKeysCredentialsId: "jenkins-aws-key"
        altEC2Endpoint: "https://ec2.eu-north-1.amazonaws.com"
        templates:
          - ami: "ami-0ebce4d7c262896a3"
            amiType:
              unixData:
                sshPort: "22"
                rootCommandPrefix: ""
            associateIPStrategy: PRIVATE_IP
            connectBySSHProcess: false
            connectionStrategy: PRIVATE_IP
            deleteRootOnTermination: true
            description: "Amazon Linux 2023 Jenkins Agent"
            ebsOptimized: false
            hostKeyVerificationStrategy: CHECK_NEW_HARD
            iamInstanceProfile: "arn:aws:iam::${account_id}:instance-profile/${project_name}-jenkins-agent-profile"
            idleTerminationMinutes: "15"
            instanceCapStr: "1"
            type: "t3.medium"
            labelString: "docker-nodejs"
            launchTimeoutStr: ""
            maxTotalUses: -1
            mode: EXCLUSIVE
            metadataEndpointEnabled: true
            metadataHopsLimit: 1
            metadataSupported: true
            metadataTokensRequired: true
            minimumNumberOfInstances: 0
            minimumNumberOfSpareInstances: 0
            monitoring: true
            numExecutors: 1
            remoteAdmin: "ec2-user"
            remoteFS: "/home/ec2-user/jenkins"
            securityGroups: "${project_name}-jenkins-agent-sg"
            stopOnTerminate: false
            subnetId: "${jenkins_agent_subnet_id}"
            t2Unlimited: false
            tags:
              - name: "Name"
                value: "jenkins-agent"
              - name: "Environment"
                value: "dev"
              - name: "ManagedBy"
                value: "jenkins"
            tenancy: Default
            useEphemeralDevices: false
            zone: "${region}a,${region}b"
    - amazonEC2:
        name: "aws-eu-north-1-k3s"
        region: "${region}"
        useInstanceProfileForCredentials: true
        roleArn: "arn:aws:iam::${account_id}:role/${project_name}-jenkins-agent-role"
        sshKeysCredentialsId: "jenkins-aws-key"
        altEC2Endpoint: "https://ec2.eu-north-1.amazonaws.com"
        templates:
          - ami: "ami-08d20f05cc563bc10"
            amiType:
              unixData:
                sshPort: "22"
                rootCommandPrefix: ""
            associateIPStrategy: PRIVATE_IP
            connectBySSHProcess: false
            connectionStrategy: PRIVATE_IP
            deleteRootOnTermination: true
            description: "Amazon Linux 2023 Jenkins Agent - K3s"
            ebsOptimized: false
            hostKeyVerificationStrategy: CHECK_NEW_HARD
            iamInstanceProfile: "arn:aws:iam::${account_id}:instance-profile/${project_name}-jenkins-agent-profile"
            idleTerminationMinutes: "15"
            instanceCapStr: "1"
            type: "t3.small"
            labelString: "k3s"
            launchTimeoutStr: ""
            maxTotalUses: -1
            mode: EXCLUSIVE
            metadataEndpointEnabled: true
            metadataHopsLimit: 1
            metadataSupported: true
            metadataTokensRequired: true
            minimumNumberOfInstances: 0
            minimumNumberOfSpareInstances: 0
            monitoring: true
            numExecutors: 5
            remoteAdmin: "ec2-user"
            remoteFS: "/home/ec2-user/jenkins"
            securityGroups: "${project_name}-jenkins-agent-sg"
            stopOnTerminate: false
            subnetId: "${jenkins_agent_subnet_id}"
            t2Unlimited: false
            tags:
              - name: "Name"
                value: "jenkins-agent-k3s"
              - name: "Environment"
                value: "dev"
              - name: "ManagedBy"
                value: "jenkins"
            tenancy: Default
            useEphemeralDevices: false
            zone: "${region}a,${region}b"
EOFCASC

# Set correct ownership
chown -R 1000:1000 /var/jenkins_home/casc_configs/jenkins.yaml

# Create Jenkins systemd service
cat > /etc/systemd/system/jenkins.service <<EOF
[Unit]
Description=Jenkins Docker Container
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop jenkins
ExecStartPre=-/usr/bin/docker rm jenkins
ExecStart=/usr/bin/docker run --rm --name jenkins \
  --network host \
  -v /var/jenkins_home:/var/jenkins_home \
  -e JAVA_OPTS="-Xmx1024m -Xms512m -Djenkins.install.runSetupWizard=false" \
  -e JENKINS_URL="http://jenkins.internal.space2study.pp.ua:8080/" \
  -e AWS_REGION=${region} \
  -e AWS_DEFAULT_REGION=${region} \
  -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs \
  jenkins/jenkins:lts

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

# Enable and start Jenkins
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start
echo "Waiting for Jenkins to start..."
sleep 60

# Get initial admin password
if [ -f /var/jenkins_home/secrets/initialAdminPassword ]; then
    INITIAL_PASSWORD=$(cat /var/jenkins_home/secrets/initialAdminPassword)
    echo "Jenkins Initial Admin Password: $INITIAL_PASSWORD" > /home/ec2-user/jenkins-initial-password.txt
    chown ec2-user:ec2-user /home/ec2-user/jenkins-initial-password.txt
fi

echo "Jenkins Controller setup complete!"
