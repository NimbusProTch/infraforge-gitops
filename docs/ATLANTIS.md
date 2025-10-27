# Atlantis Integration Guide

## What is Atlantis?

**Atlantis** is a self-hosted tool that provides Terraform automation via Pull Requests. It brings collaboration, visibility, and safety to your infrastructure changes.

## Why Use Atlantis?

### ✅ Benefits

1. **Pull Request Based Workflow**
   - All infrastructure changes go through PRs
   - Review changes before applying
   - Track who made what changes

2. **Automated Planning**
   - Atlantis automatically runs `terraform plan` when you open a PR
   - See exactly what will change before merging
   - No more "oops, I forgot to check the plan"

3. **Collaboration & Visibility**
   - Team members can review infrastructure changes
   - Comments directly on the PR with plan output
   - Approval workflow before apply

4. **Safety & Compliance**
   - Require approvals before apply
   - Branch protection
   - No direct access to AWS credentials needed by developers

5. **Audit Trail**
   - Every change is tracked in Git
   - PR history = infrastructure change history
   - Easy rollback with Git revert

6. **State Locking**
   - Prevents concurrent applies
   - No more "someone else is running terraform" issues

## Atlantis Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Developer Opens PR                                          │
│     - Modify terraform/*.tf                                     │
│     - Push to feature branch                                    │
│     - Open PR to main                                          │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Atlantis Automatically Plans                                │
│     - Detects .tf file changes                                  │
│     - Runs: terraform init && terraform plan                    │
│     - Posts plan output as PR comment                          │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Team Reviews                                                │
│     - Review plan output                                        │
│     - Discuss changes in PR                                     │
│     - Request changes if needed                                │
│     - Approve PR when satisfied                                │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Apply Changes                                               │
│     - Comment "atlantis apply" on PR                           │
│     - Atlantis runs: terraform apply                           │
│     - Posts apply output                                        │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. Merge PR                                                    │
│     - Changes are applied                                       │
│     - PR merged to main                                        │
│     - Infrastructure updated                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Setup Atlantis

### Option 1: Run on EKS (Recommended)

1. **Create Atlantis Namespace**
   ```bash
   kubectl create namespace atlantis
   ```

2. **Create GitHub Token Secret**
   ```bash
   kubectl create secret generic atlantis-github \
     --from-literal=token=ghp_your_github_token \
     -n atlantis
   ```

3. **Create AWS Credentials Secret**
   ```bash
   kubectl create secret generic atlantis-aws \
     --from-literal=AWS_ACCESS_KEY_ID=your_key \
     --from-literal=AWS_SECRET_ACCESS_KEY=your_secret \
     -n atlantis
   ```

4. **Deploy Atlantis**
   ```yaml
   # k8s/atlantis/deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: atlantis
     namespace: atlantis
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: atlantis
     template:
       metadata:
         labels:
           app: atlantis
       spec:
         containers:
         - name: atlantis
           image: ghcr.io/runatlantis/atlantis:latest
           env:
           - name: ATLANTIS_REPO_ALLOWLIST
             value: "github.com/NimbusProTch/infraforge-gitops"
           - name: ATLANTIS_GH_USER
             value: "your-github-username"
           - name: ATLANTIS_GH_TOKEN
             valueFrom:
               secretKeyRef:
                 name: atlantis-github
                 key: token
           - name: ATLANTIS_REPO_CONFIG_JSON
             value: '{"repos":[{"id":"/.*/","apply_requirements":["approved"]}]}'
           - name: AWS_ACCESS_KEY_ID
             valueFrom:
               secretKeyRef:
                 name: atlantis-aws
                 key: AWS_ACCESS_KEY_ID
           - name: AWS_SECRET_ACCESS_KEY
             valueFrom:
               secretKeyRef:
                 name: atlantis-aws
                 key: AWS_SECRET_ACCESS_KEY
           ports:
           - containerPort: 4141
           volumeMounts:
           - name: atlantis-data
             mountPath: /atlantis-data
         volumes:
         - name: atlantis-data
           emptyDir: {}
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: atlantis
     namespace: atlantis
   spec:
     type: LoadBalancer
     ports:
     - port: 80
       targetPort: 4141
     selector:
       app: atlantis
   ```

5. **Configure GitHub Webhook**
   - Go to GitHub repo → Settings → Webhooks
   - Add webhook:
     - URL: `http://your-atlantis-url/events`
     - Content type: `application/json`
     - Events: `Pull requests`, `Pull request reviews`, `Issue comments`

### Option 2: Run Locally (Development)

```bash
# Install Atlantis
brew install atlantis  # macOS
# or download from https://github.com/runatlantis/atlantis/releases

# Run Atlantis
atlantis server \
  --atlantis-url="http://localhost:4141" \
  --repo-allowlist="github.com/NimbusProTch/*" \
  --gh-user="your-github-username" \
  --gh-token="your-github-token"
```

## Using Atlantis

### Basic Commands (in PR comments)

```bash
# Plan changes
atlantis plan

# Plan specific project
atlantis plan -p infraforge-production

# Apply changes (after approval)
atlantis apply

# Apply specific project
atlantis apply -p infraforge-production

# Show help
atlantis help
```

### Example Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/add-redis
   ```

2. **Make changes**
   ```bash
   # Edit config/apps.yaml
   vim config/apps.yaml
   # Enable redis_operator
   ```

3. **Commit and push**
   ```bash
   git add config/apps.yaml
   git commit -m "Enable Redis operator"
   git push origin feature/add-redis
   ```

4. **Open Pull Request**
   - Go to GitHub
   - Create PR from `feature/add-redis` to `main`
   - Atlantis automatically comments with plan output

5. **Review plan**
   ```
   Plan: 5 to add, 2 to change, 0 to destroy

   + kubernetes_namespace.redis_operator[0]
   + helm_release.redis_operator[0]
   ...
   ```

6. **Get approval**
   - Team reviews changes
   - Approves PR

7. **Apply changes**
   - Comment on PR: `atlantis apply`
   - Atlantis applies changes
   - Posts output

8. **Merge PR**
   - Merge when apply succeeds
   - Infrastructure is updated!

## Atlantis vs Manual Workflow

### Manual Workflow (Before)

```bash
# Developer has to:
cd terraform
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
terraform plan  # Did I check the plan? Maybe...
terraform apply  # Oops, applied to wrong environment
git push  # Hope nobody else is running terraform...
```

**Problems:**
- ❌ No review process
- ❌ Direct AWS access required
- ❌ No visibility for team
- ❌ Easy to make mistakes
- ❌ No audit trail

### Atlantis Workflow (After)

```bash
# Developer just needs to:
git checkout -b feature/my-change
vim terraform/main.tf
git commit -m "Add feature"
git push
# Open PR → Atlantis does the rest!
```

**Benefits:**
- ✅ Automatic planning
- ✅ Team review required
- ✅ No AWS credentials needed
- ✅ Full visibility
- ✅ Complete audit trail
- ✅ State locking automatic

## Integration with Our Setup

Our `atlantis.yaml` is pre-configured to:

1. **Auto-plan** when these files change:
   - `terraform/*.tf`
   - `terraform/*.tfvars`
   - `config/apps.yaml`
   - `argocd/*.yaml`

2. **Require approval** before apply
   - At least 1 approval needed
   - PR must be mergeable

3. **Validate config** before plan
   - Check `config/apps.yaml` exists
   - Custom validation hooks

4. **Use our workflow**
   - Custom `infraforge` workflow
   - Proper initialization
   - Correct variable files

## Advanced Features

### 1. Multiple Environments

```yaml
# atlantis.yaml
projects:
  - name: infraforge-production
    dir: terraform
    workspace: production

  - name: infraforge-staging
    dir: terraform
    workspace: staging
```

### 2. Custom Workflows

```yaml
workflows:
  custom:
    plan:
      steps:
        - run: make validate
        - run: make check
        - init
        - plan
```

### 3. Policy as Code

```yaml
# atlantis.yaml
workflows:
  infraforge:
    plan:
      steps:
        - init
        - plan
        - run: |
            # Run OPA policies
            conftest test terraform/
```

### 4. Cost Estimation

```yaml
workflows:
  infraforge:
    plan:
      steps:
        - init
        - plan
        - run: |
            # Estimate costs
            infracost breakdown --path .
```

## Security Best Practices

1. **Use IRSA for AWS Credentials** (EKS)
   - No hardcoded credentials
   - IAM role for service account

2. **Least Privilege**
   - Atlantis only needs what it applies
   - Separate IAM roles per environment

3. **Require Approvals**
   - Never allow unapproved applies
   - Use GitHub CODEOWNERS

4. **Audit Logs**
   - All changes tracked in PRs
   - Atlantis logs everything

5. **Webhook Secret**
   - Secure webhook with secret
   - Validate GitHub signatures

## Troubleshooting

### Atlantis not commenting

1. Check webhook delivery in GitHub
2. Verify Atlantis logs: `kubectl logs -n atlantis -l app=atlantis`
3. Check GitHub token permissions

### Plan fails

1. Check AWS credentials
2. Verify S3 backend accessible
3. Check Atlantis has network access

### Apply fails

1. Ensure PR is approved
2. Check state lock (DynamoDB)
3. Verify no manual changes

## Resources

- **Atlantis Docs**: https://www.runatlantis.io/docs/
- **GitHub App Setup**: https://www.runatlantis.io/docs/access-credentials.html
- **Terraform Cloud Alternative**: https://www.terraform.io/cloud

## Comparison: Atlantis vs Alternatives

| Feature | Atlantis | Terraform Cloud | Spacelift | env0 |
|---------|----------|----------------|-----------|------|
| **Cost** | Free (self-hosted) | Free tier, paid plans | Paid | Paid |
| **Hosting** | Self-hosted | Cloud | Cloud | Cloud |
| **PR Integration** | ✅ | ✅ | ✅ | ✅ |
| **State Management** | External (S3) | Built-in | Built-in | Built-in |
| **Policy as Code** | Basic | Advanced | Advanced | Advanced |
| **Cost Estimation** | Via hooks | Built-in | Built-in | Built-in |
| **RBAC** | Basic | Advanced | Advanced | Advanced |
| **Audit Logs** | PR history | Built-in | Built-in | Built-in |

**Recommendation**: Start with Atlantis (free), migrate to Terraform Cloud if you need advanced features.

## Getting Started

1. Review `atlantis.yaml` configuration
2. Deploy Atlantis to EKS (or run locally for testing)
3. Configure GitHub webhook
4. Try a test PR
5. Enjoy PR-based infrastructure workflow! 🎉
