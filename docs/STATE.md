# PLATFORM CANONICAL STATE

## 🎯 FINAL OBJECTIVE
Deliver a deterministic ZERO-to-FULLY-USABLE internal platform where:

- Users authenticate once (SSO)
- RBAC is enforced consistently across tools
- Infrastructure is provisioned via Backstage (Crossplane)
- Applications are scaffolded, built, and deployed automatically
- All resources live in the same VPC as the EKS cluster
- Everything is reproducible via `make install` (no manual steps)

---

## 🧭 PHASES (LOCKED PLAN)

### Phase 0 — Bootstrap (CURRENT)
Goal:
- Deterministic rebuild from scratch
- No manual kubectl/debug steps
- `make destroy && make install` must succeed

Includes:
- VPC + EKS
- ArgoCD (GitOps, main branch only)
- Authentication (Cognito)
- Backstage (basic, infra catalog only)
- External Secrets
- Karpenter (minimal, no policies)

Excludes (explicitly):
- Kyverno policies
- Cost controls
- Advanced security hardening

Done when:
- All UIs accessible
- SSO works on ArgoCD + Backstage
- No ArgoCD sync errors
- No CrashLoop pods

---

### Phase 1 — Infra Self-Service (NEXT)
Goal:
- Users provision AWS infra via Backstage

Includes:
- Crossplane AWS provider
- EC2 / RDS / S3 via T-shirt sizes (S/M/L)
- For ec2,  create instance profile with SSM permissions, should be acessible trough ssm
  Security group should have ingress to port 80 and 443, ami should be the latest amazon linux available, no user input about this, user should input only instance name and Size (based on tshirt)
- Resources tagged and scoped per user
- RDS, should user only get the size based on tshirt, the engine (see availables) and instance name, security group should allow the engine connections in the current vpc
- Users can delete ONLY their own resources
- add the username as owner on tags, also create common tags for all resources

Constraints:
- Same VPC as EKS
- No user input for networking

---

### Phase 2 — App Scaffolding & Deploy
Goal:
- One-click app creation + deploy

Includes:
- GitHub repo creation
- Node.js hello-world app
- ECR repo creation
- GitHub Actions CI
- ArgoCD auto-tracking
- Ingress: <app>.<domain>

---

### Phase 3 — Hardening (LATER)
Includes:
- Cost governance
- Observability improvements


---

## 🧠 CURRENT STATE

**Repository:** id-platform (migrated from reference-implementation-aws on 2026-01-24)
Phase: Phase 2 — App Scaffolding & Deploy (IN PROGRESS)
Status: ✅ FOUNDATION COMPLETE / 🚧 APP PLATFORM IMPLEMENTATION
Branch: main

---

## 📋 PHASE 2 App Platform Status (2026-01-28)

### ✅ ARCHITECTURE - 100% DYNAMIC CONFIGURATION

**Principle**: Single Source of Truth → Zero Hardcoded Values

```
config/platform-params.yaml (committed)
         ↓
.env (gitignored, sensitive only)
         ↓
Terraform (platform-gitops)
         ↓
ConfigMap platform-params + Secrets
         ↓
Backstage + ArgoCD (env var substitution)
```

### ✅ COMPLETED COMPONENTS

#### 1. Dynamic Configuration System
- **File**: `config/platform-params.yaml` - Complete schema with GitHub config
- **ConfigMap**: All values derived (ECR_REGISTRY, domains, ALB config, etc)
- **Pattern**: `${ENV_VAR}` substitution everywhere (Backstage, templates, manifests)

**Key Environment Variables (platform-params ConfigMap)**:
```yaml
DOMAIN, AWS_REGION, AWS_ACCOUNT_ID, CLUSTER_NAME
BACKSTAGE_DOMAIN, ARGOCD_DOMAIN
ALB_GROUP_NAME, ALB_SECURITY_GROUP_ID, ACM_CERTIFICATE_ARN
GITHUB_ORG, GITHUB_APP_NAME, GITHUB_REPO_PREFIX, GITHUB_REPO_VISIBILITY, GITHUB_ACTIONS_ROLE_NAME
ECR_REGISTRY, PLATFORM_REPO_URL, PLATFORM_REPO_BRANCH
```

#### 2. GitHub Integration (Dual Auth Strategy)
- **Token Auth** (default): Uses `GITHUB_TOKEN` from `.env`
- **GitHub App** (optional): Uses `GITHUB_APP_*` if configured
- **Backstage**: Uses token auth by default (stable). GitHub App credentials remain supported in Terraform/Secrets for future enablement.
- **ArgoCD**: SCM Provider uses GitHub App **or** token dynamically (based on `github.scmAuth` + presence of `GITHUB_APP_*`)
- **Secret**: `backstage-github` contains both token + app credentials

#### 3. ArgoCD AppProject for Workloads
- **Terraform**: `terraform/platform-gitops/app-platform.tf` (`kubectl_manifest.apps_project`)
- **Name**: `apps`
- **Source Repos**: `https://github.com/matheusmaais/idp-*`
- **Destinations**: Namespaces `idp-*`
- **Resources**: Standard K8s + Ingress + HPA + ServiceMonitor
- **RBAC**: Developer (view/sync) + Admin (full control)

#### 4. ArgoCD ApplicationSet - Workload Auto-Discovery
- **Terraform**: `terraform/platform-gitops/app-platform.tf` (`kubectl_manifest.workloads_appset`)
- **Generator**: SCM Provider (GitHub org scan)
- **Filter**: Repos matching `^idp-.*` with `k8s/` directory
- **Auth**: GitHub App credentials (`github-app-credentials` secret)
- **Behavior**: Creates 1 Application per discovered repo
- **Namespace**: 1 namespace per app (`idp-<name>`)

#### 5. Backstage Template - Node.js App
- **Location**: `backstage-custom/templates/idp-nodejs-app/`
- **Language**: Node.js + Express
- **Features**:
  - Structured JSON logging
  - Prometheus metrics (`/metrics`)
  - Health checks (`/health`, `/ready`)
  - Graceful shutdown
  - Non-root user (1001)
  - Read-only root filesystem

**Template Parameters** (from `environment.parameters`):
```yaml
githubOrg, repoPrefix, repoVisibility, domain
albGroupName, albSecurityGroupId, acmCertificateArn
ecrRegistry, awsRegion, awsAccountId, githubActionsRoleName, clusterName
```

#### 6. Application Skeleton
**Files**:
- `src/index.js` - Express app with observability
- `package.json` - Dependencies (express, prom-client)
- `Dockerfile` - Multi-stage, hardened, ARM64-compatible
- `k8s/deployment.yaml` - Deployment with probes + resources
- `k8s/service.yaml` - ClusterIP service
- `k8s/ingress.yaml` - Conditional (if `exposePublic`)
- `.github/workflows/ci.yml` - CI/CD pipeline
- `catalog-info.yaml` - Backstage component metadata
- `README.md` - Documentation

#### 7. CI/CD Pipeline (GitHub Actions)
- **Auth**: OIDC (no long-lived credentials)
- **ECR**: Creates repo if not exists (idempotent)
- **Build**: Multi-platform Docker build with cache
- **Push**: Tags: `${sha}` + `latest`
- **Deploy**: Updates `k8s/deployment.yaml` with new image tag
- **Commit**: Pushes manifest update (`[skip ci]`)
- **ArgoCD**: Auto-syncs on Git change

#### 8. Ingress Strategy (Shared ALB)
- **Group**: `${environment}-platform` (e.g., `dev-platform`)
- **Order**: ArgoCD=100, Backstage=200, Apps=1000
- **TLS**: ACM certificate (wildcard)
- **DNS**: External-DNS creates Route53 records
- **Security**: Shared SG from EKS module

#### 9. Makefile Automation
**New Targets**:
```bash
make install-app-platform    # Deploy AppProject + Workloads ApplicationSet
make validate-app-platform   # Validate app platform components
```

### 🚧 PENDING TASKS

1. **GitHub OIDC Provider for AWS** (manual, pre-requisite)
   - Create OIDC provider: `token.actions.githubusercontent.com`
   - IAM Role: `github-actions-ecr-push`
   - Trust policy for `matheusmaais/*` repos
   - Permissions: ECR push + create repo

2. **Deploy App Platform Components**:
   ```bash
   make apply-gitops           # Update ConfigMap with new vars
   make install-app-platform   # Deploy AppProject + ApplicationSet
   make validate-app-platform  # Verify components
   ```

3. **Test End-to-End Flow**:
   - Access Backstage: `https://backstage.timedevops.click`
   - Create App via template (e.g., `hello`)
   - Verify repo created: `matheusmaais/idp-hello`
   - Watch CI pipeline execute
   - Verify ArgoCD discovers app
   - Check deployment: `kubectl get app idp-hello -n argocd`
   - Test endpoint (if public): `https://hello.timedevops.click`

### 📊 CONFIGURATION SCHEMA

#### config/platform-params.yaml
```yaml
repository:
  org: matheusmaais
  name: id-platform
  branch: main

github:
  org: matheusmaais
  appName: daredelabs-idp-backstage
  appRepoPrefix: "idp-"
  appRepoVisibility: private
  scmAuth: token  # token | app
  actionsRoleName: github-actions-ecr-push

infrastructure:
  domain: timedevops.click
  clusterName: platform-eks
  awsRegion: us-east-1
  awsProfile: darede
  environment: dev

identity:
  cognitoAdminEmail: admin@timedevops.click
  allowedEmailDomains: []
```

#### .env (sensitive, gitignored)
```bash
GITHUB_TOKEN=ghp_xxx
COGNITO_ADMIN_TEMP_PASSWORD=xxx

# Optional (if github.scmAuth=app)
GITHUB_APP_ID=
GITHUB_APP_INSTALLATION_ID=
GITHUB_APP_PRIVATE_KEY=
```

### 🎯 VALIDATION COMMANDS

```bash
# 1. Verify Terraform ConfigMap
kubectl get configmap platform-params -n argocd -o yaml | grep -E 'GITHUB|ECR'

# 2. Verify Secrets
kubectl get secret backstage-github -n backstage -o yaml

# 3. Verify AppProject
kubectl get appproject apps -n argocd

# 4. Verify ApplicationSet
kubectl get applicationset workloads -n argocd

# 5. Monitor workload discovery
kubectl get applications -n argocd -l platform.darede.io/workload=true -w

# 6. Test Backstage template
# UI → Create Component → Node.js App → Fill params → Create

# 7. Verify auto-discovery
kubectl get app idp-<name> -n argocd
```

### 📝 ARCHITECTURE DECISIONS

**ADR-005: 100% Dynamic Configuration**
- All values from `config/platform-params.yaml` or data sources
- No hardcoded domains, orgs, ARNs, or IDs
- Env var substitution: `${VAR}` pattern everywhere
- Single edit point for org migration

**ADR-006: Dual GitHub Auth Strategy**
- Default: Token (simpler, works everywhere)
- Optional: GitHub App (better security, rate limits)
- Platform supports both simultaneously
- ConfigMap flag: `GITHUB_SCM_AUTH=token|app`

**ADR-007: One Namespace Per App**
- Pattern: `idp-<app-name>` → namespace `idp-<app-name>`
- Isolation + observability
- AppProject restricts to `idp-*` namespaces

**ADR-008: SCM Provider for Discovery**
- ArgoCD scans GitHub org for `idp-*` repos
- Requires `k8s/` directory (validation)
- Auto-creates Application on discovery
- Removes Application when repo deleted

---

## 📋 PHASE 0 GitOps Auth Foundation Status (2026-01-27)

### ✅ COMPLETED

#### 1. Cognito Foundation
- User Pool: `us-east-1_75myDdDAc` (platform-eks-user-pool)
- OAuth Domain: `idp-poc-darede`
- ArgoCD Client: `ln4nvdorop4i2rh6isgbi1m0k`
- Backstage Client: `oseg1vj7ai3usqafrjtpor4e7`
- Group: `argocd-admins` created
- Admin User: `admin@timedevops.click` (CONFIRMED) in `argocd-admins` group
- **Pre-Token Generation Lambda**: Injects `cognito:groups` into ID token

#### 2. AWS Load Balancer Controller
- Version: v2.17.1
- IRSA configured
- 2 replicas running
- Health: ✅ All targets healthy

#### 3. Shared ALB (IngressGroup)
- ALB Name: `k8s-devplatform-8c400353ac`
- Group Name: `dev-platform`
- Security Group: `sg-0e4f3823de6ccc51b`
- State: Active

#### 4. External-DNS
- Version: v0.20.0
- IRSA configured
- Route53 zone: `Z09212782MXWNY5EYNICO`
- Policy: `upsert-only`

#### 5. ArgoCD with Cognito OIDC
- Version: v3.2.6 (Chart 9.3.5)
- URL: https://argocd.timedevops.click ✅ HTTP 200
- Dex connector: Cognito OIDC ✅
- RBAC: `g, argocd-admins, role:admin` + email fallback
- Admin login: Working via admin password
- SSO login: Working (user `admin@timedevops.click` authenticated successfully)

### ✅ RECENTLY COMPLETED (2026-01-27)

#### 6. Backstage with Cognito OIDC
- **Status**: ✅ DEPLOYED & HEALTHY
- **URL**: https://backstage.timedevops.click
- **Fix Applied**: Changed `${BACKSTAGE_DOMAIN:+https://${BACKSTAGE_DOMAIN}}` to `https://${BACKSTAGE_DOMAIN}`
- **Commit**: 9cd8984 - "fix(backstage): remove bash-style URL syntax"
- **Health**: Pod running 1/1, HTTP 200 responses
- **Ingress**: Using shared ALB (dev-platform IngressGroup)

### 🚧 BLOCKED - TECHNICAL LIMITATION

#### Backstage OIDC Authentication  
- **Status**: ❌ BLOCKED - Incompatible package versions
- **Root Cause #1**: Official Backstage image does NOT include auth provider plugins (RESOLVED - built custom image)
- **Root Cause #2**: Package version incompatibility - `@backstage/backend-defaults@0.6.0` does NOT provide required core services
- **Technical Details**:
  - Custom image built successfully with OIDC plugin
  - Image: `948881762705.dkr.ecr.us-east-1.amazonaws.com/backstage-platform:20260127-160113`
  - Platform: ARM64 (matches t4g nodes)
  - **BLOCKER**: Catalog plugin requires `core.permissionsRegistry` and `core.auditor` services
  - These services are NOT provided by `@backstage/backend-defaults@^0.6.0`
  - Upgrading to newer versions causes other package incompatibilities
  - Error: `Service or extension point dependencies of plugin 'catalog' are missing`

**ATTEMPTS MADE:**
1. ✅ Built custom image with OIDC plugin
2. ✅ Fixed ARM64 architecture (exec format error)
3. ✅ Added entrypoint script for bundle extraction
4. ✅ Configured Helm command override
5. ❌ **BLOCKED**: Package version incompatibility

**TECHNICAL BLOCKER:**
```
Error: Service or extension point dependencies of plugin 'catalog' are missing  
Missing: serviceRef{core.permissionsRegistry}, serviceRef{core.auditor}

Root Cause:
- @backstage/backend-defaults@0.6.0 does NOT provide these core services
- Newer versions (0.7.x+) provide them BUT cause other package conflicts
- Backstage ecosystem has breaking changes between minor versions
- No stable version set that works with all plugins
```

**RESOLUTION OPTIONS:**

**A) Use Backstage without Catalog (Auth Only)**
```
Pros:
- OIDC authentication works
- Meets SSO requirement
- Simpler backend

Cons:
- No software catalog
- Limited Backstage functionality
```

**B) Use Latest Backstage Versions (All Latest)**
```
Pros:
- All features work
- Modern architecture

Cons:
- Requires updating ALL packages to latest
- May introduce other incompatibilities
- Longer build/test cycle
```

**C) Defer Backstage to Phase 1**
```
Pros:
- ArgoCD OIDC already working ✅
- Can focus on infrastructure provisioning
- Revisit Backstage with stable versions

Cons:
- Phase 0 incomplete
- No IDP UI for now
```

**RECOMMENDATION:** Option C - Defer Backstage to Phase 1
- ArgoCD provides GitOps UI with OIDC ✅
- Can proceed with Crossplane (infra provisioning)
- Backstage can be added later with stable versions

**DECISION REQUIRED:** Which option to proceed?

### 🚧 IN PROGRESS

#### 7. EBS CSI Driver IRSA
- **Status**: Controller CrashLoopBackOff (using node role, lacks permissions)
- **Root Cause**: Missing IRSA configuration
- **Impact**: PostgreSQL using ephemeral storage (acceptable for Phase 0 dev)
- **Fix Required**: Create IRSA for EBS CSI driver with required EC2 permissions
- **Priority**: LOW (Phase 0 allows ephemeral storage for dev)

### 📝 Pending Tasks

1. ✅ ~~Fix Backstage app-config URL syntax~~ (DONE)
2. Validate Backstage OIDC login end-to-end (Cognito SSO)
3. Create EBS CSI Driver IRSA for persistent volumes (Phase 0 optional)
4. Test end-to-end platform flow (ArgoCD + Backstage SSO)

---

### Completed Components

- [x] **VPC** (terraform/vpc)
  - 3 AZs with public + private subnets ✓
  - Single NAT Gateway (cost-optimized) ✓
  - Subnets tagged for Karpenter discovery ✓
  - Remote state: `s3://poc-idp-tfstate/vpc/terraform.tfstate`

- [x] **EKS Cluster** (terraform/eks)
  - EKS 1.31 with IRSA enabled ✓
  - Bootstrap node group (t4g.medium ARM64, AL2023) ✓
  - CoreDNS with tolerations for bootstrap node ✓
  - Karpenter IAM role (IRSA) ✓
  - Cluster creator admin permissions ✓
  - Remote state: `s3://poc-idp-tfstate/eks/terraform.tfstate`

- [x] **Karpenter** (terraform/addons)
  - Karpenter v1.8.6 via Helm ✓
  - EC2NodeClass (AL2023, ARM64) ✓
  - NodePool (Spot, t4g instances) ✓
  - Consolidation policy: WhenEmpty ✓
  - Node provisioning: TESTED & WORKING ✓
  - Remote state: `s3://poc-idp-tfstate/addons/terraform.tfstate`

- [x] **Karpenter** (terraform/addons)
  - Karpenter v1.8.6 via Helm ✓
  - EC2NodeClass (AL2023, ARM64) ✓
  - NodePool (Spot, t4g instances) ✓
  - Consolidation policy: WhenEmpty ✓
  - Node provisioning: TESTED & WORKING ✓
  - Remote state: `s3://poc-idp-tfstate/addons/terraform.tfstate`

- [x] **Platform GitOps** (terraform/platform-gitops)
  - Cognito User Pool with argocd-admins group ✓
  - AWS Load Balancer Controller v1.17.1 (IRSA) ✓
  - ArgoCD v9.3.5 with Cognito SSO ✓
  - External-DNS v1.20.0 (txt registry) ✓
  - App-of-apps pattern configured ✓
  - Remote state: `s3://poc-idp-tfstate/platform-gitops/terraform.tfstate`

- [x] **Makefile Automation**
  - `make install` — Deploy VPC → EKS → Addons → GitOps ✓
  - `make destroy` — Destroy GitOps → Addons → EKS → VPC ✓
  - `make destroy-cluster` — Destroy only EKS + Addons (keep VPC) ✓
  - `make validate` — Check cluster health ✓
  - `make validate-gitops` — Check GitOps components ✓
  - `make test-karpenter` — Test node provisioning ✓

### Validation Results (2026-01-23)

```
✅ VPC: 3 AZs, NAT Gateway, subnets tagged
✅ EKS: Cluster ACTIVE, API accessible
✅ Bootstrap Node: Running, CoreDNS scheduled
✅ Karpenter: Controller running, pods healthy
✅ Node Provisioning: Spot t4g.small launched successfully
```

### Phase 0 - GitOps Implementation Status
- [x] ✅ Cognito User Pool with OAuth domain
- [x] ✅ AWS Load Balancer Controller (ALB ingress)
- [x] ✅ ArgoCD with Cognito SSO (Dex OIDC)
- [x] ✅ External-DNS with Route53 automation
- [x] ✅ App-of-apps pattern configured
- [ ] 🚧 Deploy and validate (pending infrastructure apply)

**Access:** https://argocd.timedevops.click (after deployment)

---

## 🔒 DECISIONS (DO NOT REVISIT)

- Auth: Amazon Cognito (no Keycloak)
- GitOps: ArgoCD, main branch only
- Ingress: AWS Load Balancer Controller (ALB) — ingress-nginx deferred
- DNS: External-DNS with txt registry and txtOwnerId
- RBAC: Cognito groups (`argocd-admins`) mapped to ArgoCD roles
- Infra provisioning: Crossplane
- Secrets: AWS Secrets Manager + External Secrets
- Rebuild strategy: Destroy first, then install

---

## 🚫 OUT OF SCOPE (FOR NOW)

- Kyverno policies
- Multi-cluster
- Production HA
- Cost optimization

---

## 📌 RULES FOR AGENTS

- Read this file first
- Do not redesign phases
- Do not reintroduce Keycloak
- Commit everything (no local-only fixes)
- Update this file after each completed task
- All execution context must be written here after each major step
- If context usage exceeds ~70%, rely ONLY on this file and stop using chat memory

---

## 🔄 RECENT CHANGES (Latest First)

### 2026-01-28: ArgoCD SSO quebrado por domínio Cognito “stale” (Dex cache) ✅
**Status:** ✅ CORRIGIDO NO CLUSTER / ✅ PREVENÇÃO ADICIONADA NO CÓDIGO

**Sintoma:**
- ArgoCD redirecionava para um Hosted UI domain **antigo/inexistente** (ex.: `idp-poc-darede.auth.us-east-1.amazoncognito.com`) e o login não prosseguia.

**Root cause (Causa raiz):**
- O Cognito User Pool Domain foi alterado (ex.: agora `idp-dev-platform`), e o **Dex manteve em cache** o `authorization_endpoint` antigo do discovery OIDC.
- Resultado: `/auth/login` → `/api/dex/auth/cognito` gerava URL para o domínio antigo, que não resolvia mais.

**Fix (cluster):**
- Reinício do Dex para recarregar OIDC discovery:
```bash
kubectl rollout restart deploy/argocd-dex-server -n argocd
kubectl rollout status deploy/argocd-dex-server -n argocd --timeout=180s
```

**Validação:**
```bash
curl -sS -D- -o /dev/null https://argocd.<domain>/api/dex/auth/cognito | rg -i '^location:'
# Esperado: Location aponta para https://idp-dev-platform.auth.<region>.amazoncognito.com/oauth2/authorize...
```

**Prevenção (IaC / dinâmico):**
- Adicionado `dex.podAnnotations` em `terraform/platform-gitops/argocd.tf` com valor derivado de `local.cognito.oauth_domain_prefix`,
  garantindo rollout automático do Dex quando o domínio Cognito mudar.

### 2026-01-28: ArgoCD 404 ao clicar para login (deep-links tipo `/login`) ✅
**Status:** ✅ ROOT CAUSE IDENTIFICADA / ✅ DOCUMENTADO (sem mudança estrutural)

**Sintoma:**
- Ao tentar autenticar no ArgoCD, o navegador cai em **HTTP 404**, geralmente quando abre paths como `https://argocd.<domain>/login`.

**Evidência (reproduzível):**
```bash
curl -I https://argocd.<domain>/                 # 200 (UI entrypoint)
curl -I https://argocd.<domain>/login            # 404 (deep-link não servido)
curl -I https://argocd.<domain>/applications     # 404 (mesma classe de deep-link)

# Endpoint correto para iniciar autenticação (SSO/Dex):
curl -I https://argocd.<domain>/auth/login       # 303 → /api/dex/auth?... (OK)
```

**Root cause (Causa raiz):**
- O `argocd-server` (v3.2.6) responde UI em `/` e expõe autenticação em `/auth/*` e `/api/*`,
  mas **não atende deep-links** do UI via paths como `/login`, `/applications`, etc (retorna 404).
- Portanto, qualquer link/redirect “na aplicação” que aponte para `.../login` vai falhar.

**Correção / Mitigação (compatível com configuração dinâmica):**
- Use como URL canônica **sempre**: `https://argocd.<domain>/` (sem path hardcoded).
- Para login SSO: `https://argocd.<domain>/auth/login` (Dex → Cognito).
- Onde houver link para ArgoCD (docs/templates/botões), garantir que ele use apenas `argocd.<domain>` derivado de
  `config/platform-params.yaml` (não usar `/login`).

**Validação (mínima, sem UI):**
```bash
curl -sS -D- -o /dev/null https://argocd.<domain>/auth/login | head -n 20
# Esperado: HTTP 303 + Location: .../api/dex/auth?...
```

### 2026-01-28: Backstage SSO stabilized end-to-end (no guest, no catalog users required) ✅
**Status:** ✅ CLUSTER COMPLETE / ✅ GITOPS RECONCILED (ArgoCD `Synced/Healthy`)

**Problems observed (cluster):**
- Backstage UI still showed **Guest** sign-in even with OIDC configured.
- Cognito OIDC sign-in failed with:
  - `authentication requires session support` (missing `auth.session.secret`)
  - `Failed to sign-in, unable to resolve user identity` (resolver required catalog `User` entities)
- Some values/config had drifted via manual steps; needed to be fully declarative for GitOps.

**Root Causes:**
- Frontend `SignInPage` was hardcoded to `providers={['guest']}` (UI-level config).
- Backstage OIDC provider requires `auth.session.secret`.
- Built-in resolver `emailMatchingUserEntityProfileEmail` requires `User` entities in the catalog.
- Domain-related auth policy must not be hardcoded (domain can change); it must be file-driven.

**Fix (GitOps + file-driven):**
- **Frontend**: removed hardcoded guest provider and registered a Cognito-branded OIDC provider.
- **Backend**:
  - Added a custom OIDC `signInResolver` that **issues tokens without catalog users** (Phase 0),
    while enforcing allowed domains from config.
- **Dynamic domain allow-list (file-driven)**:
  - Terraform `platform-gitops` now publishes `AUTH_ALLOWED_EMAIL_DOMAINS` in the `platform-params` ConfigMap.
  - Backstage reads `identity.allowedEmailDomains: ${AUTH_ALLOWED_EMAIL_DOMAINS}` from `platform-apps/backstage/values.yaml`.
- **Applied via**: `make apply-gitops` (Terraform) + image push + ArgoCD reconcile.

**Current pinned image (cluster):**
- `948881762705.dkr.ecr.us-east-1.amazonaws.com/backstage-platform:20260128-backstage-v1.47.1-authz`

**Validation (cluster):**
```bash
kubectl get application backstage -n argocd
kubectl get pods -n backstage -l app.kubernetes.io/name=backstage

# ConfigMap shows allowed domains coming from Terraform/platform-params
kubectl get configmap -n backstage platform-params -o jsonpath='{.data.AUTH_ALLOWED_EMAIL_DOMAINS}{"\n"}'

# OIDC start endpoint redirects to Cognito (HTTP 302)
curl -sSI "https://backstage.timedevops.click/api/auth/oidc/start?env=development" | head -n 8
```

### 2026-01-27: Backstage dependency hell resolved (Backstage OSS v1.47.1) ✅
**Status:** ✅ LOCAL COMPLETE / 🚧 READY FOR CLUSTER DEPLOY (image push + ArgoCD sync pending)

**Problem:**
- Backstage custom image failed at runtime with missing core services:
  - `Missing: serviceRef{core.permissionsRegistry}, serviceRef{core.auditor}`

**Root Cause:**
- `@backstage/*` dependencies were set to `"latest"`, causing a **mismatched set of packages**.
- In particular, `@backstage/backend-defaults` was effectively behind the plugin set, so required core services weren’t registered for plugins like `catalog`.

**Fix (Approach A — regenerate deterministically):**
1. **Confirmed latest Backstage OSS release** via GitHub Releases: `v1.47.1`
2. **Regenerated the Backstage app** inside `backstage-custom/` using a pinned create-app:
   - `npx @backstage/create-app@0.7.8` (no `@latest`)
3. **Applied minimal customizations for Cognito OIDC (official module):**
   - Added `@backstage/plugin-auth-backend-module-oidc-provider@0.4.11`
   - Removed guest provider module from backend registration
4. **Pinned all `@backstage/*` package versions** (removed `^`) to prevent drift.
5. **Hardened Docker image (ARM64) with multi-stage build**:
   - `backstage-custom/packages/backend/Dockerfile` now builds bundle + production deps in builder stage and runs as non-root.
   - Fixed `backstage-custom/.dockerignore` to include sources (required for multi-stage build).

**Final Versions (pins):**
- Backstage OSS release: `v1.47.1`
- `@backstage/create-app`: `0.7.8`
- `@backstage/cli`: `0.35.2`
- `@backstage/backend-defaults`: `0.15.0` (used by regenerated app)
- `@backstage/plugin-auth-backend-module-oidc-provider`: `0.4.11`
- Backstage image tag (Helm): `20260127-backstage-v1.47.1`

**Validation (local):**
```bash
cd backstage-custom
corepack enable

# Deterministic deps + build
YARN_ENABLE_IMMUTABLE_INSTALLS=false corepack yarn install
corepack yarn install --immutable
corepack yarn tsc
corepack yarn build:backend

# ARM64 container build (hardened)
docker buildx build --platform linux/arm64 \
  -f packages/backend/Dockerfile \
  -t backstage-platform:local --load .

# Container boots and healthcheck is OK
docker run -d --rm -p 7007:7007 --name backstage-local backstage-platform:local
sleep 8
curl -fsS http://localhost:7007/healthcheck
docker rm -f backstage-local
```

**Next (cluster / GitOps):**
```bash
# Build and push pinned image tag (reads tag from platform-apps/backstage/values.yaml)
make validate-backstage
make push-backstage-image

# Sync and watch rollout
argocd app sync backstage
kubectl get pods -n backstage -w
kubectl logs -n backstage deploy/backstage -f
```

**Refs (source of truth):**
- Backstage OSS release `v1.47.1`: [Backstage `v1.47.1` release](https://github.com/backstage/backstage/releases/tag/v1.47.1)
- Retrieved via: `gh api repos/backstage/backstage/releases/latest`

### 2026-01-27: Backstage OIDC Authentication Fixed ✅
**Status:** ✅ COMPLETE (Backstage with Cognito OIDC working)

**Problem:**
- Backstage accessible without login (guest mode)
- Catalog API returning 401 errors
- Missing COGNITO_ISSUER in Kubernetes secret
- Missing signInPage configuration

**Root Causes:**
1. Backstage defaulting to guest authentication
2. `backstage-cognito` secret missing `COGNITO_ISSUER` field
3. No `signInPage` configuration to force OIDC login

**Solutions Applied:**
1. **Added `signInPage: oidc` to app-config:**
```yaml
# platform-apps/backstage/values.yaml
appConfig:
  signInPage: oidc  # Force OIDC login, disable guest
```

2. **Added COGNITO_ISSUER to Terraform secret:**
```hcl
# terraform/platform-gitops/secrets.tf
data = {
  COGNITO_CLIENT_ID     = aws_cognito_user_pool_client.backstage.id
  COGNITO_CLIENT_SECRET = aws_cognito_user_pool_client.backstage.client_secret
  COGNITO_ISSUER        = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}
```

3. **Manually patched secret in cluster:**
```bash
kubectl patch secret backstage-cognito -n backstage \
  --type='json' \
  -p='[{"op": "add", "path": "/data/COGNITO_ISSUER", "value": "..."}]'
```

**Validation:**
- ✅ Backstage pod restarted successfully
- ✅ All three Cognito environment variables present
- ✅ No more 401 errors in logs
- ✅ OIDC authentication enabled

**Next:** Test end-to-end Cognito login flow

**Commits:** 
- 356814b - "fix(backstage): enable OIDC sign-in page"
- 5ceb601 - "fix(terraform): add COGNITO_ISSUER to Backstage secret"

---

### 2026-01-27: Backstage ArgoCD Sync Fixed ✅
**Status:** ✅ COMPLETE (Backstage Synced and Healthy)

**Problem:**
- Backstage Application showing `OutOfSync` status despite being healthy
- Root cause: PostgreSQL Helm chart generates random `postgres-password` on each sync
- This caused perpetual drift detection in ArgoCD

**Solution:**
- Added `ignoreDifferences` configuration to ApplicationSet:
```yaml
ignoreDifferences:
  - kind: Secret
    name: backstage-postgresql
    jsonPointers:
      - /data/postgres-password
```
- Recreated ApplicationSet to apply new configuration
- Commit: 099265b

**Validation:**
```bash
kubectl get application backstage -n argocd
# NAME        SYNC STATUS   HEALTH STATUS
# backstage   Synced        Healthy
```

**Result:**
- ✅ Backstage Application now shows Synced status
- ✅ No more perpetual OutOfSync alerts
- ✅ ArgoCD properly ignores Helm-generated password drift
- ✅ Best practice for Helm-managed secrets applied

---

### 2026-01-27: Backstage Deployment Fixed ✅
**Status:** ✅ COMPLETE (Backstage healthy and accessible)

**Problem:**
- Backstage pod failing readiness probes with `TypeError: Invalid URL`
- Error: `input: "${BACKSTAGE_DOMAIN:+https://backstage.timedevops.click}"`
- Backstage doesn't support bash-style conditional syntax `${VAR:+value}`

**Solution:**
- Changed `platform-apps/backstage/values.yaml`:
  - `baseUrl: ${BACKSTAGE_DOMAIN:+https://${BACKSTAGE_DOMAIN}}` → `baseUrl: https://${BACKSTAGE_DOMAIN}`
  - Applied same fix to `backend.baseUrl`
- Committed and pushed to main branch (commit 9cd8984)
- ArgoCD auto-synced and redeployed Backstage

**Validation:**
```bash
# Application status
kubectl get application backstage -n argocd
# NAME        SYNC STATUS   HEALTH STATUS
# backstage   Synced        Healthy

# Pod status
kubectl get pods -n backstage
# NAME                        READY   STATUS    RESTARTS   AGE
# backstage-c6b4b58b4-bt5qg   1/1     Running   0          5m

# HTTP check
curl -I https://backstage.timedevops.click
# HTTP/2 200
```

**Result:**
- ✅ Backstage accessible at https://backstage.timedevops.click
- ✅ Pod healthy (1/1 Running)
- ✅ Readiness probes passing
- ✅ Using shared ALB (dev-platform IngressGroup)
- ✅ PostgreSQL running (ephemeral storage, acceptable for Phase 0)

**Next:** Validate Cognito SSO login for both ArgoCD and Backstage

---

### 2026-01-27: Configuration Sources & Where to Edit ✅
**Status:** ✅ DOCUMENTED (single source of truth, no duplication)

**Rule:**  
- **Sensitive only** in `.env`  
- **Everything else** in `config/platform-params.yaml`  
- **Terraform locals** read from `config/platform-params.yaml` (no hardcoded values)

**Files to edit (ONLY these):**
- `config/platform-params.yaml` (**non-sensitive**)
  - `repository.url`
  - `infrastructure.domain`
  - `infrastructure.backstageDomain`
  - `infrastructure.albGroupName`
  - `infrastructure.clusterName`
  - `infrastructure.awsRegion`
  - `infrastructure.awsProfile`
  - `infrastructure.environment`
  - `identity.cognitoAdminEmail`
  - `tags.*`
- `.env` (**sensitive only**)
  - `GITHUB_TOKEN`
  - `COGNITO_ADMIN_TEMP_PASSWORD`

**What NOT to edit manually:**
- `terraform/platform-gitops/locals.tf` (reads config file)
- `terraform/platform-gitops/*.tf` values (derived from locals)
- Makefile variables (reads config/.env)

**Why:**  
Avoid duplicated values across `.env`, `locals`, and Terraform code.

### 2026-01-26: GitOps Apply ✅
**Status:** ✅ DEPLOYED (kubectl wait needs local kubeconfig)

**Apply Result:**
- Terraform apply OK
- ArgoCD, AWS LB Controller, External-DNS, Cognito created
- App-of-apps (`platform-apps`) created

**Outputs (key):**
- ArgoCD: `https://argocd.timedevops.click`
- Cognito Issuer: `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_hxay4Xx1g`

**Post-apply issue:**
- `kubectl wait` failed locally due to missing kubeconfig:
  - `lookup ...eks.amazonaws.com: no such host`

**Fix:**
- `aws eks update-kubeconfig --region us-east-1 --name platform-eks`
- Then: `make validate-gitops`

### 2026-01-26: GitOps Apply Fix (Cognito MFA) ✅
**Status:** ✅ READY (apply retry required)

**Issue:**
- Cognito User Pool creation failed with `Invalid MFA configuration` when `mfa_configuration = OPTIONAL` without a configured MFA method.

**Fix Applied:**
- Enabled software token MFA configuration:
  - `software_token_mfa_configuration { enabled = true }`

**Next Command:**
- `make apply-gitops` (or `AWS_PROFILE=your-profile make apply-gitops`)

### 2026-01-23: GitOps Plan Fixes + Provider Upgrade ✅
**Status:** ✅ PLAN OK

**What Changed:**
- Upgraded Terraform providers via `terraform init -upgrade` (lockfile updated)
- Helm provider v3 syntax fixed (`kubernetes = { ... }`)
- IRSA assume-role now uses EKS data source OIDC issuer
- ALB SG annotation uses EKS data source `vpc_config` SG ID
- ACM lookup now matches primary domain `timedevops.click` (SAN includes wildcard)

**Commands:**
- Init/upgrade: `cd terraform/platform-gitops && terraform init -upgrade -reconfigure`
- Plan: `terraform plan`

### 2026-01-24: Phase 0 GitOps Implementation ✅
**Status:** ✅ CODE COMPLETE (awaiting deployment)

**What Changed:**
- Created `terraform/platform-gitops/` stack with 11 Terraform files
- Implemented Cognito User Pool with OAuth and OIDC
- Configured ArgoCD with Cognito SSO via Dex
- Deployed AWS Load Balancer Controller (IRSA)
- Configured External-DNS with Route53 automation
- Created app-of-apps pattern structure

**Terraform Stack (`terraform/platform-gitops/`):**
```
├── providers.tf          # Backend S3, AWS/K8s/Helm providers
├── data-sources.tf       # EKS, Route53, ACM lookups
├── locals.tf             # Domain config, chart versions
├── variables.tf          # region, cluster_name
├── cognito.tf            # User Pool + client + groups
├── aws-lb-controller.tf  # IRSA + Helm v1.17.1
├── argocd.tf             # Helm v9.3.5 + OIDC + RBAC
├── external-dns.tf       # IRSA + Helm v1.20.0
├── argocd-apps.tf        # App-of-apps CRD
├── outputs.tf            # URLs, IAM ARNs
└── README.md             # Usage guide
```

**Component Versions:**
- AWS Load Balancer Controller: Chart 1.17.1 (9 Jan 2026)
- ArgoCD: Chart 9.3.5 (23 Jan 2026) → App v3.2.6
- External-DNS: Chart 1.20.0 (2 Jan 2026) → App v0.20.0

**Key Configurations:**
- Domain: `timedevops.click` (via data source lookup)
- ACM cert: `*.timedevops.click` (via data source)
- Cognito OAuth domain: `idp-poc-darede`
- ArgoCD URL: `https://argocd.timedevops.click`
- OIDC issuer: Cognito User Pool
- RBAC: `argocd-admins` → `role:admin`, default: `role:readonly`
- External-DNS registry: `txt` with `txtOwnerId` = cluster name
- External-DNS policy: `upsert-only` (safe mode)

**Makefile Updates:**
- `make apply-gitops` — Deploy GitOps stack
- `make destroy-gitops` — Destroy GitOps stack (apps first)
- `make validate-gitops` — Validate all components
- `make install` — Now includes GitOps (VPC → EKS → Addons → GitOps)
- `make destroy` — Proper order (GitOps → Addons → EKS → VPC)

**Directory Structure:**
- `argocd-apps/platform/` — Created (ready for apps)
- `docs/PHASE-0-GITOPS.md` — Complete implementation guide

**State Management:**
- Backend: `s3://poc-idp-tfstate/platform-gitops/terraform.tfstate`
- Isolated from other stacks

**Next Steps:**
1. Deploy: `make apply-gitops`
2. Create ALB IAM policy (one-time setup)
3. Wait for ALB + DNS propagation (5-10 min)
4. Create admin user in Cognito
5. Test SSO: https://argocd.timedevops.click
6. Validate end-to-end flow
7. Update STATE.md with validation results

---

### 2026-01-24: Repository Migration to id-platform ✅
**Status:** ✅ COMPLETE

**What Changed:**
- Created new repository: `id-platform` (clean history)
- Migrated all working infrastructure code:
  - `terraform/vpc` - VPC stack
  - `terraform/eks` - EKS cluster stack
  - `terraform/addons` - Karpenter stack
  - `docs/` - Documentation
  - `Makefile` - Automation
- Cleaned temporary files (.terraform, *.tfstate)
- Updated STATE.md with repository name
- Created comprehensive README.md

**Repository:** https://github.com/matheusmaais/id-platform

**Why:**
- Fresh start with clean git history
- Better naming (id-platform vs reference-implementation-aws)
- Preparation for GitOps stack implementation

**Old Repository:**
- `reference-implementation-aws` remains active for reference
- Will be archived after GitOps implementation is validated

**Branch:** `platform-gitops-implementation` (working branch)

---

### 2026-01-23: Infrastructure Fully Functional ✅
**Status:** ✅ COMPLETE

**Architecture (3 Terraform Stacks):**
```
terraform/vpc    → VPC, Subnets, NAT Gateway
terraform/eks    → EKS Cluster, Bootstrap Node Group, Karpenter IAM
terraform/addons → Karpenter Helm, EC2NodeClass, NodePool
```

**Key Configurations:**

| Component | Configuration |
|-----------|---------------|
| EKS | v1.31, IRSA enabled, cluster creator admin |
| Bootstrap Node | AL2023_ARM_64_STANDARD, t4g.medium, tainted |
| CoreDNS | Tolerations for bootstrap node taint |
| Karpenter | v1.8.6, IRSA, ECR public auth |
| EC2NodeClass | AL2023, ARM64, Spot |
| NodePool | t4g instances, WhenEmpty consolidation |

**Files Structure:**
```
terraform/
├── vpc/
│   ├── main.tf, outputs.tf, providers.tf, variables.tf
├── eks/
│   ├── main.tf, karpenter.tf, outputs.tf
│   ├── providers.tf, variables.tf, locals.tf, data-sources.tf
└── addons/
    ├── main.tf, outputs.tf, providers.tf, variables.tf
    ├── locals.tf, data-sources.tf
```

**Makefile Targets:**
```bash
make install         # VPC → EKS → Addons
make destroy         # Addons → EKS → VPC
make destroy-cluster # Addons → EKS (keeps VPC)
make validate        # Check cluster health
make test-karpenter  # Test node provisioning
```

**Issues Resolved:**
- Terraform race condition: Split into 3 stacks (eks/addons separation)
- ECR public 403: Added `aws_ecrpublic_authorization_token`
- CoreDNS not scheduling: Added tolerations for bootstrap taint
- Karpenter CRD validation: Changed to `kubectl_manifest` provider
- Security group tag drift: Moved to `node_security_group_tags`
- NodePool v1.8.x: Added required `consolidateAfter` field

**Validation:**
```bash
$ kubectl get nodes
NAME                            STATUS   ROLES    AGE
ip-10-0-xx-xx.ec2.internal     Ready    <none>   # Bootstrap
ip-10-0-xx-xx.ec2.internal     Ready    <none>   # Karpenter Spot

$ kubectl get pods -n karpenter
karpenter-xxxxx   1/1   Running

$ kubectl get nodepool
karpenter-node-group   True

$ kubectl get ec2nodeclass
karpenter-node-group   True
```

### 2026-01-22: Bootstrap Node Group Stabilization
**Status:** ✅ COMPLETE

**What Changed:**
- Switched bootstrap node group AMI to `AL2_ARM_64` for faster, more reliable creation
- Standardized bootstrap label to `role=bootstrap` to match Phase 0 requirements

**Files Modified:**
- `cluster/terraform/karpenter.tf`

**Validation:**
- EKS cluster ACTIVE
- Bootstrap node group creation progressing (no health issues)

### 2026-01-22: Terraform VPC Separation
**Status:** ✅ COMPLETE

**What Changed:**
- Separated VPC from EKS cluster into independent Terraform modules
- Both use same S3 bucket but different paths:
  - VPC: `s3://poc-idp-tfstate/vpc/terraform.tfstate`
  - EKS: `s3://poc-idp-tfstate/eks/terraform.tfstate`
- EKS reads VPC outputs via remote state

**Files Modified:**
- Created: `cluster/terraform-vpc/` (new directory)
  - `main.tf`, `locals.tf`, `outputs.tf`, `providers.tf`, `versions.tf`, `README.md`
- Updated: `cluster/terraform/main.tf` (uses remote state)
- Updated: `cluster/terraform/locals.tf` (removed VPC vars)
- Updated: `cluster/terraform/karpenter.tf`, `nlb.tf`, `security_groups.tf`
- Updated: `scripts/install-infra.sh` (provisions VPC first, then EKS)
- Updated: `scripts/destroy-cluster.sh` (destroys EKS first, then VPC)
- Created: `docs/TERRAFORM-VPC-SEPARATION.md` (full documentation)

**Benefits:**
- Independent lifecycle (VPC can exist without EKS)
- Faster EKS iterations (no VPC recreation)
- Better organization and modularity
- Safer destroys (explicit order)

**Next Actions:**
- [ ] Consider replacing NLB with ALB (simpler, better for L7)
- [ ] Test full install/destroy cycle
- [ ] Update main README.md

### 2026-01-22: Full Platform Reset
**Status:** ✅ COMPLETE**What Was Destroyed:**
- All ArgoCD Applications (backstage, keycloak, external-dns, etc.)
- All Kubernetes namespaces (argocd, backstage, keycloak, ingress-nginx, etc.)
- EKS cluster `idp-poc-darede-cluster`
- VPCs: `vpc-07068c2e8724db4dc`, `vpc-0988b68ceca3b4a3a`
- Terraform state cleaned
- kubectl contexts removed

**Files Removed:**
- `argocd-apps/platform/keycloak*.yaml` (all variants)
- `argocd-apps/platform/kyverno.yaml`
- `cluster/terraform/rds-keycloak.tf`
- `platform/keycloak/` (entire directory)
- `platform/keycloak-bootstrap/` (entire directory)
- `platform/kyverno/` (entire directory)

**Config Updated:**
- `identity_provider: "cognito"` ✓
- `keycloak.enabled: "false"` ✓

**Validation:**
- ✅ No EKS cluster exists
- ✅ No Keycloak RDS instances
- ✅ No VPCs with cluster name
- ✅ No kubectl contexts
- ✅ No Terraform state files
- ✅ All Keycloak/Kyverno files removed

---

## 🚧 OPEN QUESTIONS

### NLB vs ALB Decision
**Question:** Should we use ALB instead of NLB?

**Current:** NLB (Layer 4) → ingress-nginx (Layer 7)
**Proposed:** ALB (Layer 7) → Kubernetes Services directly

**ALB Advantages:**
- Native TLS termination with ACM (already have certificate)
- Native L7 routing (path-based, host-based)
- Better health checks (HTTP instead of TCP)
- WAF integration (future security)
- Can route directly to services (no NodePort needed)
- Simpler architecture (less components)

**NLB Advantages:**
- Preserves client IP
- Lower latency (no L7 processing)
- Works with any protocol (not just HTTP)

**Recommendation:** Use ALB for this IDP use case
- Internal platform (client IP less critical)
- All traffic is HTTP/HTTPS
- Simpler architecture preferred
- Better integration with AWS services

**Decision:** ALB implemented (2026-01-27)

---

## 📝 RECENT CHANGES

### 2026-01-27: Shared ALB Architecture (ADR-001, ADR-002)

**Problem:**
- Each Ingress creates a separate ALB (~$16/month each)
- Security groups managed at app layer (coupling, duplication)
- Port 8080 hardcoded (doesn't scale to multiple apps)

**Solution: Shared ALB via IngressGroup**

**Architecture Changes:**

1. **`terraform/eks/main.tf`** (Infrastructure Layer)
   - Created `aws_security_group.platform_alb` - shared by all platform apps
   - Added `node_security_group_additional_rules` for ALB → pods (ports 1024-65535)
   - Exported `platform_alb_security_group_id`, `node_security_group_id`, `cluster_security_group_id`

2. **`terraform/platform-gitops/locals.tf`**
   - Added `shared_alb` config with IngressGroup name: `dev-platform`
   - References shared SG from EKS module

3. **`terraform/platform-gitops/argocd.tf`**
   - Removed per-app security groups (`argocd_alb`)
   - ArgoCD now uses IngressGroup annotation: `alb.ingress.kubernetes.io/group.name: dev-platform`
   - All future apps will share the same ALB

4. **`docs/ARCHITECTURE-DECISIONS.md`** (NEW)
   - ADR-001: Shared ALB Strategy (cost reduction)
   - ADR-002: Security Group Ownership (infra vs app layer)
   - ADR-003: Port Range 1024-65535 (covers all app ports)
   - ADR-004: IngressGroup Naming Convention

**Benefits:**
- Single ALB for all platform apps (ArgoCD, Backstage, Grafana, etc.)
- ~$16/month savings per additional app
- Security groups owned by infra layer (EKS module)
- Scalable to N applications without SG changes

**Validation:**
```bash
make validate-gitops  # ✅ All checks pass
curl https://argocd.timedevops.click  # ✅ HTTP 200
kubectl get ingress -n argocd  # ✅ ALB: k8s-devplatform-*
```

**Status:** Shared ALB operational, ArgoCD accessible, architecture ready for new apps.

---

### 2026-01-27: GitOps Fixes - ALB Connectivity & ArgoCD

**Issues Fixed:**
1. **AWS LB Controller IAM Policy** - Missing `elasticloadbalancing:DescribeListenerAttributes` permission (new in v2.11+)
2. **External-DNS IAM Policy** - `ListResourceRecordSets` was scoped to single zone, but external-dns discovers all zones first
3. **ALB Security Group** - Was using cluster SG (no external ingress), created dedicated SG with HTTPS 443 from 0.0.0.0/0
4. **ALB to Pods Connectivity** - Added SG rules to allow ALB to reach pods on port 8080 (cluster SG + node SG)
5. **ArgoCD Redirect Loop** - Fixed by setting `server.rootpath = ""` instead of `/`

**Changes Made:**
- `terraform/platform-gitops/aws-lb-controller.tf`: Replaced managed policy with inline policy containing full v2.11+ permissions
- `terraform/platform-gitops/external-dns.tf`: Moved `ListResourceRecordSets` to global scope (required for zone discovery)
- `terraform/platform-gitops/argocd.tf`: 
  - Created `aws_security_group.argocd_alb` with HTTPS ingress
  - Added `aws_security_group_rule.argocd_alb_to_cluster` for ALB→cluster SG
  - Fixed ArgoCD params: `server.basehref = "/"`, `server.rootpath = ""`

**Manual Step (Now Managed via Terraform):**
- ~~Added SG rule to node security group via AWS CLI~~
- ✅ Now managed via EKS module `node_security_group_additional_rules`

**Validation:**
```bash
# All checks pass
make validate-gitops

# ArgoCD accessible
curl -I https://argocd.timedevops.click  # HTTP 200

# DNS resolving
dig argocd.timedevops.click +short  # Returns ALB IPs

# Target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>  # healthy
```

**Current Status:**
- ✅ ArgoCD UI accessible at https://argocd.timedevops.click
- ✅ ALB with TLS termination (ACM certificate)
- ✅ External-DNS creating Route53 records
- ✅ All pods healthy
- ⚠️ `platform-apps` Application shows "Unknown" sync status (expected - no manifests in argocd-apps/platform/ yet)

---

### Phase: ArgoCD + Backstage (INCIDENT RESOLVED)
Status: COMPLETE

Root Cause:
1) **ArgoCD 504** — ALB targets unhealthy because AWS LB Controller could not assume its IRSA role. The controller pods still had a **stale `AWS_ROLE_ARN`** from a previous role name, so `sts:AssumeRoleWithWebIdentity` failed and TargetGroupBinding reconciliation stalled.
2) **Backstage OutOfSync** — Helm schema validation failed because `ingress` was defined under `backstage:` in `platform-apps/backstage/values.yaml`, which the chart rejects.

Fix:
- **IRSA rollout protection:** Added `podAnnotations` in `terraform/platform-gitops/aws-lb-controller.tf` tied to the role ARN to force pod rollouts when the IAM role changes.
- **Backstage values:** Moved `ingress` block to top-level in `platform-apps/backstage/values.yaml` (chart expects `ingress` at root).

How to Debug (Future):
```bash
# 1) Identify 504 source
kubectl get ingress -n argocd
kubectl describe ingress argocd-server -n argocd
curl -I https://argocd.timedevops.click

# 2) ALB Target health
aws elbv2 describe-target-health --target-group-arn <tg-arn> --region us-east-1

# 3) AWS LB Controller IRSA
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml
kubectl get pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[0].spec.containers[0].env}'
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=200

# 4) Backstage Application status
kubectl describe application backstage -n argocd
```

Validation:
- ✅ ALB target health now shows healthy targets
- ✅ ArgoCD UI responds HTTP 200
- ✅ Only 1 ALB (IngressGroup `dev-platform`)
- ⏳ Backstage sync completes after values.yaml commit to GitOps repo
