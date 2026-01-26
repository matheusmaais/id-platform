# Configuração Dinâmica - Referência Completa

## 📋 Visão Geral

Este documento descreve como **TODO** o projeto é configurado dinamicamente, eliminando valores hardcoded e garantindo que toda configuração venha de fontes centralizadas.

## 🎯 Princípios

1. **Single Source of Truth**: Toda configuração vem de `config.yaml` ou Terraform outputs
2. **Infrastructure as Code**: Nada é criado manualmente via CLI
3. **Template-First**: Todos os valores Helm usam templates `.tpl`
4. **IRSA Everywhere**: Credenciais AWS via IRSA, nunca estáticas
5. **Automated Scripts**: Scripts idempotentes que renderizam templates automaticamente

## 📂 Estrutura de Configuração

```
config.yaml                          # Valores de negócio e configuração
├── cluster_name
├── region
├── domain
├── subdomains (argocd, keycloak, backstage)
├── acm_certificate_arn
├── route53_hosted_zone_id
├── tags.cloud_economics           # OBRIGATÓRIO
├── karpenter.*
├── keycloak.*
└── secrets.*

cluster/terraform/
├── locals.tf                       # Lê config.yaml e centraliza variáveis
├── outputs.tf                      # Expõe valores para scripts
├── external-dns.tf                 # IRSA para Route53
└── *.tf                            # Outros recursos

platform/*/helm-values.yaml.tpl     # Templates Helm
scripts/*.sh                        # Scripts de instalação
```

## 🔧 Como Funciona

### 1. Terraform Outputs

Terraform expõe valores via outputs para serem consumidos pelos scripts:

```bash
terraform output -raw cluster_name
terraform output -raw external_dns_role_arn
terraform output -raw acm_certificate_arn
```

**Outputs disponíveis**:
- `cluster_name`, `region`
- `domain`, `argocd_subdomain`, `keycloak_subdomain`, `backstage_subdomain`
- `acm_certificate_arn`
- `route53_hosted_zone_id`
- `external_dns_role_arn`
- `karpenter_*` (enabled, irsa_arn, queue_name, etc.)
- `keycloak_*` (db_address, db_endpoint, db_secret_arn, etc.)

### 2. Template Rendering

O script `scripts/render-templates.sh` converte `.tpl` em arquivos finais:

```bash
# Busca todos os .tpl e renderiza
find platform apps -name "*.tpl" -type f | while read template; do
    render_template "$template"  # Substitui {{ variables }}
done
```

**Variáveis substituídas**:
- `{{ cluster_name }}`
- `{{ region }}`
- `{{ domain }}`
- `{{ acm_certificate_arn }}`
- `{{ external_dns_role_arn }}`
- `{{ cloud_economics_tag }}`
- `{{ keycloak_subdomain }}`
- E muitas outras...

### 3. Scripts de Instalação

Cada componente tem um script que:
1. Renderiza templates automaticamente
2. Instala via Helm com valores dinâmicos
3. Valida a instalação

```bash
scripts/install-ingress-nginx.sh
scripts/install-external-dns.sh
scripts/install-argocd.sh
scripts/install-keycloak.sh
scripts/install-karpenter.sh
```

## 📝 Exemplos

### Ingress NGINX com Valores Dinâmicos

**Template** (`platform/ingress-nginx/helm-values.yaml.tpl`):
```yaml
controller:
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "{{ acm_certificate_arn }}"
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "{{ cloud_economics_tag }},ManagedBy=helm"
```

**Renderizado** (`platform/ingress-nginx/helm-values.yaml`):
```yaml
controller:
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-east-1:948881762705:certificate/051f6515-0d0b-459c-a056-0663f7c88f5e"
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "Darede-IDP::devops,ManagedBy=helm"
```

### External DNS com IRSA

**Template** (`platform/external-dns/helm-values.yaml.tpl`):
```yaml
provider: aws
aws:
  region: "{{ region }}"
domainFilters:
  - "{{ domain }}"
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "{{ external_dns_role_arn }}"
```

**Terraform IRSA** (`cluster/terraform/external-dns.tf`):
```hcl
module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                  = "${local.cluster_name}-external-dns"
  attach_external_dns_policy = true
  external_dns_hosted_zone_arns = [
    "arn:aws:route53:::hostedzone/${local.route53_hosted_zone_id}"
  ]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }
}
```

## 🚀 Fluxo de Instalação

1. **Terraform Apply**:
   ```bash
   cd cluster/terraform
   terraform apply
   ```
   - Cria cluster EKS
   - Provisiona IRSA roles
   - Cria RDS para Keycloak
   - Configura networking

2. **Render Templates**:
   ```bash
   scripts/render-templates.sh
   ```
   - Lê Terraform outputs
   - Lê config.yaml
   - Renderiza todos os `.tpl` files

3. **Install Components**:
   ```bash
   scripts/install-karpenter.sh        # Node autoscaling
   scripts/install-ingress-nginx.sh    # Ingress controller + NLB
   scripts/install-external-dns.sh     # DNS automation
   scripts/install-argocd.sh           # GitOps
   scripts/install-keycloak.sh         # Identity provider
   ```

4. **One-Shot Install**:
   ```bash
   ./install.sh  # Executa tudo em ordem
   ```

## ✅ Validação

### Verificar IRSA do External DNS:
```bash
kubectl get sa external-dns -n external-dns \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

### Verificar ACM Certificate no NLB:
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o yaml | grep ssl-cert
```

### Verificar Cloud Economics Tag:
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o yaml | grep cloud_economics
```

## 🔒 Conformidade

- ✅ **Zero hardcoded values**: Tudo vem de config.yaml ou Terraform
- ✅ **IRSA for all AWS access**: Sem credenciais estáticas
- ✅ **Cloud Economics tags**: Obrigatórias em todos os recursos
- ✅ **Idempotent scripts**: Podem ser executados múltiplas vezes
- ✅ **Template-driven**: Todos os valores Helm via templates

## 📚 Referências

- **config.yaml**: Configuração central do projeto
- **cluster/terraform/locals.tf**: Lê e valida config.yaml
- **cluster/terraform/outputs.tf**: Expõe valores para scripts
- **scripts/render-templates.sh**: Renderização de templates
- **platform/*/helm-values.yaml.tpl**: Templates Helm

## 🎯 Próximas Adições

Ao adicionar novos componentes:

1. **Adicionar IRSA no Terraform** (se necessário):
   ```hcl
   module "component_irsa" {
     source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
     ...
   }
   ```

2. **Criar template Helm**:
   ```yaml
   # platform/component/helm-values.yaml.tpl
   serviceAccount:
     annotations:
       eks.amazonaws.com/role-arn: "{{ component_role_arn }}"
   ```

3. **Adicionar output no Terraform**:
   ```hcl
   output "component_role_arn" {
     value = module.component_irsa.iam_role_arn
   }
   ```

4. **Atualizar render-templates.sh**:
   ```bash
   COMPONENT_ROLE_ARN=$(terraform output -raw component_role_arn)
   ...
   sed -e "s|{{ component_role_arn }}|$COMPONENT_ROLE_ARN|g"
   ```

5. **Criar script de instalação**:
   ```bash
   scripts/install-component.sh
   ```

---

**Autor**: Platform Team
**Data**: Janeiro 2026
**Versão**: 1.0.0
