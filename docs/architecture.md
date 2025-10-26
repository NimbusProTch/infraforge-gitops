# InfraForge Architecture

Detailed architecture overview of the InfraForge GitOps platform.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    config/apps.yaml                          │
│              (Single Source of Truth)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  OpenTofu/Terraform                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Infrastructure Layer                                    │ │
│  │  ├─ VPC (3 AZs, public/private subnets)               │ │
│  │  ├─ EKS Cluster (v1.28)                               │ │
│  │  ├─ RDS MySQL + PostgreSQL                            │ │
│  │  ├─ Route53 + ACM Certificate                         │ │
│  │  └─ Security Groups                                    │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ EKS Addons                                             │ │
│  │  ├─ EBS CSI Driver                                     │ │
│  │  ├─ AWS Load Balancer Controller                      │ │
│  │  ├─ ExternalDNS                                        │ │
│  │  ├─ Cluster Autoscaler                                │ │
│  │  └─ Metrics Server                                     │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Per-App Resources (if enabled=true)                    │ │
│  │  ├─ ECR Repository                                     │ │
│  │  ├─ Kubernetes Namespace                              │ │
│  │  ├─ Secrets (DB credentials)                          │ │
│  │  └─ ConfigMap                                          │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ArgoCD Installation                                     │ │
│  │  ├─ ArgoCD Helm Chart                                  │ │
│  │  ├─ ApplicationSet (reads config/apps.yaml)           │ │
│  │  └─ Root Application                                   │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                     ArgoCD                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ApplicationSet Controller                               │ │
│  │  ├─ Reads config/apps.yaml from Git                   │ │
│  │  ├─ Generates Application per enabled app             │ │
│  │  └─ Auto-syncs every 3 minutes                        │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Application Controller                                  │ │
│  │  ├─ Deploys Helm charts                               │ │
│  │  ├─ Creates pods, services, ingress                   │ │
│  │  ├─ Monitors health                                    │ │
│  │  └─ Auto-heals drift                                   │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                 Application Pods                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ App: smk (enabled)                                      │ │
│  │  ├─ 2 pods (HPA: 2-10)                                 │ │
│  │  ├─ ClusterIP Service                                  │ │
│  │  ├─ Ingress → ALB → smk.ticarethanem.net             │ │
│  │  └─ Connected to RDS MySQL                            │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ App: sonsuzenerji (enabled)                            │ │
│  │  ├─ 2 pods (HPA: 2-10)                                 │ │
│  │  ├─ ClusterIP Service                                  │ │
│  │  ├─ Ingress → ALB → sonsuz.ticarethanem.net          │ │
│  │  └─ Connected to RDS PostgreSQL                       │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Network Architecture

### VPC Design

```
VPC: 10.0.0.0/16
├─ AZ 1 (eu-west-1a)
│  ├─ Public Subnet: 10.0.101.0/24
│  │  ├─ NAT Gateway
│  │  └─ Internet Gateway
│  └─ Private Subnet: 10.0.1.0/24
│     ├─ EKS Worker Nodes
│     └─ RDS Instances
│
├─ AZ 2 (eu-west-1b)
│  ├─ Public Subnet: 10.0.102.0/24
│  │  └─ NAT Gateway
│  └─ Private Subnet: 10.0.2.0/24
│     ├─ EKS Worker Nodes
│     └─ RDS Instances
│
└─ AZ 3 (eu-west-1c)
   ├─ Public Subnet: 10.0.103.0/24
   │  └─ NAT Gateway
   └─ Private Subnet: 10.0.3.0/24
      ├─ EKS Worker Nodes
      └─ RDS Instances
```

### Traffic Flow

```
Internet
    ↓
Route53 DNS (ticarethanem.net)
    ↓
Application Load Balancer (ALB)
    ├─ Listener: 80 → Redirect to 443
    └─ Listener: 443 → ACM Certificate → Target Group
                                              ↓
                                    ClusterIP Service
                                              ↓
                                         Application Pods
                                              ↓
                                         RDS Database
```

## Component Details

### 1. Infrastructure Layer (Terraform)

**VPC Module**:
- Multi-AZ deployment (3 availability zones)
- Public subnets for NAT Gateways and ALB
- Private subnets for EKS nodes and RDS
- VPC Endpoints (S3, ECR) for cost optimization
- Internet Gateway for public subnet connectivity
- NAT Gateways (one per AZ) for private subnet internet access

**EKS Cluster**:
- Version: 1.28
- Control plane in private subnets
- Public + private API endpoint
- IRSA (IAM Roles for Service Accounts) enabled
- Managed node group with auto-scaling (2-6 nodes)
- t3.medium instances with 50GB GP3 volumes

**RDS Instances**:
- MySQL 8.0 (t3.micro, single-AZ for cost optimization)
- PostgreSQL 15 (t3.micro, single-AZ)
- Encrypted storage (AES-256)
- 7-day automated backups
- CloudWatch logs export enabled
- Security group restricting access to EKS nodes only

**Security**:
- ACM wildcard certificate (`*.ticarethanem.net`)
- Security groups for EKS, RDS, ALB, VPC endpoints
- Private subnets for all workloads
- Encrypted Terraform state in S3
- State locking with DynamoDB

### 2. EKS Addons

**EBS CSI Driver**:
- Manages EBS volumes for persistent storage
- IRSA role for AWS API access
- Required for PersistentVolumeClaims

**AWS Load Balancer Controller**:
- Creates ALB from Ingress resources
- Manages target groups
- Handles health checks
- Integrates with ACM for TLS

**ExternalDNS**:
- Watches Ingress resources
- Automatically creates Route53 records
- Updates DNS when ingress changes
- Syncs every 60 seconds

**Cluster Autoscaler**:
- Scales nodes based on pod demands
- Scale up when pods are pending
- Scale down when nodes are underutilized
- Respects PodDisruptionBudgets

**Metrics Server**:
- Collects resource metrics from kubelets
- Required for HPA (Horizontal Pod Autoscaler)
- Required for `kubectl top` command

### 3. GitOps Layer (ArgoCD)

**ArgoCD Components**:
- **Server**: Web UI + API (2 replicas)
- **Repo Server**: Git repository connection (2 replicas)
- **Application Controller**: Sync logic (2 replicas)
- **ApplicationSet Controller**: Dynamic app generation (2 replicas)
- **Redis**: Caching

**ApplicationSet**:
```yaml
Generator: Git File
  ↓
Reads: config/apps.yaml
  ↓
For each enabled app:
  ↓
Generates: Application manifest
  ↓
Points to: helm/infraforge-app chart
  ↓
Injects: App-specific values
  ↓
Deploys to: App namespace
```

**Sync Policy**:
- Automated sync every 3 minutes
- Self-heal on drift detection
- Prune resources when disabled
- Retry on failure (5 times with backoff)

### 4. Application Layer

**Helm Chart** (`helm/infraforge-app`):
- Generic chart for all applications
- Parameterized via ArgoCD values
- Supports:
  - Deployment with health checks
  - Service (ClusterIP)
  - Ingress (ALB)
  - HPA (2-10 pods)
  - ConfigMap and Secrets
  - ServiceAccount for RBAC

**Pod Specifications**:
- Security context: non-root user (1000)
- Read-only root filesystem
- Dropped capabilities
- Resource requests and limits
- Liveness and readiness probes
- Volume mounts for tmp and cache

### 5. Data Flow

**Deployment Flow**:
```
1. Developer updates config/apps.yaml
   ├─ Changes enabled: true/false
   └─ Changes replicas, resources, etc.

2. Git push to main branch

3. ArgoCD ApplicationSet detects change
   ├─ Generates/updates Application
   └─ Triggers sync

4. ArgoCD syncs Helm chart
   ├─ Renders templates with values
   ├─ Applies manifests to Kubernetes
   └─ Waits for health checks

5. Kubernetes creates resources
   ├─ Deployment → Pods
   ├─ Service → Endpoints
   └─ Ingress → ALB

6. AWS Load Balancer Controller
   ├─ Creates/updates ALB
   ├─ Configures listeners
   ├─ Attaches target groups
   └─ Configures health checks

7. ExternalDNS
   ├─ Reads Ingress annotation
   └─ Creates Route53 A record

8. Application is live!
   └─ https://app.ticarethanem.net
```

**Enable/Disable Flow**:
```
Disable App:
  config/apps.yaml: enabled: false
      ↓
  tofu apply
      ├─ Deletes namespace
      ├─ Deletes secrets
      └─ ArgoCD prunes Application
      ↓
  Pods deleted
  Ingress deleted
  ALB target group removed
  DNS record removed (TTL expiry)

Enable App:
  config/apps.yaml: enabled: true
      ↓
  tofu apply
      ├─ Creates namespace
      ├─ Creates secrets
      └─ ArgoCD creates Application
      ↓
  Pods created
  Ingress created
  ALB target group created
  DNS record created
```

## Scaling Architecture

### Horizontal Scaling (Pods)

```
HPA watches metrics
    ↓
CPU > 75% threshold
    ↓
HPA increases replicas
    ↓
New pods created
    ↓
Cluster Autoscaler checks
    ↓
Nodes at capacity?
    ├─ Yes → Add node
    └─ No → Schedule pods
```

### Vertical Scaling (Nodes)

```
Cluster Autoscaler monitors
    ↓
Pending pods detected
    ↓
Check max nodes (6)
    ├─ Not at max → Add node
    └─ At max → Pods stay pending
    ↓
Node idle for 10 minutes
    ↓
Safe to remove?
    ├─ Yes → Drain and delete
    └─ No → Keep running
```

## Security Architecture

### Network Security

```
Internet
    ↓
WAF (Optional - can be added)
    ↓
ALB (Public subnet)
    ↓
Security Group: Allow 80, 443 from 0.0.0.0/0
    ↓
EKS Nodes (Private subnet)
    ↓
Security Group: Allow from ALB, Self, Control Plane
    ↓
RDS (Private subnet)
    ↓
Security Group: Allow from EKS nodes only
```

### IAM Security

```
EKS Node IAM Role
    ├─ AmazonEKSWorkerNodePolicy
    ├─ AmazonEKS_CNI_Policy
    ├─ AmazonEC2ContainerRegistryReadOnly
    └─ AmazonSSMManagedInstanceCore

IRSA Roles (per addon):
    ├─ EBS CSI Driver → EBS API permissions
    ├─ LB Controller → ALB API permissions
    ├─ ExternalDNS → Route53 API permissions
    └─ Cluster Autoscaler → EC2/ASG API permissions
```

### Data Security

- Encryption at rest:
  - RDS: AES-256
  - EBS volumes: AES-256
  - S3 state: AES-256
- Encryption in transit:
  - TLS 1.2+ at ALB
  - TLS within cluster
- Secrets management:
  - Kubernetes Secrets (base64)
  - Can be integrated with AWS Secrets Manager

## Cost Optimization

1. **VPC Endpoints**: Avoid NAT charges for S3/ECR traffic
2. **Single NAT per AZ**: High availability vs cost balance
3. **t3.micro RDS**: Minimum viable instances
4. **Single-AZ RDS**: No multi-AZ replication costs
5. **Cluster Autoscaler**: Scale down idle nodes
6. **Spot Instances**: Can be added for cost savings
7. **Reserved Instances**: For long-term stable workloads

## Monitoring and Observability

### Current Metrics

- **Metrics Server**: CPU, Memory per pod/node
- **RDS CloudWatch**: Database metrics
- **ALB Metrics**: Request count, latency, errors
- **EKS Control Plane**: API server metrics

### Ready for Integration

- **Prometheus**: Scrape pod metrics
- **Grafana**: Visualize metrics
- **Loki**: Log aggregation
- **OpenTelemetry**: Distributed tracing

## Disaster Recovery

### Backup Strategy

- **RDS**: Automated daily backups (7 days retention)
- **Terraform State**: Versioned in S3
- **Application Data**: Depends on app-specific needs
- **Kubernetes Resources**: Managed by Git (GitOps)

### Recovery Procedures

1. **Infrastructure Failure**: `tofu apply` recreates from state
2. **Application Failure**: ArgoCD self-heals automatically
3. **Data Loss**: Restore from RDS backup
4. **Region Failure**: Manual failover to another region

---

For implementation details, see [SETUP_GUIDE.md](../SETUP_GUIDE.md)
