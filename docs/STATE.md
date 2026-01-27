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
Status: ✅ INFRASTRUCTURE COMPLETE
Branch: platform-gitops-implementation

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
- `aws eks update-kubeconfig --region us-east-1 --name platform-eks --profile darede`
- Then: `make validate-gitops`

### 2026-01-26: GitOps Apply Fix (Cognito MFA) ✅
**Status:** ✅ READY (apply retry required)

**Issue:**
- Cognito User Pool creation failed with `Invalid MFA configuration` when `mfa_configuration = OPTIONAL` without a configured MFA method.

**Fix Applied:**
- Enabled software token MFA configuration:
  - `software_token_mfa_configuration { enabled = true }`

**Next Command:**
- `AWS_PROFILE=darede make apply-gitops`

### 2026-01-23: GitOps Plan Fixes + Provider Upgrade ✅
**Status:** ✅ PLAN OK (with `AWS_PROFILE=darede`)

**What Changed:**
- Upgraded Terraform providers via `terraform init -upgrade` (lockfile updated)
- Helm provider v3 syntax fixed (`kubernetes = { ... }`)
- IRSA assume-role now uses EKS data source OIDC issuer
- ALB SG annotation uses EKS data source `vpc_config` SG ID
- ACM lookup now matches primary domain `timedevops.click` (SAN includes wildcard)

**Commands:**
- Init/upgrade: `cd terraform/platform-gitops && terraform init -upgrade -reconfigure -backend-config="profile=darede"`
- Plan: `AWS_PROFILE=darede terraform plan`

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

**Manual Step Required:**
- Added SG rule to node security group (`sg-0af4edc484e912aa3`) via AWS CLI
- TODO: Export node SG from EKS module and manage via Terraform

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
