# EKS Terraform Module

## Overview
Creates an EKS cluster with:
- Kubernetes 1.31
- IRSA enabled
- Bootstrap node group (ARM64 Graviton)
- Essential add-ons (CoreDNS, VPC-CNI, kube-proxy)

## Usage

```bash
# Initialize
terraform init -backend-config="profile=darede"

# Plan
terraform plan

# Apply
terraform apply -auto-approve

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name platform-eks --profile darede

# Verify
kubectl get nodes
```

## Bootstrap Node Group

**Purpose**: Hosts Karpenter and core platform tools.

**Why it exists**: Karpenter needs to run inside the cluster to provision nodes (chicken-egg problem).

**Taint**: `node-role.kubernetes.io/bootstrap=NoSchedule` prevents regular workloads from scheduling here.

**Capacity**: 1-2 nodes, t4g.medium (ARM64), on-demand only.

## Dependencies
Requires VPC Terraform to be applied first (reads from remote state).
