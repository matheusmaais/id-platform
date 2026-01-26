# Platform Rebuild Summary

**Branch**: `platform-rebuild-clean`  
**Date**: 2026-01-23  
**Status**: ✅ Phases A, B, C Complete

---

## What Was Built

### Phase A - Total Destruction ✅
- Created clean branch
- Removed all legacy Terraform, Kubernetes manifests, scripts
- Cleaned repository to minimal state (README, Makefile, docs/, LICENSE)

### Phase B - Base Infrastructure ✅
**VPC**:
- 3 Availability Zones
- Private + public subnets
- Single NAT Gateway (cost-optimized)
- Proper EKS tagging

**EKS Cluster**:
- Kubernetes 1.31
- IRSA enabled
- Public + private endpoint
- Control plane logging enabled
- Essential addons: CoreDNS, VPC-CNI, kube-proxy

**Bootstrap Node Group**:
- Instance type: `t4g.medium` (ARM64 Graviton)
- Capacity: 1-2 nodes, on-demand
- Taint: `node-role.kubernetes.io/bootstrap=NoSchedule`
- Purpose: Hosts Karpenter and core platform tools

### Phase C - Karpenter ✅
**Installation**:
- Karpenter v1.0.6 via Helm
- IRSA configured
- Runs on bootstrap nodes (tolerates taint)

**EC2NodeClass** (`default`):
- AMI: Amazon Linux 2 ARM64
- IMDSv2 required (security)
- Private subnets only
- 50GB gp3 EBS volumes

**NodePool** (`default`):
- Architecture: ARM64 only
- Capacity: On-demand only (no spot)
- Instance families: t, c, m (general purpose)
- Generation: 4+ (modern instances)
- Limits: Max 100 vCPUs, 200Gi memory
- Disruption: `WhenEmpty` consolidation policy

---

## Repository Structure

```
.
├── Makefile                 # Deployment automation
├── terraform/
│   ├── vpc/                # VPC module (separate state)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   └── README.md
│   └── eks/                # EKS + Karpenter module
│       ├── main.tf
│       ├── karpenter.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── karpenter-outputs.tf
│       ├── providers.tf
│       └── README.md
└── docs/
    ├── STATE.md            # Canonical state tracking
    ├── karpenter.md        # Karpenter documentation
    └── REBUILD-SUMMARY.md  # This file
```

---

## How to Deploy

### 1. Prerequisites
- AWS CLI configured with profile `darede`
- Terraform >= 1.10
- kubectl installed
- S3 bucket `poc-idp-tfstate` exists
- DynamoDB table `terraform-state-lock` exists

### 2. Deploy Infrastructure
```bash
# Deploy everything (VPC + EKS + Karpenter)
make install

# Or step-by-step:
make apply-vpc          # Deploy VPC first
make apply-eks          # Deploy EKS + Karpenter
make configure-kubectl  # Configure kubeconfig
make validate           # Check everything works
```

### 3. Test Karpenter
```bash
make test-karpenter
# This creates a test deployment that triggers Karpenter to provision nodes
```

---

## Key Design Decisions

### Why separate VPC and EKS Terraform?
- Independent lifecycle (VPC can exist without EKS)
- Faster EKS iterations (no VPC recreation)
- Safer destroys (explicit order)

### Why ARM64 Graviton?
- 20% better price/performance vs x86
- Good availability
- Supported by all modern tools

### Why bootstrap node group?
- Karpenter chicken-egg problem: needs to run IN cluster to provision nodes
- Bootstrap provides initial capacity
- Tainted to prevent regular workloads

### Why on-demand only (no spot)?
- Simpler for dev environment
- No interruption handling needed
- Production can enable spot later

### Why single NAT Gateway?
- Cost optimization for dev
- Production should use `one_nat_gateway_per_az = true`

---

## Validation Checklist

After `make install`, verify:

- [x] VPC created with 3 AZs
- [x] EKS cluster ACTIVE
- [x] Bootstrap nodes ready (1-2 nodes)
- [x] Karpenter pod running in `karpenter` namespace
- [x] EC2NodeClass and NodePool resources exist
- [x] Test deployment triggers Karpenter node provisioning

```bash
# Check nodes
kubectl get nodes

# Check Karpenter
kubectl get pods -n karpenter
kubectl get nodepool
kubectl get ec2nodeclass

# Test provisioning
make test-karpenter
```

---

## What's NOT Included (Yet)

Phase C completed the foundation. Still needed:
- **Phase D**: GitOps base (ArgoCD, ingress-nginx, external-dns, external-secrets, Backstage)
- **Cognito**: Authentication
- **Monitoring**: Prometheus, Grafana, Loki
- **Crossplane**: Infrastructure provisioning

---

## Commits

1. **c0e9c3b**: `chore(reset): full platform teardown`
2. **816a46c**: `feat(infra): Phase B - clean base infrastructure`
3. **4547414**: `feat(karpenter): Phase C - Karpenter installation`
4. **d7a4587**: `docs(state): update STATE.md with completion`

---

## Next Steps

1. Deploy the infrastructure: `make install`
2. Validate everything works: `make validate && make test-karpenter`
3. Continue to Phase D (GitOps tooling)

---

## Notes

- All Terraform uses S3 backend with state locking
- AWS profile `darede` required for all operations
- Bootstrap nodes are intentionally small (cost optimization)
- Karpenter will provision larger nodes as needed
- Documentation embedded in each Terraform module
