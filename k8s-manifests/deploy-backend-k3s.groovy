// Jenkinsfile for Backend K3s Deployment
// Retrieves secrets from Vault and deploys to K3s cluster

pipeline {
    agent {
        label 'k3s'  // Use a specific Jenkins agent with K3s access
    }
    
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
                            echo "🔍 Resolving K3s master IP from DNS..."
                            K3S_MASTER_IP=$(getent hosts "${K3S_MASTER_DNS}" | awk '{print $1}' | head -1)
                            if [ -z "${K3S_MASTER_IP}" ]; then
                                echo "❌ Failed to resolve ${K3S_MASTER_DNS} to an IP address"
                                exit 1
                            fi
                            echo "✅ K3s Master IP resolved: ${K3S_MASTER_IP}"
                            
                            # Use sed to replace localhost with K3s master IP in kubeconfig
                            echo "Updating kubeconfig to use K3s master IP..."
                            sed -i "s|https://127.0.0.1|https://${K3S_MASTER_IP}|g" /tmp/k3s-kubeconfig-original.yaml
                            
                            # Copy to KUBECONFIG location
                            cp /tmp/k3s-kubeconfig-original.yaml "${KUBECONFIG}"
                            chmod 600 "${KUBECONFIG}"
                            
                            echo "✅ Kubeconfig configured at ${KUBECONFIG}"
                            
                            # Verify kubeconfig
                            echo "Debug: Kubeconfig content (first 10 lines):"
                            head -10 "${KUBECONFIG}"
                            
                            # Clean up temp files
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
                            echo "Cluster nodes:"
                            kubectl get nodes
                        else
                            echo "❌ K3s cluster is not reachable"
                            echo "Debug: Checking if kubeconfig exists and is valid..."
                            
                            if [ ! -f "${KUBECONFIG}" ]; then
                                echo "ERROR: KUBECONFIG file not found at ${KUBECONFIG}"
                                exit 1
                            fi
                            
                            echo "KUBECONFIG file exists but connection failed"
                            exit 1
                        fi
                    '''
                }
            }
        }
        
        stage('Get Backend Secrets from Vault') {
            steps {
                script {
                    echo "🔐 Retrieving backend secrets from Vault..."
                    withVault([
                        configuration: [
                            vaultCredentialId: 'vault-approle-jenkins',
                            engineVersion: 2,
                            skipSslVerification: false,
                            vaultUrl: 'http://vault.internal.space2study.pp.ua:8200'
                        ],
                        vaultSecrets: [
                            [
                                path: 'space2study/dev/backend/env-vars',
                                secretValues: [
                                    [envVar: 'CLIENT_URL', vaultKey: 'CLIENT_URL'],
                                    [envVar: 'COOKIE_DOMAIN', vaultKey: 'COOKIE_DOMAIN'],
                                    [envVar: 'JWT_ACCESS_EXPIRES_IN', vaultKey: 'JWT_ACCESS_EXPIRES_IN'],
                                    [envVar: 'JWT_ACCESS_SECRET', vaultKey: 'JWT_ACCESS_SECRET'],
                                    [envVar: 'JWT_CONFIRM_EXPIRES_IN', vaultKey: 'JWT_CONFIRM_EXPIRES_IN'],
                                    [envVar: 'JWT_CONFIRM_SECRET', vaultKey: 'JWT_CONFIRM_SECRET'],
                                    [envVar: 'JWT_REFRESH_EXPIRES_IN', vaultKey: 'JWT_REFRESH_EXPIRES_IN'],
                                    [envVar: 'JWT_REFRESH_SECRET', vaultKey: 'JWT_REFRESH_SECRET'],
                                    [envVar: 'JWT_RESET_EXPIRES_IN', vaultKey: 'JWT_RESET_EXPIRES_IN'],
                                    [envVar: 'JWT_RESET_SECRET', vaultKey: 'JWT_RESET_SECRET'],
                                    [envVar: 'MAIL_FIRSTNAME', vaultKey: 'MAIL_FIRSTNAME'],
                                    [envVar: 'MAIL_LASTNAME', vaultKey: 'MAIL_LASTNAME'],
                                    [envVar: 'MAIL_PASS', vaultKey: 'MAIL_PASS'],
                                    [envVar: 'MAIL_USER', vaultKey: 'MAIL_USER'],
                                    [envVar: 'SERVER_PORT', vaultKey: 'SERVER_PORT'],
                                    [envVar: 'SERVER_URL', vaultKey: 'SERVER_URL']
                                ]
                            ],
                            [
                                path: 'space2study/dev/database/mongodb',
                                secretValues: [
                                    [envVar: 'MONGODB_URL', vaultKey: 'url']
                                ]
                            ]
                        ]
                    ]) {
                        sh '''
                            echo "✅ Vault authentication successful"
                            
                            # Write all backend env vars to a temp file for verification
                            echo "📝 Writing backend environment to /tmp/backend-env.txt"
                            
                            # Use echo to write variables (they're available in environment)
                            echo "CLIENT_URL=${CLIENT_URL}" > /tmp/backend-env.txt
                            echo "COOKIE_DOMAIN=${COOKIE_DOMAIN}" >> /tmp/backend-env.txt
                            echo "JWT_ACCESS_EXPIRES_IN=${JWT_ACCESS_EXPIRES_IN}" >> /tmp/backend-env.txt
                            echo "JWT_ACCESS_SECRET=${JWT_ACCESS_SECRET}" >> /tmp/backend-env.txt
                            echo "JWT_CONFIRM_EXPIRES_IN=${JWT_CONFIRM_EXPIRES_IN}" >> /tmp/backend-env.txt
                            echo "JWT_CONFIRM_SECRET=${JWT_CONFIRM_SECRET}" >> /tmp/backend-env.txt
                            echo "JWT_REFRESH_EXPIRES_IN=${JWT_REFRESH_EXPIRES_IN}" >> /tmp/backend-env.txt
                            echo "JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}" >> /tmp/backend-env.txt
                            echo "JWT_RESET_EXPIRES_IN=${JWT_RESET_EXPIRES_IN}" >> /tmp/backend-env.txt
                            echo "JWT_RESET_SECRET=${JWT_RESET_SECRET}" >> /tmp/backend-env.txt
                            echo "MAIL_FIRSTNAME=${MAIL_FIRSTNAME}" >> /tmp/backend-env.txt
                            echo "MAIL_LASTNAME=${MAIL_LASTNAME}" >> /tmp/backend-env.txt
                            echo "MAIL_PASS=${MAIL_PASS}" >> /tmp/backend-env.txt
                            echo "MAIL_USER=${MAIL_USER}" >> /tmp/backend-env.txt
                            echo "MONGODB_URL=${MONGODB_URL}" >> /tmp/backend-env.txt
                            echo "SERVER_PORT=${SERVER_PORT}" >> /tmp/backend-env.txt
                            echo "SERVER_URL=${SERVER_URL}" >> /tmp/backend-env.txt
                            
                            # Verify we got all required values
                            if [ -z "${SERVER_PORT}" ] || [ -z "${MONGODB_URL}" ] || [ -z "${JWT_ACCESS_SECRET}" ]; then
                                echo "❌ Failed to retrieve all backend secrets from Vault"
                                echo "DEBUG: SERVER_PORT=${SERVER_PORT}"
                                echo "DEBUG: MONGODB_URL=${MONGODB_URL}"
                                echo "DEBUG: JWT_ACCESS_SECRET=${JWT_ACCESS_SECRET}"
                                exit 1
                            fi
                            
                            echo "✅ All backend secrets retrieved successfully"
                            echo "File contents:"
                            cat /tmp/backend-env.txt
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
                            
                            # Create or update the TLS secret (shared with frontend)
                            kubectl create secret tls space2study-tls \
                              --cert="${CERT_FILE}" \
                              --key="${KEY_FILE}" \
                              --namespace=${NAMESPACE} \
                              --dry-run=client -o yaml | kubectl apply -f -
                            
                            if [ $? -eq 0 ]; then
                                echo "✅ TLS secret 'space2study-tls' created/updated successfully"
                            else
                                echo "❌ Failed to create TLS secret"
                                exit 1
                            fi
                            
                            # Verify the secret was created
                            kubectl get secret -n ${NAMESPACE} space2study-tls -o jsonpath='{.type}'
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
                        string(credentialsId: 'ecr-repository-backend', variable: 'ECR_REPOSITORY')
                    ]) {
                        sh '''
                            # Get ECR login token
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
        
        stage('Create Backend Secrets in K3s') {
            steps {
                script {
                    echo "🔑 Creating K3s secrets from backend environment variables..."
                    withVault([
                        configuration: [
                            vaultCredentialId: 'vault-approle-jenkins',
                            engineVersion: 2,
                            skipSslVerification: false,
                            vaultUrl: 'http://vault.internal.space2study.pp.ua:8200'
                        ],
                        vaultSecrets: [
                            [
                                path: 'space2study/dev/backend/env-vars',
                                secretValues: [
                                    [envVar: 'CLIENT_URL', vaultKey: 'CLIENT_URL'],
                                    [envVar: 'COOKIE_DOMAIN', vaultKey: 'COOKIE_DOMAIN'],
                                    [envVar: 'JWT_ACCESS_EXPIRES_IN', vaultKey: 'JWT_ACCESS_EXPIRES_IN'],
                                    [envVar: 'JWT_ACCESS_SECRET', vaultKey: 'JWT_ACCESS_SECRET'],
                                    [envVar: 'JWT_CONFIRM_EXPIRES_IN', vaultKey: 'JWT_CONFIRM_EXPIRES_IN'],
                                    [envVar: 'JWT_CONFIRM_SECRET', vaultKey: 'JWT_CONFIRM_SECRET'],
                                    [envVar: 'JWT_REFRESH_EXPIRES_IN', vaultKey: 'JWT_REFRESH_EXPIRES_IN'],
                                    [envVar: 'JWT_REFRESH_SECRET', vaultKey: 'JWT_REFRESH_SECRET'],
                                    [envVar: 'JWT_RESET_EXPIRES_IN', vaultKey: 'JWT_RESET_EXPIRES_IN'],
                                    [envVar: 'JWT_RESET_SECRET', vaultKey: 'JWT_RESET_SECRET'],
                                    [envVar: 'MAIL_FIRSTNAME', vaultKey: 'MAIL_FIRSTNAME'],
                                    [envVar: 'MAIL_LASTNAME', vaultKey: 'MAIL_LASTNAME'],
                                    [envVar: 'MAIL_PASS', vaultKey: 'MAIL_PASS'],
                                    [envVar: 'MAIL_USER', vaultKey: 'MAIL_USER'],
                                    [envVar: 'SERVER_PORT', vaultKey: 'SERVER_PORT'],
                                    [envVar: 'SERVER_URL', vaultKey: 'SERVER_URL']
                                ]
                            ],
                            [
                                path: 'space2study/dev/database/mongodb',
                                secretValues: [
                                    [envVar: 'MONGODB_URL', vaultKey: 'url']
                                ]
                            ]
                        ]
                    ]) {
                        sh '''
                            # Verify we have critical values
                            if [ -z "${SERVER_PORT}" ] || [ -z "${MONGODB_URL}" ]; then
                                echo "❌ Missing critical backend environment variables"
                                echo "DEBUG: SERVER_PORT=${SERVER_PORT}"
                                echo "DEBUG: MONGODB_URL=${MONGODB_URL}"
                                exit 1
                            fi
                            
                            echo "✅ Backend environment variables loaded from Vault"
                            
                            # Create K3s secret from all backend env vars
                            kubectl create secret generic backend-secrets \
                              --from-literal=CLIENT_URL="${CLIENT_URL}" \
                              --from-literal=COOKIE_DOMAIN="${COOKIE_DOMAIN}" \
                              --from-literal=JWT_ACCESS_EXPIRES_IN="${JWT_ACCESS_EXPIRES_IN}" \
                              --from-literal=JWT_ACCESS_SECRET="${JWT_ACCESS_SECRET}" \
                              --from-literal=JWT_CONFIRM_EXPIRES_IN="${JWT_CONFIRM_EXPIRES_IN}" \
                              --from-literal=JWT_CONFIRM_SECRET="${JWT_CONFIRM_SECRET}" \
                              --from-literal=JWT_REFRESH_EXPIRES_IN="${JWT_REFRESH_EXPIRES_IN}" \
                              --from-literal=JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET}" \
                              --from-literal=JWT_RESET_EXPIRES_IN="${JWT_RESET_EXPIRES_IN}" \
                              --from-literal=JWT_RESET_SECRET="${JWT_RESET_SECRET}" \
                              --from-literal=MAIL_FIRSTNAME="${MAIL_FIRSTNAME}" \
                              --from-literal=MAIL_LASTNAME="${MAIL_LASTNAME}" \
                              --from-literal=MAIL_PASS="${MAIL_PASS}" \
                              --from-literal=MAIL_USER="${MAIL_USER}" \
                              --from-literal=MONGODB_URL="${MONGODB_URL}" \
                              --from-literal=SERVER_PORT="${SERVER_PORT}" \
                              --from-literal=SERVER_URL="${SERVER_URL}" \
                              --namespace=${NAMESPACE} \
                              --dry-run=client -o yaml | kubectl apply -f -
                            
                            echo "✅ K3s backend secrets created/updated"
                            
                            # Verify secret was created
                            kubectl get secrets -n ${NAMESPACE} backend-secrets
                        '''
                    }
                }
            }
        }
        
        stage('Deploy Backend Manifest') {
            steps {
                script {
                    echo "🚀 Deploying backend to K3s..."
                    withCredentials([string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY')]) {
                        sh '''
                            # Replace ECR_REGISTRY in manifest
                            sed -i "s|ACCOUNT_ID.dkr.ecr.eu-north-1.amazonaws.com|${ECR_REGISTRY}|g" \
                              k8s-manifests/backend-deployment.yaml
                            
                            # Apply backend deployment
                            echo "Applying k8s-manifests/backend-deployment.yaml..."
                            kubectl apply -f k8s-manifests/backend-deployment.yaml
                            
                            # Wait for deployment to be ready
                            echo "⏳ Waiting for backend deployment to be ready..."
                            timeout 5m kubectl rollout status deployment/backend \
                              --namespace=${NAMESPACE} || true
                            
                            # Check if pods are running
                            echo -e "\n📊 Checking pod status..."
                            kubectl get pods -n ${NAMESPACE} -l app=backend -o wide
                            
                            echo "✅ Backend deployment applied"
                        '''
                    }
                }
            }
        }
        
        stage('Deploy/Update Ingress') {
            steps {
                script {
                    echo "🌐 Deploying/updating ingress rules..."
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
        
        stage('Test Backend Deployment') {
            steps {
                script {
                    echo "🧪 Testing if backend deployment was applied correctly..."
                    sh '''
                        echo "=== Checking Deployment ==="
                        if kubectl get deployment backend -n ${NAMESPACE} &>/dev/null; then
                            echo "✅ Backend deployment found"
                            kubectl describe deployment backend -n ${NAMESPACE} | grep -A 5 "Image:"
                        else
                            echo "❌ Backend deployment not found"
                            exit 1
                        fi
                        
                        echo -e "\n=== Checking Service ==="
                        if kubectl get svc backend -n ${NAMESPACE} &>/dev/null; then
                            echo "✅ Backend service found"
                            kubectl get svc backend -n ${NAMESPACE} -o wide
                        else
                            echo "❌ Backend service not found"
                            exit 1
                        fi
                        
                        echo -e "\n=== Checking Pods ==="
                        POD_COUNT=$(kubectl get pods -n ${NAMESPACE} -l app=backend --no-headers 2>/dev/null | wc -l)
                        if [ $POD_COUNT -gt 0 ]; then
                            echo "✅ Backend pods found: $POD_COUNT"
                            kubectl get pods -n ${NAMESPACE} -l app=backend -o wide
                        else
                            echo "⚠️  No pods running yet (may still be starting)"
                        fi
                        
                        echo -e "\n=== Checking Ingress ==="
                        if kubectl get ingress space2study-ingress -n ${NAMESPACE} &>/dev/null; then
                            echo "✅ Ingress found"
                            kubectl get ingress -n ${NAMESPACE} -o wide
                        else
                            echo "⚠️  Ingress not found"
                        fi
                    '''
                }
            }
        }
        
        stage('Verify Backend Deployment') {
            steps {
                script {
                    echo "✔️  Verifying backend deployment..."
                    sh '''
                        echo "=== Pod Status ==="
                        kubectl get pods -n ${NAMESPACE} -l app=backend -o wide
                        
                        echo -e "\n=== Pod Logs (last 30 lines) ==="
                        kubectl logs -n ${NAMESPACE} -l app=backend --tail=30 || echo "No logs yet"
                        
                        echo -e "\n=== Nginx Ingress Controller Logs ==="
                        kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 2>/dev/null || echo "Ingress logs not available"
                        
                        echo -e "\n=== Ingress Configuration Details ==="
                        kubectl describe ingress space2study-ingress -n ${NAMESPACE}
                        
                        echo -e "\n=== Service Status ==="
                        kubectl get svc -n ${NAMESPACE} backend
                        
                        echo -e "\n=== Ingress Status ==="
                        kubectl get ingress -n ${NAMESPACE}
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "📊 Backend Deployment Summary:"
                sh '''
                    echo "=== Backend Pods ==="
                    kubectl get pods -n ${NAMESPACE} -l app=backend
                    
                    echo -e "\n=== Resource Usage ==="
                    kubectl top pods -n ${NAMESPACE} -l app=backend || echo "Metrics not available yet"
                    
                    # Clean up temp files
                    rm -f /tmp/backend-env.txt
                '''
            }
        }
        
        success {
            script {
                echo "✅ Backend deployment to K3s SUCCESSFUL!"
                echo "Backend API is available at: https://api.space2study.pp.ua (via nginx-ingress)"
            }
        }
        
        failure {
            script {
                echo "❌ Backend deployment FAILED!"
                sh '''
                    echo "Last 50 lines of backend pod logs:"
                    kubectl logs -n ${NAMESPACE} -l app=backend --tail=50 || echo "No logs available"
                '''
            }
        }
    }
}
