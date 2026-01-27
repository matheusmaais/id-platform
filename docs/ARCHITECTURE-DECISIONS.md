# Architecture Decisions Record (ADR)

## ADR-001: Shared ALB Strategy

### Status
**ACCEPTED** - 2026-01-27

### Context
Each Kubernetes Ingress with `kubernetes.io/ingress.class: alb` creates a separate AWS Application Load Balancer. This leads to:
- **Cost**: ~$16/month per ALB + data processing charges
- **Complexity**: Multiple DNS records, certificates, security groups
- **Limits**: AWS account limits on ALBs

### Decision
Use **IngressGroup** annotation to share a single ALB across all platform applications.

```yaml
# All platform ingresses use the same group
annotations:
  alb.ingress.kubernetes.io/group.name: platform-shared
  alb.ingress.kubernetes.io/group.order: "100"  # Lower = higher priority
```

### Consequences
- **Single ALB** for all platform apps (ArgoCD, Backstage, Grafana, etc.)
- **Single Security Group** for the shared ALB
- **Path/Host-based routing** via ALB rules
- **Cost reduction**: 1 ALB instead of N ALBs

### Implementation
1. Create shared ALB security group in EKS module (infra layer)
2. All apps use `group.name: platform-shared` annotation
3. Each app defines its own host/path rules

---

## ADR-002: Security Group Ownership

### Status
**ACCEPTED** - 2026-01-27

### Context
Current implementation creates security groups in the `platform-gitops` stack (application layer). This causes:
- **Coupling**: Apps managing infra resources
- **Duplication**: Each app creating similar SG rules
- **Drift**: Manual rules added outside Terraform

### Decision
Security groups belong to the **infrastructure layer** (EKS module), not application layer.

**Infrastructure Layer (terraform/eks):**
- Cluster security group
- Node security group  
- **Shared ALB security group** (NEW)
- Rules for ALB → Nodes communication

**Application Layer (terraform/platform-gitops):**
- Uses security groups via data sources
- Does NOT create security groups
- Only references existing SGs in Ingress annotations

### Implementation

#### 1. EKS Module Changes (`terraform/eks/main.tf`)

```hcl
# Shared ALB Security Group for all platform apps
resource "aws_security_group" "platform_alb" {
  name        = "${var.cluster_name}-platform-alb"
  description = "Shared ALB for platform applications"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All traffic to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.terraform_remote_state.vpc.outputs.vpc_cidr]
  }

  tags = merge(var.default_tags, {
    Name = "${var.cluster_name}-platform-alb"
  })
}

# Node SG rule: Allow ALB to reach any pod port
module "eks" {
  # ... existing config ...
  
  node_security_group_additional_rules = {
    ingress_platform_alb = {
      description                   = "Allow platform ALB to reach pods"
      protocol                      = "tcp"
      from_port                     = 1024
      to_port                       = 65535
      type                          = "ingress"
      source_security_group_id      = aws_security_group.platform_alb.id
    }
  }
}

# Export for use by platform-gitops
output "platform_alb_security_group_id" {
  description = "Security group ID for shared platform ALB"
  value       = aws_security_group.platform_alb.id
}
```

#### 2. Platform-GitOps Changes

```hcl
# Remove: aws_security_group.argocd_alb
# Remove: aws_security_group_rule.argocd_alb_to_*

# Use shared ALB SG from EKS
locals {
  platform_alb_sg_id = data.terraform_remote_state.eks.outputs.platform_alb_security_group_id
}

# ArgoCD Ingress uses shared group
server.ingress.annotations = {
  "alb.ingress.kubernetes.io/group.name"       = "platform-shared"
  "alb.ingress.kubernetes.io/security-groups"  = local.platform_alb_sg_id
  # ... other annotations
}
```

### Consequences
- **Clear ownership**: Infra team owns SGs, app team uses them
- **Scalability**: N apps share 1 ALB and 1 SG
- **No drift**: All SG rules in one place (EKS module)
- **Port range**: 1024-65535 covers all app ports

---

## ADR-003: Port Range for ALB → Nodes

### Status
**ACCEPTED** - 2026-01-27

### Context
Different applications use different ports:
- ArgoCD: 8080
- Backstage: 7007
- Grafana: 3000
- Prometheus: 9090
- Custom apps: various

### Decision
Allow **ephemeral port range (1024-65535)** from ALB to nodes.

### Rationale
1. **Kubernetes uses dynamic ports**: Services can use any port
2. **Target type IP**: ALB connects directly to pod IPs
3. **Security**: Traffic is VPC-internal (ALB → Node)
4. **Simplicity**: One rule covers all apps

### Security Considerations
- ALB SG only allows HTTPS (443) from internet
- Node SG only allows traffic FROM the ALB SG
- No direct internet → node access
- Defense in depth maintained

---

## ADR-004: IngressGroup Naming Convention

### Status
**ACCEPTED** - 2026-01-27

### Context
Need consistent naming for IngressGroups across environments.

### Decision
Use environment-prefixed group names:

| Environment | Group Name |
|-------------|------------|
| dev | `dev-platform` |
| staging | `stg-platform` |
| production | `prd-platform` |

### Implementation
```hcl
locals {
  ingress_group_name = "${var.environment}-platform"
}
```

All platform apps in same environment share the same ALB.

---

## Summary: Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS (443)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SHARED ALB (platform-shared)                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Security Group: ${cluster}-platform-alb                  │   │
│  │ Ingress: 443/tcp from 0.0.0.0/0                         │   │
│  │ Egress: all to VPC CIDR                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Rules:                                                          │
│  - argocd.domain.com/* → ArgoCD (8080)                          │
│  - backstage.domain.com/* → Backstage (7007)                    │
│  - grafana.domain.com/* → Grafana (3000)                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP (1024-65535)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         EKS NODES                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Security Group: ${cluster}-node                          │   │
│  │ Ingress: 1024-65535/tcp from platform-alb SG            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Pods:                                                           │
│  - ArgoCD Server (10.0.x.x:8080)                                │
│  - Backstage (10.0.x.x:7007)                                    │
│  - Grafana (10.0.x.x:3000)                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Migration Plan

1. **Phase 1**: Add shared ALB SG to EKS module
2. **Phase 2**: Update ArgoCD to use IngressGroup
3. **Phase 3**: Remove app-specific SGs from platform-gitops
4. **Phase 4**: Deploy new apps using shared ALB
