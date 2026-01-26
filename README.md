# IDP Platform - AWS Infrastructure

Internal Developer Platform infrastructure as code.

## Overview

This repository contains the complete infrastructure for our Internal Developer Platform running on AWS, including:

- **VPC Infrastructure** - Multi-AZ networking with NAT Gateway
- **EKS Cluster** - Kubernetes 1.31 with IRSA
- **Karpenter** - Spot-first autoscaling
- **GitOps** - ArgoCD with Cognito SSO
- **Authentication** - Amazon Cognito OIDC provider

## Quick Start

See [docs/STATE.md](docs/STATE.md) for current state and detailed setup instructions.

## Repository Structure

```
id-platform/
├── terraform/
│   ├── vpc/               # VPC infrastructure
│   ├── eks/               # EKS cluster with Karpenter IAM
│   ├── addons/            # Karpenter deployment
│   └── platform-gitops/   # ArgoCD + Authentication (Phase 0)
├── docs/
│   ├── STATE.md           # Canonical state document
│   └── PHASE-0-GITOPS.md  # GitOps implementation guide
├── Makefile               # Automation targets
└── README.md              # This file
```

## Terraform Stacks

Each stack has isolated state in S3:

| Stack | Purpose | State Key |
|-------|---------|-----------|
| `vpc` | VPC, Subnets, NAT Gateway | `vpc/terraform.tfstate` |
| `eks` | EKS Cluster, Bootstrap Nodes | `eks/terraform.tfstate` |
| `addons` | Karpenter Controller | `addons/terraform.tfstate` |
| `platform-gitops` | ArgoCD, Cognito, DNS | `platform-gitops/terraform.tfstate` |

## Installation

Full platform installation:

```bash
make install
```

This runs in order:
1. `make install-vpc`
2. `make install-eks`
3. `make install-addons`
4. `make install-gitops`

## Destruction

Full platform destruction:

```bash
make destroy
```

This runs in reverse order:
1. `make destroy-gitops`
2. `make destroy-addons`
3. `make destroy-eks`
4. `make destroy-vpc`

## Validation

Check cluster health:

```bash
make validate
```

Check GitOps components:

```bash
make validate-gitops
```

## Access

- **ArgoCD UI:** https://argocd.timedevops.click
- **Authentication:** AWS Cognito (SSO)

## Documentation

- [docs/STATE.md](docs/STATE.md) - Current state, validation results, decisions
- [docs/PHASE-0-GITOPS.md](docs/PHASE-0-GITOPS.md) - GitOps implementation details

## Phases

- ✅ **Phase 0 - Bootstrap:** VPC, EKS, Karpenter, ArgoCD, Cognito
- 🚧 **Phase 1 - Infra Self-Service:** Crossplane for AWS resources
- 📋 **Phase 2 - App Scaffolding:** One-click app creation + deploy

## Support

For troubleshooting, see [docs/STATE.md](docs/STATE.md) "Recent Changes" section.
