# Golden Path: 3-Tier Application

## Overview

The Golden Path creates a production-ready 3-tier application on the IDP with a single Backstage template. It provisions all infrastructure (Aurora, S3, CloudFront), deploys the backend to EKS, and configures DNS — fully automated via GitOps.

## What Gets Created

```
┌─────────────────────────────────────────────────────────┐
│                    CloudFront CDN                        │
│            {app}.timedevops.click                        │
│  ┌──────────────┐          ┌──────────────────────┐     │
│  │  S3 Bucket   │          │  ALB (backend proxy)  │     │
│  │  index.html  │          │  /api/* → EKS pod     │     │
│  │  app.js      │          │                       │     │
│  └──────────────┘          └──────────────────────┘     │
└─────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                        ┌──────────────────────┐
                        │   EKS Pod (Backend)   │
                        │   Express :3000       │
                        │   /api/health         │
                        │   /api/users          │
                        └──────────┬───────────┘
                                   │
                                   ▼
                        ┌──────────────────────┐
                        │  Aurora PostgreSQL    │
                        │  db.t4g.medium        │
                        └──────────────────────┘
```

### Tier 1 — Frontend (S3 + CloudFront)
- S3 bucket with `index.html` + `app.js`
- CloudFront distribution with OAC
- Custom domain: `{app}.timedevops.click`
- Backend proxy via CloudFront origin to ALB

### Tier 2 — Backend (EKS)
- Express/Node.js API on port 3000
- ALB Ingress with HTTPS (ACM certificate)
- Two hosts: `internal-{app}.timedevops.click` and `api-{app}.timedevops.click`
- Health check: `GET /api/health`
- Init container waits for DB connection secret

### Tier 3 — Database (Aurora PostgreSQL)
- Aurora PostgreSQL cluster via Crossplane
- Graviton instances (db.t4g.medium)
- Connection secret mounted as volume (`db-conn`)
- Keys: `endpoint`, `port`, `username`, `password`, `database`

## Crossplane Claims

The platform uses custom XRDs under `platform.darede.io/v1alpha1`:

### Aurora (Database)

```yaml
apiVersion: platform.darede.io/v1alpha1
kind: Aurora
metadata:
  name: {app}-db
  namespace: {app}
  labels:
    db.engine: aurora-postgresql
spec:
  appName: {app}
  dbEngine: aurora-postgresql    # or: aurora-mysql, rds-mysql, rds-postgresql
  dbSize: M                     # P (small), M (medium), G (large)
  compositionSelector:
    matchLabels:
      db.engine: aurora-postgresql
  vpcId: vpc-0b050e119ea97ff04
  subnetIds:
    - subnet-0c9e3902a62022850
    - subnet-045e94472e0068db7
    - subnet-0086df67ce197c14d
  allowedSecurityGroupId: sg-06e8c156b7703c26b
  masterPasswordSecretRef:
    name: {app}-aurora-master-password
    namespace: {app}
    key: password
  writeConnectionSecretToRef:
    name: {app}-db-conn
```

**Available compositions:**

| Composition | Engine | Description |
|-------------|--------|-------------|
| `aurora-postgresql` | Aurora PostgreSQL | Cluster + writer instance (Graviton) |
| `aurora-mysql` | Aurora MySQL | Cluster + writer instance (Graviton) |
| `rds-postgresql` | RDS PostgreSQL | Standalone instance |
| `rds-mysql` | RDS MySQL | Standalone instance |

### StaticWebsite (Frontend)

```yaml
apiVersion: platform.darede.io/v1alpha1
kind: StaticWebsite
metadata:
  name: {app}-web
  namespace: {app}
spec:
  siteName: {app}
  customDomain: {app}.timedevops.click
  backendOriginDomain: internal-{app}.timedevops.click
  acmCertificateArn: arn:aws:acm:us-east-1:948881762705:certificate/051f6515-...
  hostedZoneId: Z09212782MXWNY5EYNICO
  region: us-east-1
  indexDocument: index.html
  errorDocument: index.html
  priceClass: PriceClass_100
```

Provisions: S3 bucket + CloudFront + OAC + Route53 records + bucket policy.

### HttpApi (API Gateway)

```yaml
apiVersion: platform.darede.io/v1alpha1
kind: HttpApi
metadata:
  name: {app}-api
  namespace: {app}
spec:
  # API Gateway + Cognito authorizer + VPC Link
```

## Deployment Flow

```
1. Backstage Template    → Developer fills form, clicks Create
2. GitHub Repo Created   → App code + Dockerfile + CI/CD workflow
3. GitHub Actions        → Build image → Push to ECR
4. GitOps Repo Updated   → K8s manifests + Crossplane claims
5. ArgoCD Syncs 3 Apps:
   ├── {app}             → Namespace + base resources
   ├── {app}-infra       → Aurora claim + StaticWebsite claim
   └── {app}-backend     → Deployment + Service + Ingress
6. Crossplane Provisions → Aurora cluster + S3 + CloudFront + DNS
7. Init Container        → Waits for DB secret, then app starts
8. App Live              → https://{app}.timedevops.click
```

## URLs Generated

| URL | Purpose |
|-----|---------|
| `https://{app}.timedevops.click` | Frontend (CloudFront → S3 + backend proxy) |
| `https://api-{app}.timedevops.click` | API direct access (ALB → EKS) |
| `https://internal-{app}.timedevops.click` | Internal backend (used by CloudFront origin) |

## Environment Variables

The backend pod receives:

| Variable | Value | Source |
|----------|-------|--------|
| `PORT` | `3000` | Deployment spec |
| `DB_ENGINE` | `aurora-postgresql` | Deployment spec |
| `DB_SSL` | `true` | Deployment spec |
| `DB_NAME` | `app` | Deployment spec |
| DB credentials | endpoint, port, user, pass | Mounted from secret `{app}-db-conn` at `/etc/db-conn/` |

## Health Checks

| Probe | Path | Config |
|-------|------|--------|
| Liveness | `GET /api/health` | delay=30s, period=20s, failure=3 |
| Readiness | `GET /api/health` | delay=10s, period=10s, failure=3 |
| ALB health check | `/api/health` | Configured via ingress annotation |

Response: `{"status":"ok","now":"...","engine":"aurora-postgresql"}`

## Verifying a Deployment

### Check ArgoCD apps
```bash
kubectl get applications -n argocd | grep {app}
# Should show 3-4 apps: idp-{app}, {app}, {app}-backend, {app}-infra
```

### Check Crossplane claims
```bash
kubectl get aurora,staticwebsite -n {app}
# Both should show SYNCED=True, READY=True
```

### Check pods
```bash
kubectl get pods -n {app}
# Should show 1/1 Running
```

### Test health
```bash
curl https://api-{app}.timedevops.click/api/health
```

### Test frontend
```bash
curl https://{app}.timedevops.click
```

## Troubleshooting

### Pod stuck in Init:0/1

The init container waits for DB connection secret files. Check if Aurora claim is ready:

```bash
kubectl get aurora -n {app}
# If READY=False, check Crossplane logs:
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision -c package-runtime --tail=50
```

### ImagePullBackOff

ECR image not found. Check if CI/CD ran:

```bash
aws ecr describe-images --repository-name idp-{app} --region us-east-1 --profile darede-iam
```

### CrashLoopBackOff

App crashing after start. Check logs:

```bash
kubectl logs -n {app} -l app={app} --tail=50
```

Common causes: DB connection failed (wrong secret), port mismatch, missing env vars.

### CloudFront returning 403

S3 bucket empty or OAC not configured. Check:

```bash
aws s3 ls s3://idp-{app}-static/ --profile darede-iam
```

### ArgoCD app OutOfSync

```bash
kubectl get application {app}-infra -n argocd -o yaml | grep -A5 status
# Force sync:
argocd app sync {app}-infra
```

### Cleaning up a failed deployment

Delete in order — ArgoCD apps first (cascade deletes K8s + Crossplane resources):

```bash
# Delete ArgoCD apps (triggers cascade cleanup)
kubectl delete application -n argocd idp-{app} {app} {app}-backend {app}-infra

# Wait for Crossplane to delete AWS resources (~5 min for Aurora)
kubectl get managed | grep {app}

# Delete namespace
kubectl delete ns {app}

# If namespace stuck in Terminating, check for finalizers:
kubectl get ns {app} -o json | jq '.spec.finalizers'
```

## Advanced: Adding HPA

Add to the GitOps repo manifests:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {app}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {app}
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

## Advanced: Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {app}
spec:
  podSelector:
    matchLabels:
      app: {app}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - port: 3000
  egress:
  - to: []
    ports:
    - port: 5432
    - port: 443
```
