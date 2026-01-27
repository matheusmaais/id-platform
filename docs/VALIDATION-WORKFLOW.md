# Validation Workflow

## Overview

**CRITICAL**: Validation is **mandatory** before any platform application deployment. The Makefile enforces this by making `validate-params` a prerequisite for all deployment targets.

## Automatic Validation

### Targets with Mandatory Validation

```makefile
# These targets automatically run validation first:
make bootstrap-platform   # Depends on: validate-params → configure-kubectl
make install-backstage    # Depends on: bootstrap-platform (which validates)
```

### Validation Checks

The `scripts/validate-params.sh` script validates:

1. ✅ **Git Config File**: `config/platform-params.yaml` exists
2. ✅ **Kubernetes ConfigMap**: `platform-params` exists in `argocd` namespace
3. ✅ **ApplicationSet**: `platform-apps` exists in `argocd` namespace
4. ✅ **Current Configuration**: Displays repo, domain, and ALB settings

## Deployment Flow

### ✅ Correct Flow (Validation Built-In)

```bash
# Step 1: Apply Terraform (creates ConfigMap)
cd terraform/platform-gitops
terraform init
terraform apply

# Step 2: Bootstrap (validates automatically)
cd ../..
make bootstrap-platform
# → Runs validate-params first
# → Creates ApplicationSet if validation passes

# Step 3: Install Backstage (validates via bootstrap-platform)
make install-backstage
# → Depends on bootstrap-platform
# → Inherits validation check
```

### ❌ What Happens Without ConfigMap

```bash
$ make bootstrap-platform

=== Validating Platform Parameters ===

1. Git config file...
✅ config/platform-params.yaml exists

2. Kubernetes ConfigMap...
❌ ConfigMap platform-params not found in argocd namespace
   Run: cd terraform/platform-gitops && terraform apply
make: *** [bootstrap-platform] Error 1
```

**Result**: Deployment stops immediately with clear error message.

### ❌ What Happens Without Git Config

```bash
$ rm config/platform-params.yaml
$ make bootstrap-platform

=== Validating Platform Parameters ===

1. Git config file...
❌ config/platform-params.yaml not found
make: *** [bootstrap-platform] Error 1
```

**Result**: Deployment stops before any kubectl commands.

## Manual Validation

You can also run validation manually anytime:

```bash
# Validate current configuration
make validate-params

# Output:
=== Validating Platform Parameters ===

1. Git config file...
✅ config/platform-params.yaml exists

2. Kubernetes ConfigMap...
✅ ConfigMap platform-params exists

3. ApplicationSet...
✅ ApplicationSet platform-apps exists

=== Current Configuration ===

📝 Git Params (config/platform-params.yaml):
org: matheusmaais
name: id-platform
branch: main
url: https://github.com/matheusmaais/id-platform
domain: timedevops.click
backstageDomain: backstage.timedevops.click
albGroupName: dev-platform

☸️  ConfigMap Params (platform-params):
{
  "ACM_CERTIFICATE_ARN": "arn:aws:acm:...",
  "ALB_GROUP_NAME": "dev-platform",
  "BACKSTAGE_DOMAIN": "backstage.timedevops.click",
  ...
}

✅ All validations passed!
```

## Benefits

### 1. Fail Fast
- Catches configuration issues **before** deployment
- Clear error messages with remediation steps
- No partial deployments with missing config

### 2. Prevents Common Errors
- ✅ Forgot to apply Terraform? → Script catches it
- ✅ Deleted config file? → Script catches it
- ✅ Wrong namespace? → Script catches it

### 3. Self-Documenting
- Script shows current configuration
- Easy to verify values before deployment
- Helpful for troubleshooting

### 4. Cannot Be Bypassed
- Validation is a Makefile **dependency**
- Can't run deployment targets without it
- Enforces best practices automatically

## Validation Script Location

```
scripts/validate-params.sh
```

**Requirements**:
- Must be executable: `chmod +x scripts/validate-params.sh`
- Uses `kubectl`, `yq`, and `jq` (optional for pretty print)
- Runs from repository root

## Troubleshooting

### ConfigMap Not Found

```bash
❌ ConfigMap platform-params not found in argocd namespace
   Run: cd terraform/platform-gitops && terraform apply
```

**Fix**: Apply Terraform to create the ConfigMap
```bash
cd terraform/platform-gitops
terraform apply
```

### ApplicationSet Not Found

```bash
❌ ApplicationSet platform-apps not found
   Run: make bootstrap-platform
```

**Fix**: This is expected on first deployment. The validation will pass after you run terraform apply.

### Git Config Not Found

```bash
❌ config/platform-params.yaml not found
```

**Fix**: Create or restore the config file
```bash
# If you deleted it, restore from git
git checkout config/platform-params.yaml

# If you're on a new fork, create it from template
cp config/platform-params.yaml.example config/platform-params.yaml
vim config/platform-params.yaml  # Edit with your values
```

## Summary

| Before | After |
|--------|-------|
| ❌ Can deploy without validation | ✅ Validation is mandatory |
| ❌ Must remember to validate | ✅ Automatic via Makefile |
| ❌ Easy to skip steps | ✅ Enforced by dependencies |
| ❌ Partial deployments possible | ✅ Fail fast on issues |

**Golden Rule**: If validation fails, deployment stops. Fix the issue, then try again.
