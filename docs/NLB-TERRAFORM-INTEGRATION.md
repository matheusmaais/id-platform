# NLB Integration with Terraform

## Problem
Previously, ingress-nginx created its own NLB automatically via Kubernetes Service type LoadBalancer. This caused orphaned resources during `terraform destroy`:
- NLB remained after destroy
- ENIs blocked subnet deletion
- Security groups remained attached

## Solution
Create NLB in Terraform and configure ingress-nginx to use NodePort with external target groups.

## Configuration

### 1. Terraform (cluster/terraform/nlb.tf)
- Creates NLB with listeners on ports 80 and 443
- Target groups point to NodePorts 30080 (HTTP) and 30443 (HTTPS)
- Auto-attaches worker nodes to target groups
- TLS termination at NLB using ACM certificate

### 2. Ingress-Nginx Configuration
Use NodePort service instead of LoadBalancer:

```yaml
controller:
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
    annotations:
      # external-dns will use NLB DNS from Terraform
      external-dns.alpha.kubernetes.io/hostname: backstage.example.com
```

### 3. Install Script Integration
The install.sh should:
1. Get NLB DNS from Terraform output: `terraform output -raw nlb_dns_name`
2. Configure external-dns to point to the NLB
3. Install ingress-nginx with NodePort service

## Benefits
✅ **Clean terraform destroy** - no orphaned resources
✅ **Consistent infrastructure** - NLB managed by IaC
✅ **Better cost control** - NLB lifecycle tied to cluster
✅ **Faster destroy** - no manual cleanup needed

## Implementation Status
- [x] Terraform NLB resource created (`nlb.tf`)
- [x] Outputs configured for NLB DNS and ARN
- [ ] install.sh updated to use NodePort service
- [ ] Tested full destroy/apply cycle

## Next Steps
1. Update install.sh to configure ingress-nginx with NodePort
2. Test destroy/apply cycle
3. Update documentation

## Config.yaml Settings
```yaml
# Enable NLB creation in Terraform (default: true)
enable_nlb: true

# ACM certificate ARN for TLS termination
acm_certificate_arn: "arn:aws:acm:us-east-1:ACCOUNT:certificate/ID"
```
