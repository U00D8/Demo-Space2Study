# Architecture Diagrams

This document contains detailed ASCII art diagrams of the Demo-Space2Study infrastructure architecture.

---

## 1. AWS Infrastructure Topology

Complete overview of the production environment showing all components, availability zones, and data flow.

```
                          Internet Users
                   HTTPS: space2study.pp.ua
                              |
                 ┌────────────▼────────────┐
                 │  Cloudflare CDN/DNS     │
                 │  • DDoS Protection      │
                 │  • Cache, TLS           │
                 │  • Rate Limiting        │
                 └────────────┬────────────┘
                              |
        ┌────────────────▼────────────────────┐
        │   AWS Region: eu-north-1            │
        │   ┌──────────────────────────────┐  │
        │   │  Internet Gateway (IGW)      │  │
        │   └──────────────┬───────────────┘  │
        │                  │                  │
        │   ┌──────────────▼────────────────┐ │
        │   │ Application Load Balancer     │ │
        │   │ • 443 (HTTPS)                 │ │
        │   │ • 80 (HTTP) → HTTPS           │ │
        │   │ • TLS Termination             │ │
        │   └──────────────┬────────────────┘ │
        └──────────────────┼──────────────────┘  
    ┌──────────────────────┼─────────────────────┐ 
    │                      │                     │ 
    │ ┌────────────────────▼───────────────────┐ │ 
    │ │ AWS VPC (10.0.0.0/16)                  │ │ 
    │ │                                        │ │ 
    │ │  AZ-A (eu-north-1a)    AZ-B (eu-n)     │ │ 
    │ │  ┌──────────────────┐                  │ │ 
    │ │  │ K3s Master       │  ┌────────────┐  │ │ 
    │ │  │ t3.medium        │  │ K3s Worker │  │ │ 
    │ │  │ • etcd           │  │ t3.small   │  │ │ 
    │ │  │ • 6443 API       │  │ • Kubelet  │  │ │ 
    │ │  │ • EBS (Metrics)  │  └────────────┘  │ │ 
    │ │  └──────────────────┘  ┌────────────┐  │ │ 
    │ │  ┌──────────────────┐  │ K3s Worker │  │ │ 
    │ │  │ Jenkins          │  │ t3.small   │  │ │ 
    │ │  │ t3.medium        │  │ • Kubelet  │  │ │ 
    │ │  │ • 8080 UI        │  └────────────┘  │ │ 
    │ │  │ • Docker         │  ┌────────────┐  │ │ 
    │ │  │ • Groovy         │  │ App Pods   │  │ │ 
    │ │  └──────────────────┘  │ • Frontend │  │ │ 
    │ │  ┌──────────────────┐  │ • Backend  │  │ │ 
    │ │  │ Vault            │  │ • Monitor  │  │ │ 
    │ │  │ t3.small         │  └────────────┘  │ │ 
    │ │  │ • 8200 API       │                  │ │ 
    │ │  │ • KMS Unseal     │                  │ │ 
    │ │  └──────────────────┘  NAT Gateway     │ │ 
    │ │                                        │ │ 
    │ │  Private Subnets (Prod Only):          │ │ 
    │ │  10.0.10.0/24 (A) 10.0.11.0/24 (B)     │ │ 
    │ │  Route: 0.0.0.0/0 → NAT                │ │ 
    │ │                                        │ │ 
    │ └────────────────────┬───────────────────┘ │ 
    │                      │                     │ 
    └──────────────────────┼─────────────────────┘ 
                           │                        
    ┌──────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  MongoDB Atlas (Production)         │
│  Region: EU North 1                 │
│  • Managed MongoDB                  │
│  • IP Whitelist: K3s NAT Gateway    │
│  • Encrypted at Rest + Transit      │
│  • Automatic Backups                │
└─────────────────────────────────────┘
```

**Key Architecture Features:**
- **Multi-AZ Deployment:** ALB and K3s cluster span 2 availability zones for high availability
- **Network Isolation:** Public/private subnets with security groups enforcing least-privilege access
- **TLS End-to-End:** Cloudflare → ALB → Ingress → Pod communication encrypted
- **Service Discovery:** Private Route53 zone for internal DNS resolution
- **Persistent Storage:** EBS volumes for Prometheus, Grafana, Loki data with automated snapshots
- **Container Registry:** AWS ECR with vulnerability scanning on image push

---

## 2. Security Architecture & Security Group Rules

Detailed security architecture showing network boundaries, security groups, and allowed traffic flows.

```
INGRESS FROM INTERNET (via Cloudflare)
│ HTTP/HTTPS only (80, 443)
▼
┌─────────────────────────────────────────────────────────────┐
│  ALB Security Group (alb-sg)                                │
│    Inbound:                                                 │
│    • HTTP (80) from 0.0.0.0/0                               │
│    • HTTPS (443) from 0.0.0.0/0                             │
│    Outbound:                                                │
│    • All traffic to VPC CIDR (10.0.0.0/16)                  │
└─────────────────────────────┬───────────────────────────────┘
                              │ Port 30080/30443
        ┌─────────────────────▼──────────────────────┐
        │  K3s Worker Security Group (k3s-worker-sg) │
        │    Inbound:                                │
        │    • 30080 (HTTP) from ALB-SG              │
        │    • 30443 (HTTPS) from ALB-SG             │
        │    • 10250 (Kubelet) from K3s-MASTER-SG    │
        │    • 8472 (Flannel VXLAN) between workers  │
        │    • 22 (SSH) from ADMIN-CIDR              │
        │    • 9100 (node_exporter) from master      │
        │    Outbound: All traffic                   │
        └────────────────────────────────────────────┘

        ┌─────────────────────────────────────────────┐
        │  K3s Master Security Group (k3s-master-sg)  │
        │    Inbound:                                 │
        │    • 6443 (K3s API) from workers & Jenkins  │
        │    • 2379-2380 (etcd) from workers          │
        │    • 8472 (Flannel VXLAN) from workers      │
        │    • 10250 (Kubelet) from workers           │
        │    • 22 (SSH) from ADMIN-CIDR               │
        │    • 9100 (node_exporter) from pods         │
        │    Outbound: All traffic                    │
        └─────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────┐
        │  Jenkins Security Group (jenkins-sg)         │
        │    Inbound:                                  │
        │    • 8080 (UI) from ALB-SG & ADMIN-CIDR      │
        │    • 50000 (Agents) from agents              │
        │    • 22 (SSH) from ADMIN-CIDR                │
        │    • 9100 (node_exporter) from K3s           │
        │    Outbound: All traffic                     │
        └──────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────┐
        │  Vault Security Group (vault-sg)             │
        │    Inbound:                                  │
        │    • 8200 (API) from K3s, Jenkins, Admin     │
        │    • 22 (SSH) from ADMIN-CIDR                │
        │    • 9100 (node_exporter) from K3s           │
        │    Outbound: All traffic (AWS KMS, S3)       │
        └──────────────────────────────────────────────┘

SECURITY PRINCIPLES APPLIED:
✅ No security group allows all traffic (0.0.0.0/0 except ALB)
✅ Specific ports only (no port ranges)
✅ SSH restricted to admin CIDR (not open to internet)
✅ Inter-service communication via security group references
✅ Database access from K3s pods only
✅ All traffic to MongoDB is encrypted (TLS 1.2+)
```

**Security Zones:**
- **Internet Zone** - Cloudflare (untrusted, public)
- **Edge Zone** - ALB (TLS termination, basic filtering)
- **Compute Zone** - K3s cluster (orchestrated, containerized)
- **Management Zone** - Jenkins, Vault (privileged access)
- **Data Zone** - MongoDB Atlas (encrypted, restricted access)

---

## 3. Request Flow & Data Path Diagram

Complete request lifecycle from user to database with all security checkpoints.

```
STEP 1: USER REQUEST (HTTPS)
User Browser → GET https://space2study.pp.ua/api/courses
└─ TLS Handshake (Cloudflare Origin Certificate)

STEP 2: CLOUDFLARE CDN/PROXY
├─ DNS Lookup (space2study.pp.ua)
├─ DDoS Check (rate limit, geo-blocking)
├─ Cache Check (not found, forward to origin)
└─ Forward HTTPS to ALB

STEP 3: AWS APPLICATION LOAD BALANCER (ALB)
├─ Receive HTTPS on 443
├─ TLS Termination (Cloudflare Origin Certificate)
├─ Target Group Selection:
│  ├─ api.space2study.pp.ua → K3s Ingress (30080)
│  ├─ space2study.pp.ua → K3s Ingress (30080)
│  └─ jenkins.space2study.pp.ua → Jenkins (8080)
├─ Health Check: GET / (30s interval)
├─ Load Balance: Round-robin to healthy workers
└─ Forward HTTP to K3s Worker (via NodePort)

STEP 4: K3S WORKER NODE
├─ Receive HTTP on 30080 (NodePort from ALB)
├─ IPtables: Route to Ingress Controller Pod
└─ Forward to Ingress Controller

STEP 5: KUBERNETES INGRESS CONTROLLER (Nginx)
├─ Host Matching:
│  └─ api.space2study.pp.ua/api/* → backend:5000
├─ Service Discovery:
│  └─ backend → Pod IPs (10.42.x.1, 10.42.x.2)
├─ Load Balance: Round-robin to backend replicas
└─ Forward HTTP to Backend Pod

STEP 6: BACKEND POD (Node.js Application)
├─ Security Context:
│  ├─ RunAsUser: 1000 (non-root)
│  ├─ ReadOnlyRootFilesystem: true
│  └─ Capabilities: drop [ALL]
├─ Environment Variables (from Kubernetes Secrets):
│  ├─ MONGODB_URL=mongodb+srv://...
│  ├─ DATABASE_PASSWORD=<from Vault>
│  └─ JWT_SECRET=<from Vault>
├─ Health Checks: Liveness & Readiness probes
├─ Request Processing:
│  ├─ Parse JWT from Authorization header
│  ├─ Validate token against JWT_SECRET
│  ├─ Extract user ID from token claims
│  └─ Prepare MongoDB query
└─ Forward MongoDB connection request

STEP 7: SERVICE DISCOVERY (Kubernetes DNS)
├─ Query: mongodb-srv.default.svc.cluster.local
├─ Resolution: Returns MongoDB Atlas connection string
└─ TLS 1.2+ connection initiated

STEP 8: MONGODB ATLAS (Database)
├─ Connection:
│  ├─ TLS 1.2+ (encrypted in transit)
│  ├─ IP Whitelist: K3s cluster NAT Gateway IP only
│  ├─ Authentication: Username/password from Vault
│  └─ Database: space2study
├─ Query Execution:
│  ├─ Collection: courses
│  ├─ Filter: { userId: <from JWT> }
│  ├─ Encryption: At Rest (KMS)
│  └─ Audit: Connection & query logged
└─ Response: Array of documents (JSON)

STEP 9: RESPONSE PATH (Backend → User)
├─ Backend Pod:
│  ├─ Transform documents to JSON
│  ├─ Add response headers
│  ├─ HTTP 200 OK
│  └─ Send to Ingress
├─ Ingress Controller → ALB (NodePort)
├─ ALB:
│  ├─ Receive HTTP from NodePort
│  ├─ Encrypt HTTPS (Cloudflare Certificate)
│  └─ Add security headers (HSTS)
├─ Cloudflare:
│  ├─ Receive HTTPS response
│  ├─ Cache decision (not cached for /api/*)
│  └─ Forward HTTPS to browser
└─ User Browser:
   ├─ Receive HTTPS (TLS decrypted)
   ├─ Parse JSON response
   └─ Render UI with course data

SECURITY CHECKPOINTS AT EACH STEP:
✅ Step 1: HTTPS enforced (no plain HTTP)
✅ Step 2: Cloudflare DDoS, rate limiting
✅ Step 3: ALB health checks, TLS termination
✅ Step 4: Security group allows only 30080 from ALB
✅ Step 5: Ingress validates Host header
✅ Step 6: Pod runs non-root, read-only filesystem, JWT validated
✅ Step 7: Service account restricts pod access (RBAC)
✅ Step 8: TLS to MongoDB, IP whitelist, Vault-managed credentials
✅ Step 9: Response encrypted end-to-end, HSTS headers

PERFORMANCE:
⚡ Cloudflare: Caches static content, absorbs DDoS
⚡ ALB: Connection pooling, keep-alive
⚡ K3s: Pod affinity for worker spreading
⚡ MongoDB: Connection pooling, indexes on userId
⚡ Overall: ~150-300ms end-to-end latency target
```

---

## Architecture Principles

### High Availability
- Multi-AZ deployment ensures service continues if one AZ fails
- Load balancing distributes traffic across multiple instances
- Health checks automatically remove failing instances
- Pod replicas (2+) ensure service availability
- Automatic failover with health check recovery

### Security in Depth
- **Perimeter:** Cloudflare DDoS, rate limiting, geo-blocking
- **Network:** Security groups, TLS encryption, private subnets
- **Application:** RBAC, security contexts, JWT validation
- **Data:** Encryption at rest (KMS), encryption in transit (TLS 1.2+)
- **Access:** IAM roles, service accounts, least-privilege policies

### Scalability
- Horizontal scaling: Add K3s worker nodes as needed
- Auto-scaling ready: Cluster Autoscaler integration (future)
- Load distribution: ALB, K3s Ingress, MongoDB connection pooling
- Stateless application design enables easy horizontal scaling

### Observability
- **Metrics:** Prometheus collects 100+ metrics from all components
- **Logging:** Loki centralizes logs from all pods and system services
- **Tracing:** Jaeger ready for distributed tracing (future enhancement)
- **Alerting:** AlertManager triggers on thresholds (CPU, memory, errors)

### Cost Optimization
- K3s lightweight distribution (~$73/month savings vs EKS)
- MongoDB Atlas free tier (M0) for development
- Automatic snapshot cleanup with Data Lifecycle Manager
- Dev/Prod split for cost control
- No managed services overhead (self-hosted where beneficial)

---

## Compliance & Standards

- **Data Protection:** Encryption at rest (KMS) and in transit (TLS 1.2+)
- **Authentication:** JWT tokens, IAM roles, service accounts
- **Authorization:** RBAC, security contexts, least-privilege policies
- **Audit Trail:** CloudTrail, VPC Flow Logs, application metrics
- **Compliance Ready:** GDPR, SOC2, ISO 27001 (with additional controls)
