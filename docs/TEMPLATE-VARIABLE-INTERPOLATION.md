# Backstage Template Variable Interpolation Guide

## Overview

Understanding how and when variables are interpolated is critical for Backstage templates to work correctly.

## Variable Interpolation Timing

### 1. Template Time (Backstage Scaffolder)

**When**: During template scaffold (`fetch:template` action)  
**Variables**: `${{ parameters.* }}`, `${{ values.* }}`, `${{ environment.parameters.* }}`  
**Process**: Backstage replaces these with actual values **before** creating the repository

**Example**:
```yaml
# In template.yaml skeleton
env:
  BUCKET_NAME: ${{ values.name }}-static-${{ values.environment }}
  
# After Backstage scaffolding → Generated in repo
env:
  BUCKET_NAME: my-site-static-dev
```

✅ **Best Practice**: Use `${{ values.* }}` for:
- AWS Account ID
- AWS Region
- GitHub Org/Repo names
- Role ARNs
- Fixed configuration values

### 2. Runtime (GitHub Actions)

**When**: During workflow execution in GitHub Actions  
**Variables**: `${{ env.* }}`, `${{ github.* }}`, `${{ secrets.* }}`  
**Process**: GitHub Actions evaluates these at runtime

**Example**:
```yaml
# In generated workflow
env:
  SITE_NAME: my-site
  AWS_REGION: us-east-1

steps:
  - run: echo "Deploying ${{ env.SITE_NAME }} to ${{ env.AWS_REGION }}"
  # GitHub evaluates at runtime → "Deploying my-site to us-east-1"
```

✅ **Best Practice**: Use `${{ env.* }}` for:
- Dynamic values computed during workflow
- Values that change between steps
- Conditional logic

---

## Common Mistake: Mixing Interpolation Contexts

### ❌ WRONG Pattern (Causes Empty Variables)

```yaml
# template.yaml skeleton - workflow file
env:
  AWS_ACCOUNT_ID: ${{ values.awsAccountId }}  # Backstage replaces this
  
jobs:
  deploy:
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          # ❌ ERROR: env.AWS_ACCOUNT_ID is NOT interpolated by Backstage!
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/...
```

**Why it fails**:
1. Backstage sees `${{ env.AWS_ACCOUNT_ID }}` as a literal string (not `${{ values.* }}`)
2. Backstage doesn't replace it during scaffolding
3. Generated file has: `role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/...`
4. GitHub Actions tries to evaluate `env.AWS_ACCOUNT_ID` but it doesn't exist in the env context
5. Result: Empty or invalid ARN

### ✅ CORRECT Pattern (Direct Interpolation)

```yaml
# template.yaml skeleton - workflow file
jobs:
  deploy:
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          # ✅ CORRECT: Backstage interpolates values.* during scaffold
          role-to-assume: arn:aws:iam::${{ values.awsAccountId }}:role/${{ values.roleName }}
```

**Why it works**:
1. Backstage sees `${{ values.awsAccountId }}` and replaces it with `948881762705`
2. Generated file has: `role-to-assume: arn:aws:iam::948881762705:role/github-actions-ecr-push`
3. GitHub Actions receives a complete, hardcoded ARN
4. OIDC authentication succeeds

---

## Real-World Examples

### Example 1: S3 Bucket Naming

**Problem**: Bucket name missing environment suffix

```yaml
# ❌ WRONG
env:
  ENVIRONMENT: ${{ values.environment }}  # Backstage → "dev"
  BUCKET_NAME: ${{ values.name }}-static-${{ env.ENVIRONMENT }}  # ❌ Empty!

# Generated file:
env:
  ENVIRONMENT: dev
  BUCKET_NAME: my-site-static-  # ❌ Missing suffix!
```

**Solution**:
```yaml
# ✅ CORRECT
env:
  BUCKET_NAME: ${{ values.name }}-static-${{ values.environment }}

# Generated file:
env:
  BUCKET_NAME: my-site-static-dev  # ✅ Complete!
```

### Example 2: Multi-use Variables

If you need a value in **both** contexts:

```yaml
# Define once at top level for GitHub Actions runtime
env:
  AWS_REGION: ${{ values.awsRegion }}  # Backstage → "us-east-1"

jobs:
  deploy:
    steps:
      # Use values.* for Backstage interpolation
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ values.awsAccountId }}:role/...
          # Use env.* for GitHub Actions runtime (already defined)
          aws-region: ${{ env.AWS_REGION }}
      
      # Use env.* in subsequent steps
      - run: aws s3 ls --region ${{ env.AWS_REGION }}
```

---

## Backstage Configuration Sources

### User Input (`parameters.*`)

Defined in `template.yaml` → `spec.parameters`:

```yaml
spec:
  parameters:
    - title: Website Details
      properties:
        name:
          title: Site Name
          type: string
```

Referenced as: `${{ parameters.name }}` or `${{ values.name }}`

### Platform Config (`environment.parameters.*`)

Defined in `platform-apps/backstage/values.yaml` → `scaffolder.defaultEnvironment.parameters`:

```yaml
scaffolder:
  defaultEnvironment:
    parameters:
      githubOrg: darede-labs
      awsRegion: us-east-1
      awsAccountId: "948881762705"
      environment: dev
      githubActionsRoleName: github-actions-ecr-push
```

Referenced as: `${{ environment.parameters.awsRegion }}`

**Source of Truth**: Terraform ConfigMap (`terraform/platform-gitops/configmap.tf`)

---

## Debugging Checklist

### Variable Not Interpolated (Empty in Generated Repo)

1. **Check variable prefix**:
   - ✅ Using `${{ values.* }}`? → Should work
   - ❌ Using `${{ env.* }}`? → Won't be interpolated by Backstage

2. **Check source**:
   - User input → `${{ parameters.* }}` or `${{ values.* }}`
   - Platform config → `${{ environment.parameters.* }}`

3. **Verify platform config**:
   ```bash
   kubectl get configmap platform-params -n backstage -o yaml | grep ENVIRONMENT
   ```

4. **Check Backstage values.yaml**:
   ```bash
   grep -A 20 "defaultEnvironment:" platform-apps/backstage/values.yaml
   ```

### OIDC Role Assumption Fails

**Error**: "Request ARN is invalid" or "Could not assume role"

**Check**:
1. Is `role-to-assume` using `${{ values.awsAccountId }}`? (Not `env.AWS_ACCOUNT_ID`)
2. Is `role-to-assume` hardcoded in generated repo? `grep "role-to-assume" .github/workflows/*.yaml`
3. Expected: `arn:aws:iam::948881762705:role/github-actions-ecr-push`

### Bucket/Resource Not Found

**Check**:
1. Naming convention matches: `{name}-static-{environment}`
2. `ENVIRONMENT` variable is defined in workflow
3. Crossplane claim uses same naming convention

---

## Reference: Template Variable Sources

| Variable | Source | Interpolation Time | Example |
|----------|--------|-------------------|---------|
| `${{ parameters.name }}` | User input (template UI) | Template Time | `my-site` |
| `${{ values.name }}` | Same as `parameters.*` | Template Time | `my-site` |
| `${{ environment.parameters.awsRegion }}` | Platform ConfigMap | Template Time | `us-east-1` |
| `${{ env.AWS_REGION }}` | Workflow env block | Runtime (GitHub) | Evaluated during workflow |
| `${{ github.sha }}` | GitHub context | Runtime (GitHub) | `abc123...` |
| `${{ secrets.TOKEN }}` | GitHub Secrets | Runtime (GitHub) | `***` |

---

## Best Practices Summary

1. **Use `${{ values.* }}` for fixed configuration** (account ID, region, role names)
2. **Use `${{ env.* }}` only for dynamic runtime values** (computed in workflow)
3. **Never nest interpolation contexts** (no `${{ env.VAR }}` where `VAR` is `${{ values.* }}`)
4. **Test generated repos** to verify variables were interpolated correctly
5. **Keep platform config in ConfigMap** for single source of truth

---

## Related Files

- Platform Config: `config/platform-params.yaml`
- Terraform ConfigMap: `terraform/platform-gitops/configmap.tf`
- Backstage Values: `platform-apps/backstage/values.yaml`
- Template Examples:
  - `backstage-custom/templates/idp-nodejs-app/skeleton/.github/workflows/ci.yml`
  - `backstage-custom/templates/idp-static-site/skeleton/.github/workflows/publish.yaml`
