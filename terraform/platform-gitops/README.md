# Platform GitOps Stack

This Terraform stack deploys the GitOps foundation for the Internal Developer Platform, including authentication, ingress, and DNS automation.

## Components

### 1. Amazon Cognito
- User Pool with email-based authentication
- OAuth 2.0 / OIDC provider for ArgoCD
- Admin group (`argocd-admins`) for RBAC
- MFA support (optional)
- Advanced security mode enforced

### 2. AWS Load Balancer Controller
- Helm chart v1.17.1
- IRSA-based authentication
- ALB provisioning for Kubernetes Ingress
- High availability (2 replicas)

### 3. ArgoCD
- Helm chart v9.3.5
- Cognito SSO integration via Dex
- RBAC with admin group mapping
- App-of-apps pattern configured
- Auto-scaling enabled
- Accessible at: https://argocd.timedevops.click

### 4. External-DNS
- Helm chart v1.20.0
- Automatic Route53 record management
- TXT registry for ownership tracking
- Policy: `upsert-only` (safe mode)
- Scoped IAM permissions to hosted zone

## Prerequisites

- VPC stack deployed (`terraform/vpc`)
- EKS stack deployed (`terraform/eks`)
- Addons stack deployed (`terraform/addons`)
- Route53 hosted zone: `timedevops.click`
- ACM certificate: `*.timedevops.click`
- AWS Load Balancer Controller IAM policy created (see below)

## Initial Setup

### 1. Create AWS Load Balancer Controller IAM Policy

This needs to be created manually once per AWS account:

```bash
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json
```

### 2. Deploy Stack

```bash
terraform init
terraform plan
terraform apply
```

Expected resources: ~25 resources

### 3. Wait for ALB and DNS

```bash
# Check ALB creation
kubectl get ingress -n argocd

# Check DNS propagation
dig argocd.timedevops.click
```

Propagation typically takes 2-5 minutes.

### 4. Create Admin User

```bash
# Get command from Terraform output
terraform output -raw create_admin_user_command | bash

# Or manually:
aws cognito-idp admin-create-user \
  --user-pool-id <pool-id> \
  --username admin@example.com \
  --user-attributes Name=email,Value=admin@example.com \
  --temporary-password TempPass123! \
  --message-action SUPPRESS

aws cognito-idp admin-add-user-to-group \
  --user-pool-id <pool-id> \
  --username admin@example.com \
  --group-name argocd-admins
```

### 5. Access ArgoCD

```bash
# Open ArgoCD UI
open https://argocd.timedevops.click

# Click "Login via AWS Cognito"
# Enter credentials
# Change temporary password on first login
```

## Validation

```bash
# Check all pods running
kubectl get pods -n argocd
kubectl get pods -n external-dns
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check Ingress
kubectl get ingress -n argocd

# Check DNS
dig argocd.timedevops.click

# Check HTTPS
curl -I https://argocd.timedevops.click

# Check ArgoCD Applications
kubectl get applications -n argocd
```

## Troubleshooting

### ALB not created

```bash
# Check AWS LB Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Common issues:
# - IAM policy not created
# - IRSA role not assumed correctly
# - Insufficient permissions
```

### DNS not resolving

```bash
# Check External-DNS logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Common issues:
# - IAM policy scoped to wrong hosted zone
# - Ingress missing external-dns annotation
# - TXT record conflicts (check txtOwnerId)
```

### Cognito redirect fails

```bash
# Verify callback URL matches exactly
echo "Expected: https://argocd.timedevops.click/api/dex/callback"

# Check Cognito client configuration
aws cognito-idp describe-user-pool-client \
  --user-pool-id <pool-id> \
  --client-id <client-id>
```

### 403 Forbidden on ArgoCD

```bash
# Verify user is in admin group
aws cognito-idp admin-list-groups-for-user \
  --user-pool-id <pool-id> \
  --username admin@example.com

# Expected: argocd-admins

# Check ArgoCD RBAC policy
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
```

## Outputs

```bash
# View all outputs
terraform output

# Specific outputs
terraform output argocd_url
terraform output cognito_user_pool_id
terraform output cognito_issuer
```

## Destruction

**Warning:** This will destroy authentication and GitOps infrastructure.

```bash
# Delete all ArgoCD applications first
kubectl delete applications --all -n argocd

# Then destroy Terraform stack
terraform destroy
```

## State

- **Backend:** S3
- **Bucket:** `poc-idp-tfstate`
- **Key:** `platform-gitops/terraform.tfstate`
- **Region:** `us-east-1`

## Architecture

```
User
  ↓ HTTPS
ALB (ACM TLS)
  ↓
ArgoCD Server
  ↓ OIDC
Cognito User Pool
  ↓ Groups Claim
ArgoCD RBAC (admin/readonly)

External-DNS
  ↓ Sync
Route53 (timedevops.click)
```

## Security

- ✅ TLS termination at ALB (ACM certificate)
- ✅ IRSA for pod-level IAM permissions
- ✅ Cognito with advanced security mode
- ✅ RBAC with group-based access control
- ✅ Least privilege IAM policies (scoped to hosted zone)
- ✅ MFA support (optional)
- ✅ Password policy enforced

## Next Steps

After this stack is deployed:

1. **Add Applications** to `argocd-apps/platform/`
2. **Configure Observability** (Prometheus, Grafana, Loki)
3. **Deploy Crossplane** for infrastructure provisioning
4. **Deploy Backstage** for developer portal
5. **Implement External Secrets** for secrets management

## References

- [AWS Load Balancer Controller Docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [External-DNS Documentation](https://kubernetes-sigs.github.io/external-dns/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/)
