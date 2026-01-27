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
Phase: Phase 0 — Bootstrap
Status: ✅ GITOPS AUTH COMPLETE - Ready for SSO validation
Branch: main

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
