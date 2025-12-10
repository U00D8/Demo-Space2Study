// Jenkinsfile for Frontend K3s Deployment
// Retrieves secrets from Vault and deploys to K3s cluster

pipeline {
    agent {
        label 'k3s'  // Use a specific Jenkins agent with K3s access
    }
    // agent any
    
    environment {
        // K3s and Vault configuration
        KUBECONFIG = "${HOME}/.kube/config"
        NAMESPACE = 'space2study'
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    stages {
        stage('Setup SSH Key for K3s Access') {
            steps {
                script {
                    echo "🔑 Setting up AWS private key for K3s cluster access..."
                    echo "Debug: Attempting to load jenkins-aws-key credential..."
                    
                    // Using SSH Username with private key credential
                    withCredentials([sshUserPrivateKey(credentialsId: 'jenkins-aws-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                        sh '''
                            echo "Debug: SSH_KEY_FILE=${SSH_KEY_FILE}"
                            echo "Debug: SSH_USER=${SSH_USER}"
                            
                            # Create SSH directory with proper permissions
                            mkdir -p ~/.ssh
                            chmod 700 ~/.ssh
                            
                            # Copy private key from Jenkins credentials
                            echo "Debug: Copying SSH key to ~/.ssh/space2study-aws.pem"
                            cp "${SSH_KEY_FILE}" ~/.ssh/space2study-aws.pem
                            chmod 600 ~/.ssh/space2study-aws.pem
                            
                            echo "✅ Private key installed at ~/.ssh/space2study-aws.pem"
                            ls -lah ~/.ssh/space2study-aws.pem
                            
                            # Verify key format
                            echo "Debug: Key file first line:"
                            head -1 ~/.ssh/space2study-aws.pem
                        '''
                    }
                }
            }
        }
        
        stage('Generate Kubeconfig from K3s Master') {
            steps {
                script {
                    echo "📋 Generating kubeconfig from K3s master..."
                    
                    // Use SSH private key credential to fetch kubeconfig from K3s master
                    withCredentials([sshUserPrivateKey(credentialsId: 'jenkins-aws-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                        sh '''
                            # K3s master details
                            K3S_MASTER_DNS="k3s-master.internal.space2study.pp.ua"
                            K3S_MASTER_USER="ubuntu"
                            SSH_KEY="${SSH_KEY_FILE}"
                            
                            echo "🔐 Fetching kubeconfig from K3s master..."
                            echo "  Master: ${K3S_MASTER_DNS}"
                            echo "  User: ${K3S_MASTER_USER}"
                            
                            # Create .kube directory
                            mkdir -p "${HOME}/.kube"
                            
                            # SSH to K3s master and fetch kubeconfig
                            echo "Connecting to K3s master via SSH..."
                            ssh -i "${SSH_KEY}" \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=30 \
                                -o UserKnownHostsFile=/dev/null \
                                "${K3S_MASTER_USER}@${K3S_MASTER_DNS}" \
                                "sudo cat /etc/rancher/k3s/k3s.yaml" > /tmp/k3s-kubeconfig-original.yaml
                            
                            if [ $? -ne 0 ]; then
                                echo "❌ Failed to fetch kubeconfig from K3s master"
                                exit 1
                            fi
                            
                            echo "✅ Kubeconfig fetched from K3s master"
                            
                            # Replace localhost/127.0.0.1 with K3s master DNS for internal access
                            # Get the K3s master internal IP from Route53 DNS name
                            echo "🔍 Resolving K3s master IP from DNS..."
                            K3S_MASTER_IP=$(getent hosts "${K3S_MASTER_DNS}" | awk '{print $1}' | head -1)
                            if [ -z "${K3S_MASTER_IP}" ]; then
                                echo "❌ Failed to resolve ${K3S_MASTER_DNS} to an IP address"
                                exit 1
                            fi
                            echo "✅ K3s Master IP resolved: ${K3S_MASTER_IP}"
                            
                            # Replace localhost/127.0.0.1 with K3s master IP (not DNS, to match TLS certificate)
                            echo "🔄 Updating kubeconfig to use K3s master IP for TLS certificate validation..."
                            sed -i "s|127.0.0.1|${K3S_MASTER_IP}|g" /tmp/k3s-kubeconfig-original.yaml
                            sed -i "s|localhost|${K3S_MASTER_IP}|g" /tmp/k3s-kubeconfig-original.yaml
                            sed -i "s|${K3S_MASTER_DNS}|${K3S_MASTER_IP}|g" /tmp/k3s-kubeconfig-original.yaml
                            
                            # Also disable TLS verification as a fallback (since we trust internal network)
                            sed -i 's|insecure-skip-tls-verify: false|insecure-skip-tls-verify: true|g' /tmp/k3s-kubeconfig-original.yaml
                            
                            # Copy to agent's .kube/config
                            cp /tmp/k3s-kubeconfig-original.yaml "${HOME}/.kube/config"
                            chmod 600 "${HOME}/.kube/config"
                            
                            echo "✅ Kubeconfig installed at ${HOME}/.kube/config"
                            
                            # Verify kubeconfig content
                            echo "Debug: Kubeconfig content:"
                            cat "${HOME}/.kube/config"
                            
                            # Clean up temp file
                            rm -f /tmp/k3s-kubeconfig-original.yaml
                        '''
                    }
                }
            }
        }
        
        stage('Verify K3s Cluster') {
            steps {
                script {
                    echo "🔍 Verifying K3s cluster connectivity..."
                    sh '''
                        echo "Debug: KUBECONFIG=${KUBECONFIG}"
                        echo "Debug: Current kubeconfig:"
                        ls -lah "${KUBECONFIG}" 2>&1 || echo "  ⚠️  KUBECONFIG file not found"
                        
                        echo ""
                        echo "Debug: kubectl config view:"
                        kubectl config view 2>&1 | head -20
                        
                        echo ""
                        echo "Debug: kubectl cluster-info:"
                        kubectl cluster-info 2>&1
                        
                        if kubectl cluster-info &>/dev/null; then
                            echo "✅ K3s cluster is reachable"
                            kubectl get nodes
                        else
                            echo "❌ K3s cluster is not reachable"
                            echo "Debug: Checking if kubeconfig exists and is valid..."
                            
                            # Check if KUBECONFIG file exists
                            if [ ! -f "${KUBECONFIG}" ]; then
                                echo "ERROR: KUBECONFIG file not found at ${KUBECONFIG}"
                                echo "Available kubeconfigs:"
                                find /home/ec2-user -name "*kube*" -o -name "*k3s*" 2>/dev/null | head -20
                                exit 1
                            fi
                            
                            echo "KUBECONFIG file exists but connection failed"
                            exit 1
                        fi
                    '''
                }
            }
        }
        
        stage('Get Secrets from Vault') {
            steps {
                script {
                    echo "🔐 Retrieving secrets from Vault using Jenkins plugin..."
                    withVault([
                        configuration: [
                            vaultCredentialId: 'vault-approle-jenkins',
                            engineVersion: 2,
                            skipSslVerification: false,
                            vaultUrl: 'http://vault.internal.space2study.pp.ua:8200'
                        ],
                        vaultSecrets: [
                            [
                                path: 'space2study/dev/frontend/env-vars',
                                secretValues: [
                                    [envVar: 'VITE_API_BASE_PATH', vaultKey: 'VITE_API_BASE_PATH']
                                ]
                            ]
                        ]
                    ]) {
                        sh '''
                            echo "✅ Vault authentication successful"
                            
                            # Write the VITE_API_BASE_PATH to a temp file for verification
                            echo "📝 Writing VITE_API_BASE_PATH to /tmp/frontend-env.txt"
                            echo "VITE_API_BASE_PATH=${VITE_API_BASE_PATH}" > /tmp/frontend-env.txt
                            
                            # Verify we got the value
                            if [ -z "${VITE_API_BASE_PATH}" ]; then
                                echo "❌ Failed to retrieve VITE_API_BASE_PATH from Vault"
                                exit 1
                            fi
                            
                            echo "✅ Secret retrieved successfully"
                            echo "VITE_API_BASE_PATH value written to /tmp/frontend-env.txt"
                        '''
                    }
                }
            }
        }
        
        stage('Create K3s Namespace') {
            steps {
                script {
                    echo "📦 Ensuring space2study namespace exists..."
                    sh '''
                        kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                        echo "✅ Namespace '${NAMESPACE}' ready"
                    '''
                }
            }
        }
        
        stage('Create TLS Secret from Cloudflare Certs') {
            steps {
                script {
                    echo "🔐 Creating TLS secret from Cloudflare Origin Certificates..."
                    withCredentials([
                        file(credentialsId: 'cloudflare-cert-pem', variable: 'CERT_FILE'),
                        file(credentialsId: 'cloudflare-key-pem', variable: 'KEY_FILE')
                    ]) {
                        sh '''
                            echo "📋 Creating Kubernetes TLS secret with Cloudflare certificates..."
                            
                            # Create or update the TLS secret
                            kubectl create secret tls space2study-frontend-tls \
                              --cert="${CERT_FILE}" \
                              --key="${KEY_FILE}" \
                              --namespace=${NAMESPACE} \
                              --dry-run=client -o yaml | kubectl apply -f -
                            
                            if [ $? -eq 0 ]; then
                                echo "✅ TLS secret 'space2study-frontend-tls' created/updated successfully"
                            else
                                echo "❌ Failed to create TLS secret"
                                exit 1
                            fi
                            
                            # Verify the secret was created
                            kubectl get secret -n ${NAMESPACE} space2study-frontend-tls -o jsonpath='{.type}'
                            echo ""
                            echo "✅ TLS secret verified in namespace '${NAMESPACE}'"
                        '''
                    }
                }
            }
        }
        
        stage('Create ECR Pull Secret') {
            steps {
                script {
                    echo "🔐 Creating ECR pull secret in K3s..."
                    withCredentials([
                        string(credentialsId: 'aws-region', variable: 'AWS_REGION'),
                        string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY'),
                        string(credentialsId: 'ecr-repository-frontend', variable: 'ECR_REPOSITORY')
                    ]) {
                        sh '''
                            # Get ECR login token - same as docker login
                            echo "🔑 Getting ECR authentication token..."
                            ECR_TOKEN=$(aws ecr get-login-password --region ${AWS_REGION})
                            
                            # Extract registry URL without https:// prefix
                            REGISTRY_URL=$(echo ${ECR_REGISTRY} | sed 's|https://||')
                            
                            echo "Creating docker-registry secret for: ${REGISTRY_URL}"
                            
                            # Create or update the secret in dry-run mode then apply
                            kubectl create secret docker-registry ecr-secret \
                                --docker-server="${REGISTRY_URL}" \
                                --docker-username=AWS \
                                --docker-password="${ECR_TOKEN}" \
                                --namespace="${NAMESPACE}" \
                                --dry-run=client -o yaml | kubectl apply -f -
                            
                            echo "✅ ECR pull secret created/updated"
                        '''
                    }
                }
            }
        }
        
        stage('Create Frontend Secrets in K3s') {
            steps {
                script {
                    echo "🔑 Creating K3s secrets from environment variables..."
                    sh '''
                        # Load the environment file
                        . /tmp/frontend-env.txt
                        
                        # Verify we have the value
                        if [ -z "${VITE_API_BASE_PATH}" ]; then
                            echo "❌ VITE_API_BASE_PATH not set"
                            exit 1
                        fi
                        
                        echo "✅ Environment variables loaded: VITE_API_BASE_PATH=${VITE_API_BASE_PATH}"
                        
                        # Create K3s secret
                        kubectl create secret generic frontend-secrets \
                          --from-literal=VITE_API_BASE_PATH="${VITE_API_BASE_PATH}" \
                          --namespace=${NAMESPACE} \
                          --dry-run=client -o yaml | kubectl apply -f -
                        
                        echo "✅ K3s frontend secrets created/updated"
                        
                        # Verify secret was created
                        kubectl get secrets -n ${NAMESPACE} frontend-secrets
                    '''
                }
            }
        }
        
        stage('Create Frontend Runtime Config ConfigMap') {
            steps {
                script {
                    echo "⚙️  Creating runtime configuration ConfigMap..."
                    sh '''
                        # Load the environment file
                        . /tmp/frontend-env.txt
                        
                        # Create temporary config.js file
                        cat > /tmp/config.js << CONFIG_EOF
// Runtime configuration injected by Kubernetes at deployment time
window.__CONFIG__ = {
  VITE_API_BASE_PATH: '${VITE_API_BASE_PATH}'
};
CONFIG_EOF
                        
                        echo "📄 Generated config.js:"
                        cat /tmp/config.js
                        
                        # Create ConfigMap from the config file
                        kubectl create configmap frontend-runtime-config \
                          --from-file=config.js=/tmp/config.js \
                          --namespace=${NAMESPACE} \
                          --dry-run=client -o yaml | kubectl apply -f -
                        
                        echo "✅ Frontend runtime config ConfigMap created/updated"
                        
                        # Verify ConfigMap was created
                        echo "ConfigMap content:"
                        kubectl get configmap -n ${NAMESPACE} frontend-runtime-config -o yaml | grep -A 5 "data:"
                    '''
                }
            }
        }
        
        stage('Deploy Frontend Manifest') {
            steps {
                script {
                    echo "🚀 Deploying frontend to K3s..."
                    withCredentials([string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY')]) {
                        sh '''
                            # Replace ECR_REGISTRY in manifest
                            sed -i "s|ACCOUNT_ID.dkr.ecr.eu-north-1.amazonaws.com|${ECR_REGISTRY}|g" \
                              k8s-manifests/frontend-deployment.yaml
                            
                            # Apply frontend deployment
                            echo "Applying k8s-manifests/frontend-deployment.yaml..."
                            kubectl apply -f k8s-manifests/frontend-deployment.yaml
                            
                            # Wait for deployment to be ready
                            echo "⏳ Waiting for frontend deployment to be ready..."
                            timeout 5m kubectl rollout status deployment/frontend \
                              -n ${NAMESPACE} || true
                            
                            # Check if pods are running
                            echo -e "\n📊 Checking pod status..."
                            kubectl get pods -n ${NAMESPACE} -l app=frontend -o wide
                            
                            # Show pod logs if any exist
                            PODS=$(kubectl get pods -n ${NAMESPACE} -l app=frontend -o jsonpath='{.items[*].metadata.name}')
                            if [ -n "$PODS" ]; then
                                for pod in $PODS; do
                                    echo -e "\n📋 Logs from pod $pod:"
                                    kubectl logs -n ${NAMESPACE} $pod --tail=20 || echo "No logs yet"
                                done
                            fi
                            
                            echo "✅ Frontend deployment applied"
                        '''
                    }
                }
            }
        }
        
        stage('Deploy Ingress') {
            steps {
                script {
                    echo "🌐 Deploying ingress rules..."
                    sh '''
                        kubectl apply -f k8s-manifests/ingress.yaml
                        
                        # Wait a moment for ingress to be created
                        sleep 5
                        
                        echo "📋 Ingress configuration:"
                        kubectl get ingress -n ${NAMESPACE}
                        kubectl describe ingress space2study-ingress -n ${NAMESPACE}
                    '''
                }
            }
        }
        
        stage('Test Manifest Applied') {
            steps {
                script {
                    echo "🧪 Testing if manifest was applied correctly..."
                    sh '''
                        echo "=== Checking Deployment ==="
                        if kubectl get deployment frontend -n ${NAMESPACE} &>/dev/null; then
                            echo "✅ Deployment 'frontend' exists"
                            kubectl describe deployment frontend -n ${NAMESPACE} | grep -A 5 "Image:"
                        else
                            echo "❌ Deployment 'frontend' NOT found"
                            exit 1
                        fi
                        
                        echo -e "\n=== Checking Service ==="
                        if kubectl get svc frontend -n ${NAMESPACE} &>/dev/null; then
                            echo "✅ Service 'frontend' exists"
                            kubectl get svc frontend -n ${NAMESPACE} -o wide
                        else
                            echo "❌ Service 'frontend' NOT found"
                            exit 1
                        fi
                        
                        echo -e "\n=== Checking Pods ==="
                        POD_COUNT=$(kubectl get pods -n ${NAMESPACE} -l app=frontend --no-headers 2>/dev/null | wc -l)
                        if [ $POD_COUNT -gt 0 ]; then
                            echo "✅ $POD_COUNT pod(s) found"
                            kubectl get pods -n ${NAMESPACE} -l app=frontend -o wide
                        else
                            echo "⚠️  No pods running yet (may still be starting)"
                        fi
                        
                        echo -e "\n=== Checking Ingress ==="
                        if kubectl get ingress space2study-ingress -n ${NAMESPACE} &>/dev/null; then
                            echo "✅ Ingress 'space2study-ingress' exists"
                            kubectl get ingress -n ${NAMESPACE} -o wide
                        else
                            echo "⚠️  Ingress not found (may not be deployed yet)"
                        fi
                    '''
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    echo "✔️  Verifying frontend deployment..."
                    sh '''
                        echo "=== Pod Status ==="
                        kubectl get pods -n ${NAMESPACE} -l app=frontend -o wide
                        
                        echo -e "\n=== Pod Logs (last 30 lines) ==="
                        kubectl logs -n ${NAMESPACE} -l app=frontend --tail=30 || echo "No logs yet"
                        
                        echo -e "\n=== Nginx Ingress Controller Logs ==="
                        kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 2>/dev/null || echo "Ingress logs not available"
                        
                        echo -e "\n=== Ingress Configuration Details ==="
                        kubectl describe ingress space2study-ingress -n ${NAMESPACE}
                        
                        echo -e "\n=== Service Status ==="
                        kubectl get svc -n ${NAMESPACE} frontend
                        
                        echo -e "\n=== Ingress Status ==="
                        kubectl get ingress -n ${NAMESPACE}
                        
                        echo -e "\n=== Health Check (via NodePort) ==="
                        WORKER_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[?(@.type=="InternalIP")].address}')
                        echo "Testing nginx-ingress on worker: ${WORKER_IP}"
                        curl -k -I https://localhost:30443/ 2>&1 | head -5 || echo "Cannot test from Jenkins, check from ALB"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "📊 Deployment Summary:"
                sh '''
                    echo "=== Frontend Pods ==="
                    kubectl get pods -n ${NAMESPACE} -l app=frontend
                    
                    echo -e "\n=== Resource Usage ==="
                    kubectl top pods -n ${NAMESPACE} -l app=frontend || echo "Metrics not available yet"
                    
                    # Clean up temp files
                    rm -f /tmp/frontend-secrets.json
                '''
            }
        }
        
        success {
            script {
                echo "✅ Frontend deployment to K3s SUCCESSFUL!"
                echo "Frontend is available at: https://space2study.pp.ua (via nginx-ingress NodePort 30443)"
            }
        }
        
        failure {
            script {
                echo "❌ Frontend deployment FAILED!"
                sh '''
                    echo "Last 50 lines of frontend pod logs:"
                    kubectl logs -n ${NAMESPACE} -l app=frontend --tail=50 || echo "No logs available"
                '''
            }
        }
    }
}
