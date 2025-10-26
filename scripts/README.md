# InfraForge Utility Scripts

This directory contains utility scripts for managing the InfraForge GitOps infrastructure.

## Scripts

### 1. `cleanup-namespaces.sh`

Forcefully removes Kubernetes namespaces that are stuck in "Terminating" state by removing their finalizers.

**Usage:**
```bash
# Clean up specific namespaces
./cleanup-namespaces.sh monitoring logging argocd

# Auto-detect and clean all terminating namespaces
./cleanup-namespaces.sh
```

**Prerequisites:**
- `kubectl` configured and connected to cluster
- `jq` installed

**Example:**
```bash
$ ./cleanup-namespaces.sh monitoring
Cleaning up namespace: monitoring
Removing finalizers from namespace monitoring...
✓ Successfully cleaned up namespace: monitoring
```

### 2. `full-cleanup.sh`

Performs a complete cleanup of the entire InfraForge infrastructure. This script automates the full destroy process including:

1. Kubernetes namespace cleanup (stuck in Terminating state)
2. LoadBalancer deletion (created by K8s services)
3. Terraform/OpenTofu destroy
4. Manual AWS resource cleanup (Security Groups, VPC, etc.)
5. Verification of remaining resources

**Usage:**
```bash
# Full cleanup (interactive confirmation)
./full-cleanup.sh

# Skip Kubernetes cleanup
./full-cleanup.sh --skip-k8s

# Skip AWS manual cleanup (only run terraform destroy)
./full-cleanup.sh --skip-aws
```

**Prerequisites:**
- `kubectl` (if not using --skip-k8s)
- `jq` (if not using --skip-k8s)
- `aws-cli` configured
- `opentofu` (or `terraform`)

**What it does:**
- ✅ Cleans terminating namespaces
- ✅ Deletes LoadBalancer services
- ✅ Runs `tofu destroy`
- ✅ Manually deletes LoadBalancers in AWS
- ✅ Deletes Kubernetes-created Security Groups
- ✅ Attempts VPC deletion
- ✅ Verifies no cost-generating resources remain

**Example:**
```bash
$ ./full-cleanup.sh
============================================
  InfraForge Full Cleanup Script
============================================

⚠ This script will destroy ALL infrastructure!
Are you sure you want to continue? (yes/no): yes

[INFO] Checking prerequisites...
[SUCCESS] All prerequisites met

[INFO] Step 1: Cleaning up stuck Kubernetes namespaces...
[SUCCESS] Kubernetes namespace cleanup completed

[INFO] Step 2: Deleting Kubernetes LoadBalancers...
[INFO] Deleting LoadBalancer service: argocd/argocd-server
[SUCCESS] LoadBalancer cleanup completed

[INFO] Step 3: Running Terraform/OpenTofu destroy...
[INFO] Starting infrastructure destroy (this may take 10-20 minutes)...
[SUCCESS] Terraform destroy completed successfully

[INFO] Step 4: Manual AWS resource cleanup...
[INFO] Found VPC: vpc-019ca85c583e108ab
[INFO] Deleting LoadBalancer: arn:aws:elasticloadbalancing:...
[SUCCESS] AWS resource cleanup completed

[INFO] Step 5: Verifying cleanup...
[SUCCESS] No EKS clusters found
[SUCCESS] No EC2 instances found
[SUCCESS] No LoadBalancers found
[SUCCESS] No NAT Gateways found
[SUCCESS] No RDS instances found

[SUCCESS] ✓ All cost-generating resources have been cleaned up!

============================================
  Cleanup Complete!
============================================
```

## Common Issues

### Namespace Stuck in Terminating

**Problem:** Namespace won't delete and stays in "Terminating" state.

**Solution:** Use `cleanup-namespaces.sh` to force remove finalizers:
```bash
./cleanup-namespaces.sh <namespace-name>
```

**Manual Fix:**
```bash
kubectl get namespace <namespace> -o json | \
  jq '.spec.finalizers = null' > temp.json && \
  kubectl replace --raw "/api/v1/namespaces/<namespace>/finalize" -f temp.json
```

### VPC Won't Delete

**Problem:** VPC deletion fails with "DependencyViolation" error.

**Cause:** Usually LoadBalancers or Security Groups created by Kubernetes services.

**Solution:**
1. Delete LoadBalancer services first:
   ```bash
   kubectl get svc --all-namespaces | grep LoadBalancer
   kubectl delete svc <service-name> -n <namespace>
   ```

2. Wait 2-3 minutes for AWS to clean up

3. Delete remaining Security Groups:
   ```bash
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>" \
     --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text | \
     xargs -n1 aws ec2 delete-security-group --group-id
   ```

4. Delete VPC:
   ```bash
   aws ec2 delete-vpc --vpc-id <vpc-id>
   ```

### Terraform State Lock

**Problem:** Terraform operations fail with "state lock" error.

**Solution:**
```bash
cd terraform
tofu force-unlock -force <lock-id>
```

## Environment Variables

- `AWS_REGION`: AWS region (default: `eu-west-1`)
- `AWS_PROFILE`: AWS CLI profile to use

## Tips

1. **Before destroy:** Always check what resources will be destroyed:
   ```bash
   cd terraform
   tofu plan -destroy
   ```

2. **Cost verification:** After cleanup, verify no cost-generating resources remain:
   ```bash
   aws eks list-clusters --region eu-west-1
   aws ec2 describe-instances --region eu-west-1 --filters "Name=instance-state-name,Values=running"
   aws elbv2 describe-load-balancers --region eu-west-1
   aws rds describe-db-instances --region eu-west-1
   ```

3. **Partial cleanup:** If you want to keep EKS but clean up apps:
   ```bash
   kubectl delete namespace <app-namespace>
   ```

## Safety

⚠️ **WARNING:** These scripts are **destructive** and will **permanently delete** infrastructure. Always:
- Review what will be destroyed
- Ensure you have backups if needed
- Run in non-production environments first
- Understand the cost implications

## Support

For issues or questions, please refer to:
- [InfraForge Documentation](../README.md)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs)
