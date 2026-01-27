# Backstage Deployment Plan

## 📋 Overview

This document outlines the strategy for deploying Backstage as the Internal Developer Platform (IDP) following GitOps best practices with ArgoCD.

---

## 🎯 Objectives

1. **User-Friendly Installation**: Streamlined process via Makefile
2. **GitOps Native**: All configuration in Git, managed by ArgoCD
3. **Correct Dependencies**: Respect installation order (Backstage → Crossplane → Templates)
4. **Best Practices**: Follow official Backstage recommendations
5. **SSO Integration**: Cognito authentication like ArgoCD

---

## 🏗️ Architecture Decision: Infra vs Application

### Phase Separation

**Phase 0 (Bootstrap) - INFRASTRUCTURE**
- VPC, EKS, Karpenter
- ArgoCD, AWS LB Controller, External-DNS
- Cognito User Pool
- **Managed by**: Terraform + Make commands

**Phase 1+ (Platform) - APPLICATIONS**
- Backstage, Crossplane, Templates
- Platform tools (Grafana, Prometheus, etc.)
- **Managed by**: ArgoCD ApplicationSets + Git

### Key Principle
> After bootstrap completes, **NO MORE `terraform apply`** for applications.
> Everything uses GitOps via ArgoCD.

---

## 📦 Backstage Deployment Architecture

### 1. Helm Chart Strategy

Use **official Backstage Helm chart**:
```
Repository: https://backstage.github.io/charts
Chart: backstage
```

**Why Helm?**
- ✅ Official support from Backstage project
- ✅ Battle-tested defaults
- ✅ Easy customization via values.yaml
- ✅ ArgoCD native support

### 2. GitOps Repository Structure

```
id-platform/
├── argocd-apps/
│   ├── bootstrap/              # ArgoCD itself (already deployed)
│   │   └── argocd.yaml
│   └── platform/               # Platform applications
│       ├── backstage.yaml      # NEW
│       ├── crossplane.yaml     # NEW (depends on backstage)
│       └── observability/      # Future
│           ├── prometheus.yaml
│           └── grafana.yaml
├── platform-apps/              # Application configurations
│   ├── backstage/
│   │   ├── values-dev.yaml
│   │   ├── values-prod.yaml
│   │   └── app-config.yaml     # Backstage config
│   └── crossplane/
│       ├── values.yaml
│       └── providers/
│           └── aws-provider.yaml
```

### 3. ArgoCD Application Hierarchy

```
platform-apps (App-of-Apps)
├── backstage-app
│   ├── Sync Wave: 0
│   ├── Health Check: Required
│   └── Dependencies: None
├── crossplane-app
│   ├── Sync Wave: 10
│   ├── Health Check: Required
│   └── Dependencies: backstage-app
└── backstage-templates-app
    ├── Sync Wave: 20
    ├── Health Check: Optional
    └── Dependencies: crossplane-app
```

**Sync Waves ensure correct order:**
1. Backstage deploys first (wave 0)
2. Crossplane waits for Backstage to be healthy (wave 10)
3. Templates load after Crossplane is ready (wave 20)

---

## 🔐 Backstage Configuration

### Core Components

1. **Database**: PostgreSQL
   - **Option A**: AWS RDS (production)
   - **Option B**: In-cluster PostgreSQL (dev) ← **Start with this**

2. **Authentication**: AWS Cognito (same as ArgoCD)
   - Shared User Pool
   - Separate client ID
   - SSO experience across platform

3. **Networking**:
   - Uses **shared ALB** (IngressGroup: `dev-platform`)
   - Domain: `backstage.timedevops.click`
   - Same security architecture as ArgoCD

4. **Catalog**:
   - GitHub integration (read-only initially)
   - File-based catalog for bootstrap
   - Crossplane resources auto-discovery

---

## 📝 Installation Workflow

### Phase 1: Backstage Core

**Step 1: Prepare ArgoCD Application**

Create `argocd-apps/platform/backstage.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backstage
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://backstage.github.io/charts
    chart: backstage
    targetRevision: 1.x.x
    helm:
      releaseName: backstage
      valueFiles:
        - https://raw.githubusercontent.com/matheusmaais/id-platform/main/platform-apps/backstage/values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: backstage
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Step 2: Create Backstage Values**

Create `platform-apps/backstage/values-dev.yaml`:
```yaml
backstage:
  appConfig:
    app:
      title: Developer Platform
      baseUrl: https://backstage.timedevops.click
    
    backend:
      baseUrl: https://backstage.timedevops.click
      database:
        client: pg
        connection:
          host: ${POSTGRES_HOST}
          port: 5432
          user: ${POSTGRES_USER}
          password: ${POSTGRES_PASSWORD}
    
    auth:
      providers:
        oidc:
          development:
            metadataUrl: https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxx/.well-known/openid-configuration
            clientId: ${COGNITO_CLIENT_ID}
            clientSecret: ${COGNITO_CLIENT_SECRET}

  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/group.name: dev-platform
      alb.ingress.kubernetes.io/group.order: "200"
      alb.ingress.kubernetes.io/security-groups: <shared-alb-sg-id>
      alb.ingress.kubernetes.io/certificate-arn: <acm-cert-arn>
      external-dns.alpha.kubernetes.io/hostname: backstage.timedevops.click
    host: backstage.timedevops.click

postgresql:
  enabled: true  # In-cluster for dev
  postgresqlPassword: changeme  # Use sealed-secrets or External Secrets Operator
```

**Step 3: Makefile Target**

Add to `Makefile`:
```makefile
.PHONY: install-backstage
install-backstage: ## Install Backstage via ArgoCD
	@echo "=== Installing Backstage ==="
	kubectl apply -f argocd-apps/platform/backstage.yaml
	@echo "Waiting for Backstage to be healthy..."
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=300s
	@echo "✅ Backstage available at https://backstage.timedevops.click"
```

### Phase 2: Crossplane

**Step 1: Create Crossplane Application**

`argocd-apps/platform/crossplane.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crossplane
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # After Backstage
spec:
  project: default
  source:
    repoURL: https://charts.crossplane.io/stable
    chart: crossplane
    targetRevision: 1.x.x
  destination:
    server: https://kubernetes.default.svc
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Step 2: AWS Provider Configuration**

`platform-apps/crossplane/providers/aws-provider.yaml`:
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: xpkg.upbound.io/upbound/provider-aws:v0.x.x
---
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: IRSA  # Use IAM Roles for Service Accounts
```

**Step 3: Makefile Target**

```makefile
.PHONY: install-crossplane
install-crossplane: ## Install Crossplane via ArgoCD
	@echo "=== Installing Crossplane ==="
	kubectl apply -f argocd-apps/platform/crossplane.yaml
	@echo "Waiting for Crossplane to be healthy..."
	kubectl wait --for=condition=Ready pod -l app=crossplane -n crossplane-system --timeout=300s
	@echo "✅ Crossplane ready"
```

### Phase 3: Backstage Templates

**Step 1: Create Templates Repository Structure**

```
platform-apps/backstage/templates/
├── aws-ec2-instance/
│   ├── template.yaml          # Backstage template
│   └── skeleton/
│       ├── composition.yaml   # Crossplane composition
│       └── xrd.yaml          # Crossplane XRD
├── aws-rds-database/
│   └── ...
└── aws-s3-bucket/
    └── ...
```

**Step 2: Load Templates into Backstage**

Via `app-config.yaml`:
```yaml
catalog:
  locations:
    - type: url
      target: https://raw.githubusercontent.com/matheusmaais/id-platform/main/platform-apps/backstage/templates/*/template.yaml
      rules:
        - allow: [Template]
```

---

## 🔄 Complete Installation Flow

### Bootstrap (One-time, manual)

```bash
# 1. Infrastructure (Terraform)
make install        # VPC, EKS, Karpenter
make install-gitops # ArgoCD, LB Controller, External-DNS, Cognito

# 2. Verify bootstrap
make validate-gitops
```

### Platform Applications (GitOps)

```bash
# 3. Install Backstage
make install-backstage

# 4. Install Crossplane (automatic via sync-wave)
# Or manually: make install-crossplane

# 5. Verify platform
make validate-platform
```

### Post-Installation

```bash
# Access Backstage
open https://backstage.timedevops.click

# Login with Cognito
# Email: admin@timedevops.click
# Password: <your-password>
```

---

## 📚 Makefile Targets Summary

```makefile
# Bootstrap (Infra)
make install              # Install VPC + EKS
make install-gitops       # Install ArgoCD stack
make validate-gitops      # Validate bootstrap

# Platform (Apps via GitOps)
make install-backstage    # Deploy Backstage
make install-crossplane   # Deploy Crossplane
make validate-platform    # Validate platform apps

# Helpers
make get-credentials      # Show login credentials
make port-forward-backstage  # Local access for debugging
```

---

## 🎯 Benefits of This Approach

### 1. Clear Separation of Concerns
- **Bootstrap = Terraform** (infra that enables GitOps)
- **Platform = ArgoCD** (apps managed by GitOps)

### 2. Correct Dependency Management
- Sync waves enforce order
- Health checks prevent race conditions
- Automatic retries on transient failures

### 3. User-Friendly Experience
```bash
# Simple, predictable workflow
make install              # Once
make install-gitops       # Once
make install-backstage    # Once
# Done! Everything else is GitOps
```

### 4. GitOps Native
- All config in Git
- Declarative, auditable
- Self-healing
- No `kubectl apply` needed after bootstrap

### 5. Scalable
- Add new apps by creating ArgoCD Application YAML
- No Makefile changes needed
- Sync waves handle dependencies automatically

---

## 🚀 Next Steps

1. **Implement Backstage Application** (argocd-apps/platform/backstage.yaml)
2. **Create Backstage Values** (platform-apps/backstage/values-dev.yaml)
3. **Configure Cognito Client** for Backstage
4. **Update Makefile** with `install-backstage` target
5. **Test End-to-End** flow
6. **Implement Crossplane** following same pattern
7. **Create First Template** (EC2 instance)

---

## 📖 References

- [Backstage Official Helm Chart](https://github.com/backstage/charts)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Crossplane AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-aws)
- [AWS Prescriptive Guidance - Backstage](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/accelerate-mlops-with-backstage-and-sagemaker-templates.html)
