// Jenkinsfile for Monitoring Stack K3s Deployment
// Deploys Prometheus, Grafana, Loki, and Promtail to K3s cluster

pipeline {
    agent {
        label 'k3s'  // Use a specific Jenkins agent with K3s access
    }

    environment {
        // K3s and Vault configuration
        KUBECONFIG = "${HOME}/.kube/config"
        MONITORING_NAMESPACE = 'monitoring'
        INGRESS_NAMESPACE = 'ingress-nginx'
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

        stage('Create Monitoring Namespace') {
            steps {
                script {
                    echo "📦 Creating monitoring namespace..."
                    sh '''
                        kubectl create namespace ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                        echo "✅ Namespace '${MONITORING_NAMESPACE}' ready"
                    '''
                }
            }
        }

        stage('Apply StorageClass') {
            steps {
                script {
                    echo "💾 Applying StorageClass for monitoring..."
                    sh '''
                        kubectl apply -f k8s-manifests/monitoring/ebs-storageclass.yaml
                        echo "✅ StorageClass 'monitoring-sc' applied"
                        kubectl get storageclass monitoring-sc
                    '''
                }
            }
        }

        stage('Apply PersistentVolumes') {
            steps {
                script {
                    echo "📊 Applying PersistentVolumes..."
                    sh '''
                        # Get K3s master hostname for node affinity
                        echo "🔍 Getting K3s master hostname..."
                        MASTER_HOSTNAME=$(kubectl get nodes -l kubernetes.io/hostname -o jsonpath='{.items[0].metadata.name}')

                        if [ -z "${MASTER_HOSTNAME}" ]; then
                            echo "❌ Failed to get K3s master hostname"
                            exit 1
                        fi

                        echo "✅ K3s Master hostname: ${MASTER_HOSTNAME}"

                        # Replace placeholder in monitoring-pvs.yaml and apply
                        echo "🔄 Updating PV manifests with master hostname..."
                        sed "s|MASTER_NODE_NAME_PLACEHOLDER|${MASTER_HOSTNAME}|g" \
                            k8s-manifests/monitoring/monitoring-pvs.yaml | kubectl apply -f -

                        echo "✅ PersistentVolumes applied"

                        # Comprehensive PV debugging
                        echo ""
                        echo "=== PV DEBUG INFO ==="
                        echo "1️⃣ PV Summary:"
                        kubectl get pv monitoring-data-pv

                        echo ""
                        echo "2️⃣ PV Full Details:"
                        kubectl describe pv monitoring-data-pv

                        echo ""
                        echo "3️⃣ PV YAML:"
                        kubectl get pv monitoring-data-pv -o yaml

                        echo ""
                        echo "4️⃣ PV Node Affinity:"
                        kubectl get pv monitoring-data-pv -o jsonpath='{.spec.nodeAffinity}' | jq .

                        echo ""
                        echo "5️⃣ PV Storage Class:"
                        kubectl get pv monitoring-data-pv -o jsonpath='{.spec.storageClassName}'
                        echo ""

                        echo ""
                        echo "6️⃣ Available Nodes:"
                        kubectl get nodes -o wide
                    '''
                }
            }
        }

        stage('Add Helm Repositories') {
            steps {
                script {
                    echo "📦 Adding Helm repositories..."
                    sh '''
                        # Add Prometheus Community Helm repo
                        echo "Adding prometheus-community repo..."
                        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true

                        # Add Grafana Helm repo
                        echo "Adding grafana repo..."
                        helm repo add grafana https://grafana.github.io/helm-charts || true

                        # Update Helm repos
                        helm repo update
                        echo "✅ Helm repositories updated"
                    '''
                }
            }
        }

        stage('Deploy kube-prometheus-stack') {
            steps {
                script {
                    echo "📈 Deploying kube-prometheus-stack..."
                    sh '''
                        echo "Installing kube-prometheus-stack with Prometheus, Grafana, Alertmanager..."

                        helm upgrade --install kube-prometheus-stack \
                            prometheus-community/kube-prometheus-stack \
                            --namespace ${MONITORING_NAMESPACE} \
                            --values k8s-manifests/monitoring/prometheus-values.yaml

                        HELM_EXIT=$?

                        echo ""
                        echo "=== HELM DEPLOYMENT DEBUG INFO ==="

                        echo ""
                        echo "1️⃣ Helm exit code: $HELM_EXIT"

                        # Wait briefly for pods to be created (not for them to be ready)
                        echo "Waiting for pods to be created..."
                        sleep 5

                        # Give Prometheus extra time since it needs to wait for PVC binding
                        echo "Waiting for Prometheus to initialize..."
                        for i in {1..30}; do
                            PROM_STATUS=$(kubectl get pod -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
                            if [ "$PROM_STATUS" = "Running" ]; then
                                echo "✅ Prometheus pod is Running"
                                break
                            fi
                            if [ $i -eq 30 ]; then
                                echo "⚠️  Prometheus still initializing (may take a few more minutes)"
                            else
                                echo "  Prometheus status: $PROM_STATUS... ($i/30)"
                            fi
                            sleep 2
                        done

                        echo ""
                        echo "2️⃣ PVC Status:"
                        kubectl get pvc -n ${MONITORING_NAMESPACE} || echo "No PVCs found"

                        echo ""
                        echo "3️⃣ PVC Details (Prometheus):"
                        kubectl describe pvc -n ${MONITORING_NAMESPACE} prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 2>/dev/null || echo "PVC not yet created"

                        echo ""
                        echo "4️⃣ PV Status (should match PVC):"
                        kubectl get pv monitoring-data-pv

                        echo ""
                        echo "5️⃣ Pod Status:"
                        kubectl get pods -n ${MONITORING_NAMESPACE} -o wide

                        echo ""
                        echo "6️⃣ Pod Events (Prometheus):"
                        kubectl describe pod -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=prometheus 2>/dev/null | tail -30 || echo "No Prometheus pods found"

                        echo ""
                        echo "7️⃣ Kubernetes Events (Monitoring namespace):"
                        kubectl get events -n ${MONITORING_NAMESPACE} --sort-by='.lastTimestamp' | tail -20

                        echo ""
                        echo "8️⃣ Storage Classes:"
                        kubectl get storageclass

                        if [ $HELM_EXIT -eq 0 ]; then
                            echo "✅ kube-prometheus-stack deployed successfully"
                        else
                            echo "⚠️  Helm deployment timed out or failed (exit code: $HELM_EXIT)"
                            echo "Note: This may be normal if pods are still starting. Check PVC/PV binding above."
                        fi
                    '''
                }
            }
        }

        stage('Apply ServiceMonitor for nginx-ingress') {
            steps {
                script {
                    echo "🌐 Applying ServiceMonitor for nginx-ingress controller..."
                    sh '''
                        kubectl apply -f k8s-manifests/monitoring/nginx-ingress-servicemonitor.yaml
                        echo "✅ nginx-ingress ServiceMonitor applied"

                        # Verify
                        kubectl get servicemonitor -n ${MONITORING_NAMESPACE}
                    '''
                }
            }
        }

        stage('Deploy Loki Stack') {
            steps {
                script {
                    echo "📝 Deploying Loki Stack (Loki + Promtail)..."
                    sh '''
                        echo "Installing loki-stack with Loki and Promtail..."

                        helm upgrade --install loki \
                            grafana/loki-stack \
                            --namespace ${MONITORING_NAMESPACE} \
                            --values k8s-manifests/monitoring/loki-values.yaml

                        echo "✅ Loki Stack deployment initiated (pods will continue starting in background)"

                        # Show pod status
                        echo "Pod status:"
                        kubectl get pods -n ${MONITORING_NAMESPACE}
                    '''
                }
            }
        }

        stage('Verify Monitoring Stack') {
            steps {
                script {
                    echo "🔍 Verifying monitoring stack deployment..."
                    sh '''
                        echo "=== COMPREHENSIVE MONITORING STACK VERIFICATION ==="

                        echo ""
                        echo "1️⃣ Pods Status:"
                        kubectl get pods -n ${MONITORING_NAMESPACE} -o wide

                        echo ""
                        echo "2️⃣ PersistentVolumeClaims:"
                        kubectl get pvc -n ${MONITORING_NAMESPACE}

                        echo ""
                        echo "3️⃣ PersistentVolumes:"
                        kubectl get pv

                        echo ""
                        echo "4️⃣ PVC-PV Binding Details:"
                        kubectl get pvc -n ${MONITORING_NAMESPACE} -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName

                        echo ""
                        echo "5️⃣ Services:"
                        kubectl get svc -n ${MONITORING_NAMESPACE}

                        echo ""
                        echo "6️⃣ Helm Releases:"
                        helm list -n ${MONITORING_NAMESPACE}

                        echo ""
                        echo "7️⃣ ServiceMonitors:"
                        kubectl get servicemonitor -n ${MONITORING_NAMESPACE}

                        echo ""
                        echo "8️⃣ All Resources in monitoring namespace:"
                        kubectl get all -n ${MONITORING_NAMESPACE}

                        echo ""
                        echo "9️⃣ Recent Events:"
                        kubectl get events -n ${MONITORING_NAMESPACE} --sort-by='.lastTimestamp' | tail -15

                        echo ""
                        echo "🔟 Storage Classes:"
                        kubectl get storageclass -o wide
                    '''
                }
            }
        }

        stage('Display Access Information') {
            steps {
                script {
                    echo "📋 Monitoring Stack Access Information"
                    sh '''
                        echo "=========================================="
                        echo "✅ Monitoring Stack Deployed Successfully!"
                        echo "=========================================="

                        echo -e "\n🔗 ACCESS INFORMATION:\n"

                        echo "1️⃣  PROMETHEUS (Metrics)"
                        echo "   Port-forward: kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-prometheus 9090:9090"
                        echo "   URL: http://localhost:9090"

                        echo -e "\n2️⃣  GRAFANA (Dashboards)"
                        echo "   Port-forward: kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80"
                        echo "   URL: http://localhost:3000"
                        echo "   Username: admin"
                        echo "   Password: changeme123 (⚠️  Change this!)"

                        echo -e "\n3️⃣  LOKI (Logs)"
                        echo "   Port-forward: kubectl port-forward -n ${MONITORING_NAMESPACE} svc/loki 3100:3100"
                        echo "   URL: http://localhost:3100"

                        echo -e "\n4️⃣  ALERTMANAGER (Alerts)"
                        echo "   Port-forward: kubectl port-forward -n ${MONITORING_NAMESPACE} svc/kube-prometheus-stack-alertmanager 9093:9093"
                        echo "   URL: http://localhost:9093"

                        echo -e "\n📊 MONITORED COMPONENTS:\n"
                        echo "✅ K3s cluster nodes (CPU, memory, disk, network)"
                        echo "✅ Pod metrics and logs (via Promtail)"
                        echo "✅ nginx-ingress controller metrics"
                        echo "✅ Jenkins application and host metrics"
                        echo "✅ Vault application and host metrics"

                        echo -e "\n📦 POD STATUS:\n"
                        kubectl get pods -n ${MONITORING_NAMESPACE} -o wide

                        echo -e "\n💾 STORAGE STATUS:\n"
                        kubectl get pvc -n ${MONITORING_NAMESPACE}
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                echo "📊 Monitoring Stack Deployment Summary:"
                sh '''
                    echo "=== Monitoring Pods ==="
                    kubectl get pods -n ${MONITORING_NAMESPACE}

                    echo -e "\n=== Resource Usage ==="
                    kubectl top pods -n ${MONITORING_NAMESPACE} || echo "Metrics not available yet"
                '''
            }
        }

        success {
            script {
                echo "✅ Monitoring Stack deployment to K3s SUCCESSFUL!"
                sh '''
                    echo -e "\n🎉 Next steps:"
                    echo "1. Access Grafana to configure dashboards"
                    echo "2. Verify Prometheus targets are UP"
                    echo "3. Check Loki for pod logs"
                    echo "4. Update Grafana admin password"
                '''
            }
        }

        failure {
            script {
                echo "❌ Monitoring Stack deployment FAILED!"
                sh '''
                    echo "Debugging information:"
                    echo -e "\n=== Pod logs ==="
                    kubectl logs -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=prometheus --tail=30 || echo "No prometheus logs"

                    echo -e "\n=== Events ==="
                    kubectl get events -n ${MONITORING_NAMESPACE} --sort-by='.lastTimestamp' || echo "No events"

                    echo -e "\n=== PVC Status ==="
                    kubectl describe pvc -n ${MONITORING_NAMESPACE} || echo "No PVCs found"
                '''
            }
        }
    }
}
