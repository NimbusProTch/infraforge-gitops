# Troubleshooting Guide

Common issues and their solutions for InfraForge GitOps platform.

## Table of Contents

- [Infrastructure Issues](#infrastructure-issues)
- [EKS Cluster Issues](#eks-cluster-issues)
- [ArgoCD Issues](#argocd-issues)
- [Application Issues](#application-issues)
- [Networking Issues](#networking-issues)
- [Database Issues](#database-issues)
- [Performance Issues](#performance-issues)

---

## Infrastructure Issues

### OpenTofu: "bucket does not exist"

**Problem**: OpenTofu fails with S3 bucket not found error.

**Solution**:
```bash
./scripts/setup.sh  # Re-run setup script to create bucket
```

### OpenTofu: "state locked"

**Problem**: OpenTofu state is locked by another operation.

**Solution**:
```bash
# Check DynamoDB for lock
aws dynamodb scan --table-name infraforge-terraform-locks --region eu-west-1

# Force unlock (use with caution!)
cd terraform
tofu force-unlock <LOCK_ID>
```

### OpenTofu: "quota exceeded"

**Problem**: AWS service quota exceeded (e.g., VPCs, EIPs).

**Solution**:
```bash
# Check current limits
aws service-quotas list-service-quotas \
  --service-code vpc --region eu-west-1

# Request quota increase
aws service-quotas request-service-quota-increase \
  --service-code vpc \
  --quota-code <QUOTA_CODE> \
  --desired-value 10
```

---

## EKS Cluster Issues

### kubectl: "Unable to connect to server"

**Problem**: Cannot connect to EKS cluster.

**Solutions**:

1. **Update kubeconfig**:
```bash
aws eks update-kubeconfig --region eu-west-1 --name infraforge-eks
```

2. **Check AWS credentials**:
```bash
aws sts get-caller-identity
```

3. **Verify cluster exists**:
```bash
aws eks describe-cluster --name infraforge-eks --region eu-west-1
```

### Nodes: "NotReady" status

**Problem**: Nodes showing NotReady status.

**Diagnosis**:
```bash
kubectl describe node <node-name>
kubectl get pods -n kube-system  # Check system pods
```

**Solutions**:

1. **Check VPC CNI**:
```bash
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl logs -n kube-system -l k8s-app=aws-node
```

2. **Restart kubelet** (via Systems Manager):
```bash
# Get instance ID
kubectl get node <node-name> -o json | jq -r '.spec.providerID'

# Connect via SSM
aws ssm start-session --target <instance-id>

# Restart kubelet
sudo systemctl restart kubelet
```

### Pods: "ImagePullBackOff"

**Problem**: Cannot pull image from ECR.

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Solutions**:

1. **Verify image exists**:
```bash
aws ecr describe-images --repository-name <app-name> --region eu-west-1
```

2. **Check ECR permissions**:
```bash
# Node should have ECR read policy
aws iam get-role --role-name infraforge-eks-node-group-role
```

3. **Push image if missing**:
```bash
./scripts/push-images.sh
```

---

## ArgoCD Issues

### ArgoCD: "Unknown" health status

**Problem**: Application shows Unknown health status.

**Diagnosis**:
```bash
kubectl get application -n argocd <app-name> -o yaml
kubectl describe application -n argocd <app-name>
```

**Solutions**:

1. **Check if pods are running**:
```bash
kubectl get pods -n <namespace>
```

2. **Force sync**:
```bash
kubectl patch application <app-name> -n argocd \
  --type merge \
  --patch '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

3. **Check ArgoCD logs**:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### ArgoCD: "OutOfSync" status

**Problem**: Application stuck in OutOfSync state.

**Solutions**:

1. **Manual sync**:
```bash
# Via kubectl
kubectl patch application <app-name> -n argocd \
  --type merge --patch '{"spec":{"syncPolicy":null}}'

# Via UI
# ArgoCD UI → Application → Sync
```

2. **Check for manual changes**:
```bash
kubectl diff -f <resource-file>
```

3. **Reset to Git state**:
```bash
# Delete and recreate application
kubectl delete application <app-name> -n argocd
# ArgoCD will recreate from ApplicationSet
```

### ArgoCD: Can't access UI

**Problem**: Cannot access ArgoCD web interface.

**Solutions**:

1. **Port forward**:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access: https://localhost:8080
```

2. **Get admin password**:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

3. **Check ArgoCD pods**:
```bash
kubectl get pods -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

---

## Application Issues

### Pods: "CrashLoopBackOff"

**Problem**: Pod keeps crashing and restarting.

**Diagnosis**:
```bash
kubectl logs -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --previous  # Previous crash
kubectl describe pod -n <namespace> <pod-name>
```

**Common Causes**:

1. **Database connection failure**:
```bash
# Check database secret
kubectl get secret -n <namespace> db-credentials -o yaml

# Verify RDS endpoint
cd terraform && tofu output rds_mysql_endpoint
```

2. **Missing environment variables**:
```bash
kubectl get configmap -n <namespace> <app-name>-config -o yaml
```

3. **Resource limits**:
```bash
# Check resource usage
kubectl top pod -n <namespace> <pod-name>

# Increase limits in config/apps.yaml
resources:
  cpu: "1000m"
  memory: "1Gi"
```

### Pods: "Pending" state

**Problem**: Pod stuck in Pending state, not scheduling.

**Diagnosis**:
```bash
kubectl describe pod -n <namespace> <pod-name>
```

**Solutions**:

1. **Insufficient resources**:
```bash
# Check node resources
kubectl top nodes

# Cluster Autoscaler will add nodes automatically
# Check autoscaler logs:
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler
```

2. **PVC not bound**:
```bash
kubectl get pvc -n <namespace>
kubectl describe pvc -n <namespace> <pvc-name>

# Check EBS CSI driver
kubectl get pods -n kube-system -l app=ebs-csi-controller
```

### Application: Slow response times

**Problem**: Application responds slowly or times out.

**Diagnosis**:
```bash
# Check pod metrics
kubectl top pod -n <namespace>

# Check HPA status
kubectl get hpa -n <namespace>

# Check pod logs for errors
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app-name>
```

**Solutions**:

1. **Scale horizontally**:
```yaml
# In config/apps.yaml
autoscaling:
  enabled: true
  minReplicas: 3  # Increase minimum
  maxReplicas: 15  # Increase maximum
```

2. **Increase resources**:
```yaml
# In config/apps.yaml
resources:
  cpu: "1000m"  # Increase CPU
  memory: "2Gi"  # Increase memory
```

3. **Check database**:
```bash
# RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=infraforge-eks-mysql \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## Networking Issues

### DNS: Not resolving

**Problem**: Application domain not resolving.

**Diagnosis**:
```bash
nslookup smk.ticarethanem.net
dig smk.ticarethanem.net
```

**Solutions**:

1. **Check ExternalDNS**:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns

# Check if records were created
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --query "ResourceRecordSets[?Name=='smk.ticarethanem.net.']"
```

2. **Check Ingress annotation**:
```bash
kubectl get ingress -n <namespace> -o yaml | grep external-dns
# Should have: external-dns.alpha.kubernetes.io/hostname
```

3. **Force ExternalDNS sync**:
```bash
kubectl delete pod -n kube-system -l app.kubernetes.io/name=external-dns
```

### ALB: 503 errors

**Problem**: ALB returning 503 Service Unavailable.

**Diagnosis**:
```bash
# Check target group health
ALB_ARN=$(kubectl get ingress -n <namespace> <ingress-name> \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>
```

**Solutions**:

1. **Check pod health**:
```bash
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod-name>
```

2. **Verify health check endpoints**:
```bash
kubectl exec -n <namespace> <pod-name> -- curl localhost:8080/health
```

3. **Check service endpoints**:
```bash
kubectl get endpoints -n <namespace>
```

### Ingress: Not creating ALB

**Problem**: Ingress resource not creating ALB.

**Diagnosis**:
```bash
kubectl describe ingress -n <namespace> <ingress-name>
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Solutions**:

1. **Check AWS LB Controller**:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

2. **Verify IAM permissions**:
```bash
# Check IRSA role
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml
```

3. **Check Ingress class**:
```bash
kubectl get ingressclass
# Should show: alb
```

---

## Database Issues

### RDS: Connection refused

**Problem**: Application cannot connect to RDS.

**Diagnosis**:
```bash
# Get database secret
kubectl get secret -n <namespace> db-credentials -o jsonpath='{.data.DATABASE_URL}' | base64 -d

# Get RDS endpoint
cd terraform && tofu output rds_mysql_endpoint
```

**Solutions**:

1. **Check security group**:
```bash
# RDS security group should allow EKS nodes
aws ec2 describe-security-groups \
  --group-ids <RDS_SG_ID>
```

2. **Test connectivity from pod**:
```bash
kubectl run -n <namespace> mysql-client --rm -it --image=mysql:8.0 -- bash
# Inside pod:
mysql -h <RDS_ENDPOINT> -u dbadmin -p
```

3. **Check RDS status**:
```bash
aws rds describe-db-instances \
  --db-instance-identifier infraforge-eks-mysql
```

### RDS: High CPU usage

**Problem**: RDS CPU at 100%.

**Solutions**:

1. **Upgrade instance class**:
```yaml
# In config/apps.yaml
database:
  mysql:
    instance_class: "db.t3.small"  # Upgrade from t3.micro
```

2. **Check slow queries**:
```bash
# Enable slow query log
aws rds modify-db-instance \
  --db-instance-identifier infraforge-eks-mysql \
  --cloudwatch-logs-export-configuration '{"EnableLogTypes":["slowquery"]}'
```

3. **Add read replicas** (requires code change):
```bash
# Create read replica via Terraform
# Update app to use read replica for SELECT queries
```

---

## Performance Issues

### High latency

**Problem**: Application experiencing high latency.

**Checklist**:

1. **Check pod resources**:
```bash
kubectl top pod -n <namespace>
```

2. **Check node resources**:
```bash
kubectl top nodes
```

3. **Check HPA**:
```bash
kubectl get hpa -n <namespace>
kubectl describe hpa -n <namespace> <hpa-name>
```

4. **Check database performance**:
```bash
# RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=infraforge-eks-mysql \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

### Node scaling slow

**Problem**: Cluster Autoscaler takes too long to add nodes.

**Diagnosis**:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler
```

**Solutions**:

1. **Increase max nodes**:
```hcl
# In terraform/terraform.tfvars
node_max_size = 10  # Increase from 6
```

2. **Use Karpenter** (advanced):
```bash
# Replace Cluster Autoscaler with Karpenter for faster scaling
# See: https://karpenter.sh/
```

---

## Debugging Commands

### Comprehensive Health Check

```bash
#!/bin/bash
echo "=== Cluster Info ==="
kubectl cluster-info

echo "\n=== Nodes ==="
kubectl get nodes

echo "\n=== Namespaces ==="
kubectl get ns

echo "\n=== ArgoCD Apps ==="
kubectl get applications -n argocd

echo "\n=== Pods (all namespaces) ==="
kubectl get pods -A | grep -v Running

echo "\n=== Ingresses ==="
kubectl get ingress -A

echo "\n=== PVCs ==="
kubectl get pvc -A

echo "\n=== Top Nodes ==="
kubectl top nodes

echo "\n=== Top Pods ==="
kubectl top pods -A
```

### Logs Collection

```bash
# Collect logs from specific app
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app-name> \
  --tail=1000 > app-logs.txt

# Collect ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller \
  --tail=1000 > argocd-controller-logs.txt

# Collect system logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller \
  --tail=1000 > lb-controller-logs.txt
```

### Resource Usage Report

```bash
kubectl get pods -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
CPU_REQ:.spec.containers[*].resources.requests.cpu,\
MEM_REQ:.spec.containers[*].resources.requests.memory,\
CPU_LIM:.spec.containers[*].resources.limits.cpu,\
MEM_LIM:.spec.containers[*].resources.limits.memory
```

---

## Getting Further Help

If you're still stuck after trying these solutions:

1. **Check CloudWatch Logs**:
   - EKS Control Plane logs
   - RDS logs
   - VPC Flow logs

2. **Review AWS Service Health**:
   ```bash
   aws health describe-events --region eu-west-1
   ```

3. **Contact AWS Support**:
   - For infrastructure issues
   - For quota increases

4. **Community Resources**:
   - Kubernetes Slack
   - ArgoCD GitHub issues
   - AWS forums

---

For architecture details, see [architecture.md](architecture.md)
