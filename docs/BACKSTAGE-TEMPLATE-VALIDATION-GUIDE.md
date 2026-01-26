# Backstage Template Validation Guide

## Purpose

This guide provides step-by-step instructions to validate that the Backstage scaffolder template correctly creates a GitHub repository with all necessary files for a containerized microservice.

---

## Prerequisites

1. **Backstage is accessible**: `https://backstage.timedevops.click`
2. **You can authenticate**: Use Keycloak credentials (see `docs/BACKSTAGE-AUTHENTICATION-FIX.md` for user creation)
3. **GitHub PAT is configured**: The `GITHUB_TOKEN` secret must be set in the `backstage-env-vars` Secret
4. **AWS credentials**: ECR and S3 access configured for CI/CD

---

## Validation Steps

### Step 1: Access Backstage and Create an Application

1. Open browser and navigate to: `https://backstage.timedevops.click`

2. Click **"Sign In"** and authenticate with Keycloak

3. From the home page, click **"Create"** in the left sidebar

4. Select the template: **"Containerized Microservice"**

5. Fill in the parameters:
   - **Name**: `test-app-001` (or any unique name)
   - **Description**: `Test application created via Backstage scaffolder`
   - **Owner**: Your team name (e.g., `platform-team`)
   - **Namespace**: `default` (or your team namespace)
   - **Runtime**: `nodejs`
   - **Port**: `3000`
   - **Enable Metrics**: `Yes`

6. Review and click **"Create"**

7. Wait for the scaffolding process to complete (typically 30-60 seconds)

8. You should see a success message with:
   - Link to the created GitHub repository
   - Link to the Backstage catalog entry

---

### Step 2: Verify GitHub Repository Creation

1. Click the GitHub repository link from Backstage, or navigate to:
   ```
   https://github.com/<your-org>/test-app-001
   ```

2. Verify the repository exists and contains the following files:

#### Expected Repository Structure
```
test-app-001/
├── .github/
│   └── workflows/
│       └── ci-cd.yaml              # GitHub Actions workflow
├── src/
│   └── index.js                    # Application code
├── Dockerfile                       # Container image definition
├── package.json                     # Node.js dependencies
├── README.md                        # Application documentation
└── catalog-info.yaml                # Backstage catalog metadata
```

---

### Step 3: Validate File Contents

#### 3.1 Application Code (`src/index.js`)

**Expected**:
- Express.js server
- Health endpoints (`/health`, `/ready`)
- Structured JSON logging
- Prometheus metrics endpoint (`/metrics`)

**Validation**:
```bash
# Clone the repository
git clone https://github.com/<your-org>/test-app-001
cd test-app-001

# Check for health endpoints
grep -r "/health" src/index.js
grep -r "/ready" src/index.js

# Check for metrics
grep -r "/metrics" src/index.js
```

#### 3.2 Dockerfile

**Expected**:
- Multi-stage build (builder + production)
- Uses `node:18-alpine` base image
- Runs as non-root user (`nodejs`)
- Exposes port `3000`
- Includes healthcheck

**Validation**:
```bash
# Check Dockerfile
cat Dockerfile

# Verify multi-stage build
grep "FROM node" Dockerfile | wc -l  # Should be 2

# Verify non-root user
grep "USER nodejs" Dockerfile

# Verify healthcheck
grep "HEALTHCHECK" Dockerfile
```

#### 3.3 CI/CD Workflow (`.github/workflows/ci-cd.yaml`)

**Expected**:
- Triggers on push to `main` branch
- AWS authentication via GitHub OIDC
- Builds Docker image
- Pushes to ECR
- Updates GitOps repository with new image tag

**Validation**:
```bash
# Check workflow file
cat .github/workflows/ci-cd.yaml

# Verify steps
grep -A5 "steps:" .github/workflows/ci-cd.yaml | grep -E "name:|uses:"

# Expected steps:
# - Checkout code
# - Configure AWS credentials (aws-actions/configure-aws-credentials@v2)
# - Login to Amazon ECR
# - Build Docker image
# - Push to ECR
# - Update GitOps repository
```

#### 3.4 Backstage Catalog (`catalog-info.yaml`)

**Expected**:
- Component type: `service`
- GitHub project slug
- Kubernetes annotations
- ArgoCD annotations
- Observability annotations (Grafana, Loki)

**Validation**:
```bash
# Check catalog file
cat catalog-info.yaml

# Verify annotations
yq '.metadata.annotations' catalog-info.yaml

# Expected annotations:
# - github.com/project-slug
# - backstage.io/kubernetes-id
# - backstage.io/kubernetes-namespace
# - argocd/app-name
# - grafana.io/loki-query-url
# - grafana.io/dashboard-url
```

---

### Step 4: Verify CI/CD Pipeline Execution

1. Navigate to the GitHub Actions tab in the repository:
   ```
   https://github.com/<your-org>/test-app-001/actions
   ```

2. You should see a workflow run triggered by the initial commit

3. Click on the workflow run and verify all steps complete successfully:
   - ✅ Checkout code
   - ✅ Configure AWS credentials
   - ✅ Login to Amazon ECR
   - ✅ Build Docker image
   - ✅ Push to ECR
   - ✅ Update GitOps repository

4. If the workflow fails, check the logs for errors

---

### Step 5: Verify ECR Image

1. Check if the Docker image was pushed to ECR:
   ```bash
   # List images in ECR repository
   aws ecr describe-images \
     --repository-name test-app-001 \
     --query 'imageDetails[*].[imageTags[0],imagePushedAt]' \
     --output table
   ```

2. Expected output:
   ```
   ----------------------
   |  DescribeImages    |
   +----------+---------+
   |  main    | <date>  |
   +----------+---------+
   ```

---

### Step 6: Verify GitOps Repository Update

1. Navigate to the GitOps repository: `https://github.com/<your-org>/<gitops-repo>`

2. Check for a new directory:
   ```
   applications/workloads/default/test-app-001/
   ```

3. Verify the directory contains:
   - `deployment.yaml` - Kubernetes Deployment manifest
   - `service.yaml` - Kubernetes Service manifest (if created)
   - `ingress.yaml` - Kubernetes Ingress manifest (if created)

4. Check the image tag in `deployment.yaml`:
   ```bash
   # Clone GitOps repo
   git clone https://github.com/<your-org>/<gitops-repo>
   cd <gitops-repo>

   # Check image tag
   yq '.spec.template.spec.containers[0].image' applications/workloads/default/test-app-001/deployment.yaml
   ```

5. Expected format:
   ```
   <account-id>.dkr.ecr.<region>.amazonaws.com/test-app-001:main
   ```

---

### Step 7: Verify ArgoCD Sync

1. Navigate to ArgoCD UI: `https://argocd.timedevops.click`

2. Look for the application: `test-app-001`

3. Verify:
   - **Health Status**: Healthy
   - **Sync Status**: Synced
   - **Pods**: Running

4. Alternatively, check via CLI:
   ```bash
   # Get ArgoCD application status
   argocd app get test-app-001

   # Get pods
   kubectl get pods -n default -l app.kubernetes.io/name=test-app-001
   ```

---

### Step 8: Verify Application is Running

1. **Port-forward to the application**:
   ```bash
   kubectl port-forward -n default svc/test-app-001 8080:80
   ```

2. **Test health endpoints**:
   ```bash
   # Health check
   curl http://localhost:8080/health
   # Expected: {"status":"healthy","timestamp":"..."}

   # Readiness check
   curl http://localhost:8080/ready
   # Expected: {"status":"ready","timestamp":"..."}

   # Metrics
   curl http://localhost:8080/metrics
   # Expected: Prometheus metrics in text format
   ```

3. **Test application endpoint**:
   ```bash
   curl http://localhost:8080/
   # Expected: JSON response with service info
   ```

---

### Step 9: Verify Observability Integration

1. **Access Grafana**: `https://grafana.timedevops.click`

2. Navigate to **Explore** → **Loki**

3. Run a query for your application logs:
   ```
   {namespace="default", app_kubernetes_io_name="test-app-001"}
   ```

4. Verify logs are appearing

5. **Check Backstage Catalog**:
   - Navigate to: `https://backstage.timedevops.click/catalog`
   - Find your application: `test-app-001`
   - Click on it
   - Verify the **"View Logs"** link works (should open Grafana Explore)
   - Verify the **"View Metrics"** link works (should open Grafana dashboard)

---

## Automated Validation Script

For convenience, you can use this script to automate some of the validation steps:

```bash
#!/bin/bash
# scripts/validate-backstage-template.sh

set -e

APP_NAME=${1:-"test-app-001"}
GITHUB_ORG=${2:-"<your-org>"}
GITOPS_REPO=${3:-"<gitops-repo>"}

echo "=== Validating Backstage Template for $APP_NAME ==="

# 1. Check if GitHub repository exists
echo "1. Checking GitHub repository..."
if gh repo view "$GITHUB_ORG/$APP_NAME" &>/dev/null; then
  echo "✅ Repository exists: $GITHUB_ORG/$APP_NAME"
else
  echo "❌ Repository not found: $GITHUB_ORG/$APP_NAME"
  exit 1
fi

# 2. Clone and check file structure
echo "2. Checking file structure..."
TEMP_DIR=$(mktemp -d)
git clone "https://github.com/$GITHUB_ORG/$APP_NAME" "$TEMP_DIR/$APP_NAME" &>/dev/null
cd "$TEMP_DIR/$APP_NAME"

REQUIRED_FILES=(
  "src/index.js"
  "Dockerfile"
  "package.json"
  "README.md"
  "catalog-info.yaml"
  ".github/workflows/ci-cd.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "✅ File exists: $file"
  else
    echo "❌ File missing: $file"
    exit 1
  fi
done

# 3. Check ECR image
echo "3. Checking ECR image..."
if aws ecr describe-images --repository-name "$APP_NAME" --query 'imageDetails[0].imageTags[0]' --output text &>/dev/null; then
  echo "✅ ECR image exists"
else
  echo "⚠️  ECR image not found (may need time for CI/CD to complete)"
fi

# 4. Check GitOps repository
echo "4. Checking GitOps repository..."
git clone "https://github.com/$GITHUB_ORG/$GITOPS_REPO" "$TEMP_DIR/$GITOPS_REPO" &>/dev/null
if [ -d "$TEMP_DIR/$GITOPS_REPO/applications/workloads/default/$APP_NAME" ]; then
  echo "✅ GitOps manifests exist"
else
  echo "⚠️  GitOps manifests not found (may need time for CI/CD to complete)"
fi

# 5. Check Kubernetes deployment
echo "5. Checking Kubernetes deployment..."
if kubectl get deployment "$APP_NAME" -n default &>/dev/null; then
  READY=$(kubectl get deployment "$APP_NAME" -n default -o jsonpath='{.status.readyReplicas}')
  DESIRED=$(kubectl get deployment "$APP_NAME" -n default -o jsonpath='{.spec.replicas}')
  if [ "$READY" = "$DESIRED" ]; then
    echo "✅ Deployment is ready ($READY/$DESIRED)"
  else
    echo "⚠️  Deployment is not fully ready ($READY/$DESIRED)"
  fi
else
  echo "⚠️  Deployment not found (may need time for ArgoCD sync)"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "=== Validation Complete ==="
```

**Usage**:
```bash
chmod +x scripts/validate-backstage-template.sh
./scripts/validate-backstage-template.sh test-app-001 <your-org> <gitops-repo>
```

---

## Expected Results Summary

After completing all steps, you should have:

1. ✅ **GitHub Repository**: Created with all necessary files
2. ✅ **CI/CD Pipeline**: Executed successfully
3. ✅ **ECR Image**: Docker image pushed to ECR
4. ✅ **GitOps Update**: Kubernetes manifests committed to GitOps repo
5. ✅ **ArgoCD Sync**: Application deployed and healthy
6. ✅ **Running Application**: Pods running and responding to health checks
7. ✅ **Observability**: Logs visible in Grafana/Loki

---

## Troubleshooting

### Issue: CI/CD Workflow Fails

**Check**:
1. GitHub OIDC provider is configured in AWS
2. IAM role for GitHub Actions has ECR push permissions
3. Secrets are correctly set in `backstage-env-vars`

**Fix**:
```bash
# Verify GitHub OIDC provider
aws iam list-open-id-connect-providers

# Verify IAM role
aws iam get-role --role-name github-ecr-push-role
```

### Issue: Image Not Pushed to ECR

**Check**:
1. ECR repository exists
2. GitHub Actions workflow completed successfully
3. AWS credentials are valid

**Fix**:
```bash
# Create ECR repository if missing
aws ecr create-repository --repository-name test-app-001

# Check workflow logs in GitHub Actions
```

### Issue: GitOps Repository Not Updated

**Check**:
1. GitHub PAT has write permissions
2. Workflow step "Update GitOps repository" completed
3. GitOps repository exists

**Fix**:
```bash
# Check GitHub PAT permissions
gh auth status

# Manually commit to GitOps repo to test
git clone https://github.com/<your-org>/<gitops-repo>
# ... make changes ...
git push
```

### Issue: ArgoCD Not Syncing

**Check**:
1. ArgoCD ApplicationSet is configured
2. GitOps path matches ApplicationSet pattern
3. Kubernetes manifests are valid

**Fix**:
```bash
# Check ApplicationSet
kubectl get applicationset -n argocd

# Manually sync in ArgoCD
argocd app sync test-app-001

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

---

## Next Steps

After successful validation:

1. **Document any issues found** and report to the platform team
2. **Create additional applications** to test different configurations
3. **Test failure scenarios** (e.g., invalid Docker build, missing secrets)
4. **Add E2E test** to automatically validate template functionality

---

**END OF GUIDE**
