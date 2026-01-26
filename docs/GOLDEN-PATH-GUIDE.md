# Golden Path: Create Application Template

## Overview

The **Golden Path "Create Application"** template is a production-grade, opinionated way to create and deploy microservices on our Internal Developer Platform (IDP). It automates the entire lifecycle from code generation to production deployment.

## What Gets Created

When you use this template, you get:

### 1. Application Repository
- **Multi-tech stack support:** Node.js (Express), Python (FastAPI), or Go (Gin)
- **Production-ready code:** Structured logging, health checks, Prometheus metrics
- **CI/CD pipeline:** GitHub Actions workflow with OIDC, ECR push, GitOps update
- **Dockerfile:** Multi-stage, optimized, non-root user
- **Backstage catalog:** Pre-configured with observability links

### 2. GitOps Repository
- **Kubernetes manifests:** Deployment, Service, Ingress, ServiceMonitor
- **Standard labels:** For Prometheus, Loki, and Backstage integration
- **Resource limits:** CPU and memory requests/limits
- **Health checks:** Liveness and readiness probes
- **Namespace:** Auto-created if needed

### 3. Infrastructure (Optional)
Provisioned via **Crossplane Claims**:
- **ECR Repository:** With lifecycle policies and image scanning
- **RDS Instance:** PostgreSQL with t-shirt sizing (P/M/G)
- **S3 Bucket:** With encryption and public access block
- **SSM Parameters/Secrets:** Connection details for apps

### 4. ArgoCD Application
- **Automatic sync:** GitOps-driven deployment
- **Self-healing:** Reverts manual changes
- **Prune:** Removes deleted resources
- **ApplicationSet discovery:** Auto-discovered from platform repo

### 5. Observability
- **Logs:** Automatically collected by Promtail → Loki
- **Metrics:** Scraped by Prometheus via ServiceMonitor
- **Dashboards:** Pre-configured Grafana dashboards
- **Deep links:** From Backstage to Grafana

## Prerequisites

Before using the Golden Path:

### Platform Requirements
- ✅ EKS cluster running
- ✅ ArgoCD installed and configured
- ✅ Crossplane installed with AWS provider
- ✅ Backstage running with template registered
- ✅ GitHub organization and OIDC provider configured
- ✅ Observability stack (Loki, Prometheus, Grafana) deployed

### User Requirements
- ✅ Access to Backstage
- ✅ GitHub account with access to organization
- ✅ Team/owner assigned in Backstage

### Secrets Configuration
Backstage needs these secrets configured:
- `AWS_REGION`: AWS region (e.g., us-east-1)
- `AWS_ACCOUNT_ID`: AWS account ID
- `BASE_DOMAIN`: Base domain for ingresses
- `CERTIFICATE_ARN`: ACM certificate ARN
- `GITHUB_ORG`: GitHub organization name
- `PLATFORM_GITOPS_REPO`: Platform GitOps repository name
- `DB_SUBNET_ID_1`, `DB_SUBNET_ID_2`: RDS subnet IDs (if using database)
- `DB_SECURITY_GROUP_ID`: RDS security group ID (if using database)

## How to Use

### Step 1: Open Backstage

Navigate to: `https://backstage.{your-domain}/create`

### Step 2: Select Template

Click on **"New Microservice (Containerized)"**

### Step 3: Fill Out the Form

#### Application Configuration

- **Service Name:** Lowercase, alphanumeric, hyphens only
  - ✅ `user-api`
  - ✅ `payment-service`
  - ❌ `User_API` (no underscores, no uppercase)

- **Description:** Brief description of what this service does

- **Owner:** Select your team from the dropdown

- **Technology Stack:** Choose your preferred language/framework
  - `Node.js (Express)` - Port 3000
  - `Python (FastAPI)` - Port 8000
  - `Go (Gin)` - Port 8080

#### Infrastructure Requirements

- **Needs Database?**
  - `Yes` - Provisions a PostgreSQL RDS instance via Crossplane
  - `No` - No database provisioned

- **Database Size** (if database needed):
  - `P (Small)` - db.t3.micro, 20GB storage
  - `M (Medium)` - db.t3.small, 50GB storage
  - `G (Large)` - db.t3.medium, 100GB storage

- **Needs S3 Bucket?**
  - `Yes` - Provisions an S3 bucket via Crossplane
  - `No` - No bucket provisioned

#### Deployment Configuration

- **Kubernetes Namespace:**
  - `default` - Default namespace
  - `team-alpha` - Team Alpha namespace
  - `team-beta` - Team Beta namespace
  - Or any custom namespace

- **Service Exposure:**
  - `Cluster-only` - No ingress, only accessible within cluster
  - `Internal` - ALB ingress, internal network only
  - `Public` - ALB ingress, internet-facing

- **Replicas:** Number of pod replicas (1-10)

### Step 4: Review and Create

Click **"Create"** and wait for the process to complete.

Backstage will:
1. ✅ Generate application code
2. ✅ Create GitHub repository
3. ✅ Push code to GitHub
4. ✅ Generate GitOps manifests
5. ✅ Create GitOps repository
6. ✅ Create Crossplane Claims (if infrastructure requested)
7. ✅ Create Pull Request for ArgoCD Application
8. ✅ Register component in Backstage catalog

### Step 5: Merge ArgoCD Application PR

1. Go to the platform GitOps repository
2. Find the Pull Request created by Backstage
3. Review the ArgoCD Application manifest
4. Merge the PR

ArgoCD will:
- Discover the new application (via ApplicationSet)
- Sync the GitOps repository
- Deploy your application to Kubernetes

### Step 6: Verify Deployment

**In Backstage:**
- Go to your component page
- Click **"Kubernetes"** tab to see pods
- Click **"View Logs"** link to see logs in Grafana
- Click **"View Metrics"** link to see metrics dashboard

**In ArgoCD:**
```bash
argocd app get {your-app-name}
```

**In Kubernetes:**
```bash
kubectl get pods -n {namespace} -l app.kubernetes.io/name={your-app-name}
kubectl logs -n {namespace} -l app.kubernetes.io/name={your-app-name} --tail=50 -f
```

### Step 7: Make Changes

**Update application code:**
1. Clone the application repository
2. Make changes
3. Commit and push to `main` branch
4. GitHub Actions builds and pushes new image
5. GitOps repository updated automatically
6. ArgoCD syncs and deploys new version

**Update Kubernetes manifests:**
1. Clone the GitOps repository
2. Edit files in `manifests/`
3. Commit and push to `main` branch
4. ArgoCD syncs and applies changes

## What Happens Under the Hood

### CI/CD Flow

```
┌─────────────────┐
│  Push to main   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  GitHub Actions │
│  - Lint code    │
│  - Run tests    │
│  - Build image  │
│  - Push to ECR  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Update GitOps   │
│ - Checkout repo │
│ - Update image  │
│ - Validate YAML │
│ - Commit & push │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     ArgoCD      │
│ - Detect change │
│ - Sync cluster  │
│ - Deploy pods   │
└─────────────────┘
```

### Crossplane Infrastructure

```
┌─────────────────┐
│  Backstage      │
│  creates Claim  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Crossplane    │
│ - Matches XRD   │
│ - Applies patch │
│ - Creates AWS   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   AWS API       │
│ - Provisions    │
│ - Returns info  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Status/Secret  │
│ - Endpoint      │
│ - Credentials   │
└─────────────────┘
```

## Application Structure

### Application Repository

```
{app-name}/
├── src/                      # Source code
│   └── index.js             # Application entry point
├── .github/
│   └── workflows/
│       └── ci-cd.yaml       # CI/CD pipeline
├── Dockerfile               # Multi-stage Docker build
├── package.json             # Dependencies (Node.js)
├── requirements.txt         # Dependencies (Python)
├── go.mod                   # Dependencies (Go)
├── catalog-info.yaml        # Backstage metadata
└── README.md                # Documentation
```

### GitOps Repository

```
{app-name}-gitops/
├── manifests/
│   ├── namespace.yaml       # Namespace definition
│   ├── deployment.yaml      # Deployment
│   ├── service.yaml         # ClusterIP service
│   ├── ingress.yaml         # ALB Ingress (if exposed)
│   ├── servicemonitor.yaml  # Prometheus scraping
│   ├── database-claim.yaml  # RDS Claim (if database)
│   └── bucket-claim.yaml    # S3 Claim (if bucket)
├── .argocd/
│   └── application.yaml     # ArgoCD Application (copied to platform repo)
└── README.md                # GitOps documentation
```

## Observability

### Logs

**Automatic collection:**
- Promtail DaemonSet reads pod logs
- Logs sent to Loki
- Queryable in Grafana

**Access logs:**
```
Backstage → Component → View Logs → Grafana Explore
```

**Query format:**
```
{namespace="your-namespace", app_kubernetes_io_name="your-app"}
```

### Metrics

**Automatic scraping:**
- ServiceMonitor tells Prometheus where to scrape
- Prometheus scrapes `/metrics` endpoint
- Metrics stored in Prometheus

**Access metrics:**
```
Backstage → Component → View Metrics → Grafana Dashboard
```

**Dashboard includes:**
- Request rate
- Error rate
- Latency (P50, P95, P99)
- CPU and memory usage

### Dashboards

Pre-configured Grafana dashboards:
- **Service Overview:** High-level service metrics
- **Pod Details:** Per-pod CPU, memory, network
- **Request Analysis:** HTTP request breakdown

## Infrastructure Details

### ECR Repository

**Automatically provisioned:**
- Repository name: `{app-name}`
- Image scanning: Enabled
- Encryption: AES256
- Lifecycle policy: Keep last 10 prod images, 5 staging, expire untagged after 7 days

**Access from CI:**
```yaml
- name: Login to Amazon ECR
  uses: aws-actions/amazon-ecr-login@v2
```

### RDS Instance

**T-shirt sizing:**

| Size | Instance Class | Storage | Use Case |
|------|----------------|---------|----------|
| P | db.t3.micro | 20GB | Development, small apps |
| M | db.t3.small | 50GB | Production, medium traffic |
| G | db.t3.medium | 100GB | Production, high traffic |

**Connection details:**
- Stored in Kubernetes Secret: `{app-name}-db-secret`
- Available as environment variables in pods
- Endpoint and port in Claim status

**Access credentials:**
```bash
kubectl get secret {app-name}-db-secret -n {namespace} -o yaml
```

### S3 Bucket

**Configuration:**
- Bucket name: `{account-id}-{app-name}-{timestamp}`
- Public access: Blocked
- Encryption: AES256
- Versioning: Disabled (can be enabled)

**Access from app:**
- Use IAM Role for Service Account (IRSA)
- Crossplane can provision IAM policy
- Bucket ARN in Claim status

## Troubleshooting

### Application Not Created

**Check Backstage logs:**
```bash
kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=100 -f
```

**Common issues:**
- GitHub token expired or insufficient permissions
- AWS credentials not configured
- Template syntax errors

### GitHub Repositories Not Created

**Check:**
- GitHub organization exists and user has access
- GITHUB_ORG secret is correct
- GitHub token has `repo`, `admin:repo_hook` scopes

### ArgoCD Application Not Syncing

**Check Application status:**
```bash
argocd app get {app-name}
```

**Common issues:**
- GitOps repository doesn't exist
- Manifests have syntax errors
- Namespace doesn't exist
- RBAC permissions issue

**Manual sync:**
```bash
argocd app sync {app-name}
```

### Pods Not Starting

**Check pod status:**
```bash
kubectl get pods -n {namespace} -l app.kubernetes.io/name={app-name}
kubectl describe pod {pod-name} -n {namespace}
kubectl logs {pod-name} -n {namespace}
```

**Common issues:**
- Image pull errors (ECR permissions)
- Resource limits too low
- Health check failing
- Environment variables missing

### Infrastructure Not Provisioned

**Check Crossplane logs:**
```bash
kubectl logs -n crossplane-system -l app=crossplane --tail=100 -f
```

**Check Claim status:**
```bash
kubectl get ecrrepositoryclaim {app-name}-ecr -n {namespace} -o yaml
kubectl get rdsinstanceclaim {app-name}-db -n {namespace} -o yaml
kubectl get s3bucketclaim {app-name}-bucket -n {namespace} -o yaml
```

**Common issues:**
- AWS credentials not configured for Crossplane
- Subnet IDs or Security Group IDs incorrect
- IAM permissions missing
- Resource quotas exceeded

### Observability Not Working

**Logs not appearing in Grafana:**
1. Check Promtail is running:
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=promtail
   ```
2. Verify pod labels match Loki query
3. Check Loki ingestion rate limits

**Metrics not appearing in Grafana:**
1. Check ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor {app-name} -n {namespace}
   ```
2. Verify Prometheus is scraping:
   ```bash
   kubectl logs -n observability -l app.kubernetes.io/name=prometheus --tail=50 | grep {app-name}
   ```
3. Check `/metrics` endpoint is accessible:
   ```bash
   kubectl exec -n {namespace} {pod-name} -- curl localhost:{port}/metrics
   ```

## Best Practices

### Naming Conventions

- **Service names:** Short, descriptive, kebab-case (e.g., `user-api`, `payment-svc`)
- **Namespaces:** Team-based or environment-based (e.g., `team-alpha`, `prod`)
- **Labels:** Use standard `app.kubernetes.io/*` labels

### Resource Limits

- **Start small:** Default limits are conservative
- **Monitor first:** Check actual usage in Grafana
- **Scale up:** Adjust limits in GitOps repo based on data

### Secrets Management

- **Never commit secrets:** Use Kubernetes Secrets or External Secrets
- **Rotate regularly:** Update database passwords, API keys
- **Least privilege:** Give apps minimum permissions needed

### GitOps Workflow

- **Single source of truth:** All changes via Git
- **Small diffs:** Make incremental changes
- **Test first:** Use dev/staging environments
- **Automated rollback:** ArgoCD can revert failed deployments

### Database Management

- **Backups:** RDS automated backups enabled by default
- **Migrations:** Use tools like Flyway or Liquibase
- **Connection pooling:** Use PgBouncer or similar for high traffic
- **Read replicas:** Consider for read-heavy workloads (manual setup)

## Advanced Usage

### Custom Health Checks

Edit `deployment.yaml` in GitOps repo:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30  # Increase for slow startup
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
  successThreshold: 1  # Minimum successes before ready
```

### Horizontal Pod Autoscaling

Add HPA to GitOps repo:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {app-name}
  namespace: {namespace}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {app-name}
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Custom Environment Variables

Edit `deployment.yaml`:

```yaml
env:
- name: APP_NAME
  value: "{app-name}"
- name: LOG_LEVEL
  value: "info"
- name: DB_HOST
  valueFrom:
    secretKeyRef:
      name: {app-name}-db-secret
      key: endpoint
```

### Network Policies

Add NetworkPolicy to GitOps repo:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {app-name}
  namespace: {namespace}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: {app-name}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 5432  # PostgreSQL
```

## Migration Guide

### From Existing Application

1. **Create via Golden Path:** Use template to generate new repos
2. **Copy code:** Replace generated code with your existing code
3. **Update Dockerfile:** Ensure it matches new multi-stage pattern
4. **Add health checks:** Implement `/health` and `/ready` endpoints
5. **Add metrics:** Expose `/metrics` endpoint
6. **Test locally:** Build and run Docker image
7. **Push changes:** Commit to trigger CI/CD
8. **Verify deployment:** Check ArgoCD and pods

### From Manual K8s Manifests

1. **Create via Golden Path:** Generate GitOps repo
2. **Copy manifests:** Replace generated manifests with your existing ones
3. **Add standard labels:** Ensure `app.kubernetes.io/*` labels are present
4. **Add ServiceMonitor:** For Prometheus scraping
5. **Update ArgoCD:** Point to new GitOps repo
6. **Sync:** Let ArgoCD deploy

## FAQ

**Q: Can I use a different language/framework?**
A: Currently supports Node.js, Python, Go. To add more, create a new skeleton in `templates/backstage/microservice-containerized/skeleton/{your-stack}/`

**Q: Can I skip infrastructure provisioning?**
A: Yes, select "No" for database and bucket. ECR is provisioned by CI/CD automatically.

**Q: Can I change infrastructure size later?**
A: Yes, edit the Crossplane Claim in GitOps repo and change `size: P` to `size: M` or `size: G`. Crossplane will handle the resize (with downtime for RDS).

**Q: Can I use this for non-containerized apps?**
A: No, this template is specifically for containerized microservices. For other types, create a new template.

**Q: What if I need a different database engine?**
A: Edit the RDS Claim and change `engine: postgres` to `engine: mysql`. Update connection string in app.

**Q: Can I deploy to multiple environments?**
A: Yes, create separate namespaces (e.g., `prod`, `staging`, `dev`) and deploy the same app to each with different configurations.

**Q: How do I rollback a deployment?**
A: In GitOps repo, revert the commit that introduced the issue. ArgoCD will sync and rollback automatically.

**Q: Can I use this in production?**
A: Yes! This template follows production best practices: multi-stage builds, non-root users, resource limits, health checks, observability, GitOps.

## Support

- **Slack:** `#platform-team` channel
- **Backstage:** See component page for owner contact
- **Documentation:** https://docs.{your-domain}/golden-path
- **GitHub Issues:** Platform repo issues for bugs/features

## References

- [Backstage Scaffolder](https://backstage.io/docs/features/software-templates/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Crossplane Documentation](https://crossplane.io/docs/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Loki](https://grafana.com/docs/loki/latest/)
