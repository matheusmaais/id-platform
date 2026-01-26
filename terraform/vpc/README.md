# VPC Terraform Module

## Overview
Creates a VPC with:
- 3 Availability Zones
- Public + Private subnets
- Single NAT Gateway (cost-optimized)
- EKS-required tags

## Usage

```bash
# Initialize
terraform init -backend-config="profile=darede"

# Plan
terraform plan

# Apply
terraform apply -auto-approve

# Outputs
terraform output
```

## Design Decisions

**Single NAT Gateway**: Cost optimization for dev environment. Production should use `one_nat_gateway_per_az = true`.

**Subnet sizing**:
- Private: /20 (4096 IPs per AZ)
- Public: /24 (256 IPs per AZ)

**Tags**: EKS and Karpenter discovery tags applied automatically.
