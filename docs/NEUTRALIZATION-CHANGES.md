# Neutralization Changes - Organization-Specific References Removed

**Date:** 2026-01-27  
**Purpose:** Remove organization-specific references to make the codebase reusable

## Summary

All references to the organization name "darede" have been removed or parameterized to make this codebase portable and reusable by other organizations.

## Changes Made

### 1. Configuration Files

#### `config/platform-params.yaml`
- **Changed:** `awsProfile: darede` → `awsProfile: default`
- **Note:** Added comment to guide users to change to their AWS CLI profile name

### 2. Terraform Files

#### `terraform/platform-gitops/locals.tf`
- **Changed:** `oauth_domain_prefix: "idp-poc-darede"` → `oauth_domain_prefix: "idp-${local.environment}-platform"`
- **Impact:** Cognito OAuth domain is now dynamically generated based on environment

#### `terraform/platform-gitops/aws-lb-controller.tf`
- **Changed:** Pod annotation `platform.darede.io/irsa-role-arn` → `platform.idp/irsa-role-arn`
- **Impact:** Generic annotation namespace

#### `terraform/eks/outputs.tf`
- **Changed:** Removed `--profile darede` from kubectl configuration command
- **Impact:** Uses default AWS profile or environment credentials

#### `terraform/eks/data-sources.tf`
- **Changed:** Commented out `profile = "darede"` in remote state configuration
- **Note:** Users can uncomment and set their own profile if needed

#### `terraform/addons/data-sources.tf`
- **Changed:** Commented out `profile = "darede"` in remote state configuration
- **Note:** Users can uncomment and set their own profile if needed

#### `terraform/addons/variables.tf`
- **Changed:** Removed organization-specific tags (Owner, OwnerEmail, Manager, ManagerEmail)
- **Note:** Added comments for users to add their own organization tags

### 3. Documentation Files

#### `terraform/vpc/README.md`
- **Changed:** Removed hardcoded profile from init command
- **Added:** Comments showing how to use named profiles

#### `terraform/eks/README.md`
- **Changed:** Removed hardcoded profile from init and kubectl commands
- **Added:** Comments showing how to use named profiles

#### `docs/STATE.md`
- **Changed:** Removed `--profile darede` from all AWS CLI commands
- **Changed:** Updated Terraform commands to not require specific profile

#### `docs/PHASE-0-GITOPS.md`
- **Changed:** Removed `--profile darede` from AWS CLI commands

#### `docs/GITOPS-IMPLEMENTATION-REPORT.md`
- **Changed:** Updated AWS authentication examples to be generic

#### `docs/REBUILD-SUMMARY.md`
- **Changed:** Updated prerequisites to mention "AWS CLI configured" instead of specific profile
- **Changed:** Updated notes to remove profile requirement

#### `docs/FINAL-TEST-REPORT.md`
- **Changed:** Made AWS authentication section generic with commented examples

### 4. Files NOT Changed (Historical References)

The following files contain historical references in logs, troubleshooting notes, or past execution records. These were intentionally left unchanged as they document what actually happened:

- `docs/AUTH-FIXES-SUMMARY.md` - Historical email references
- `docs/CROSSPLANE-SUCCESS.md` - Historical resource names
- `docs/ECR-CONFIGURATION.md` - Historical IAM role names
- `docs/IMMUTABLE-INSTALLATION.md` - Historical cluster names
- `docs/IMPLEMENTATION-SUMMARY.md` - Historical GitHub org references

## How to Use This Codebase

### 1. Update Configuration

Edit `config/platform-params.yaml`:

```yaml
repository:
  org: your-github-org
  name: your-repo-name
  
infrastructure:
  domain: your-domain.com
  backstageDomain: backstage.your-domain.com
  awsProfile: your-aws-profile  # or "default"
```

### 2. AWS Authentication

**Option A:** Use default AWS credentials
```bash
# Terraform will use default AWS credentials
terraform init
terraform plan
```

**Option B:** Use named AWS profile
```bash
# Set profile in platform-params.yaml
awsProfile: your-profile-name

# Or export environment variable
export AWS_PROFILE=your-profile-name

# Or pass to Terraform backend
terraform init -backend-config="profile=your-profile-name"
```

**Option C:** Use AWS SSO
```bash
aws sso login --profile your-profile-name
export AWS_PROFILE=your-profile-name
```

### 3. Makefile Usage

The Makefile automatically reads the AWS profile from `config/platform-params.yaml`:

```bash
# All make commands will use the profile from config
make init-all
make plan-all
make apply-vpc
make apply-eks
make apply-addons
make apply-gitops
```

## Validation

To verify all changes are working:

```bash
# 1. Validate configuration
make validate-params

# 2. Test Terraform initialization
make init-all

# 3. Test Terraform planning
make plan-all
```

## Breaking Changes

### None Expected

All changes are backward compatible if you:
1. Update `config/platform-params.yaml` with your AWS profile
2. Set `AWS_PROFILE` environment variable if not using default profile

### Migration from Previous Setup

If you were using this codebase with "darede" profile:

```bash
# Option 1: Keep using "darede" profile
# Update config/platform-params.yaml:
awsProfile: darede

# Option 2: Switch to default profile
# Update config/platform-params.yaml:
awsProfile: default
# And ensure your AWS default profile is configured

# Option 3: Use your organization's profile
# Update config/platform-params.yaml:
awsProfile: your-org-profile
```

## Files Modified

```
 M config/platform-params.yaml
 M docs/FINAL-TEST-REPORT.md
 M docs/GITOPS-IMPLEMENTATION-REPORT.md
 M docs/PHASE-0-GITOPS.md
 M docs/REBUILD-SUMMARY.md
 M docs/STATE.md
 M terraform/addons/data-sources.tf
 M terraform/addons/variables.tf
 M terraform/eks/README.md
 M terraform/eks/data-sources.tf
 M terraform/eks/outputs.tf
 M terraform/platform-gitops/aws-lb-controller.tf
 M terraform/platform-gitops/locals.tf
 M terraform/vpc/README.md
```

## Testing Checklist

- [ ] Update `config/platform-params.yaml` with your organization details
- [ ] Run `make validate-params` to verify configuration
- [ ] Run `make init-all` to initialize Terraform
- [ ] Run `make plan-all` to verify Terraform plans work
- [ ] Verify AWS authentication works (check `aws sts get-caller-identity`)
- [ ] Deploy infrastructure: `make install`
- [ ] Verify all services are running: `make validate-platform`

## Support

For questions or issues related to these changes, please review:
- This document
- `config/platform-params.yaml` - Main configuration file
- `Makefile` - Automation commands
- `docs/ARCHITECTURE-DECISIONS.md` - Architecture decisions
