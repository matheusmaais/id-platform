# Karpenter Documentation

## Overview
Karpenter is a Kubernetes node autoscaler that provisions nodes based on actual workload requirements. It's significantly faster and more flexible than Cluster Autoscaler.

## Why Karpenter?

**vs Cluster Autoscaler:**
- Faster: Provisions nodes in ~30 seconds vs 3-5 minutes
- Smarter: Considers actual pod requirements (CPU, memory, topology)
- Simpler: No node groups to manage
- Cost-effective: Bin-packs workloads efficiently

## Architecture

```
┌─────────────────────────────────────────┐
│ Bootstrap Node Group (1-2 nodes)       │
│ - Runs Karpenter controller            │
│ - Runs CoreDNS, VPC-CNI                │
│ - Tainted: prevents workload scheduling│
└─────────────────────────────────────────┘
                  │
                  │ Provisions
                  ▼
┌─────────────────────────────────────────┐
│ Karpenter-Managed Nodes (0-N nodes)    │
│ - ARM64 Graviton instances             │
│ - On-demand only (no spot)             │
│ - Auto-provisioned based on pods       │
│ - Automatically terminated when empty  │
└─────────────────────────────────────────┘
```

## Components

### 1. EC2NodeClass (`default`)
Defines HOW nodes are created:
- **AMI**: Amazon Linux 2 (ARM64)
- **Subnets**: Private subnets with `karpenter.sh/discovery` tag
- **Security Groups**: Cluster security group
- **IAM Role**: Bootstrap node role (reused)
- **Instance Metadata**: IMDSv2 required (security best practice)

### 2. NodePool (`default`)
Defines WHEN and WHAT nodes are created:
- **Architecture**: ARM64 only (cost optimization)
- **Capacity Type**: On-demand only (no spot interruptions)
- **Instance Families**: t, c, m (general purpose + compute)
- **Generation**: 4+ (modern instances only)
- **Limits**: Max 100 vCPUs, 200Gi memory

## Node Lifecycle

1. **Pod Pending**: Kubernetes scheduler can't place pod (no capacity)
2. **Karpenter Detects**: Sees pending pod within seconds
3. **Instance Selection**: Picks best instance type for requirements
4. **Provisioning**: Launches EC2 instance (~30 seconds)
5. **Node Ready**: Node joins cluster, pod schedules
6. **Consolidation**: Empty nodes automatically terminated

## Cost Optimization

**ARM64 Graviton**:
- 20% better price/performance vs x86
- Same or better performance for most workloads

**On-demand Only**:
- No spot interruptions (simpler for dev)
- Production can enable spot for non-critical workloads

**Consolidation**:
- Policy: `WhenEmpty` (only empty nodes removed)
- Prevents unnecessary disruption

## Validation

```bash
# Check Karpenter is running
kubectl get pods -n karpenter

# Check NodePool and EC2NodeClass
kubectl get nodepool
kubectl get ec2nodeclass

# Create test deployment to trigger provisioning
kubectl create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause --replicas=0
kubectl scale deployment inflate --replicas=5

# Watch Karpenter provision nodes
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Check nodes
kubectl get nodes --show-labels | grep karpenter
```

## Troubleshooting

### Nodes not provisioning
1. Check Karpenter logs: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`
2. Verify EC2NodeClass: `kubectl describe ec2nodeclass default`
3. Check IAM role permissions
4. Verify subnet/SG tags: `karpenter.sh/discovery`

### Nodes created but pods not scheduling
1. Check pod tolerations (bootstrap taint)
2. Verify resource requests match NodePool requirements
3. Check node labels and selectors

## References
- [Karpenter Docs](https://karpenter.sh/)
- [EKS Best Practices - Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/)
