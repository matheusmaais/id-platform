# Instalação Imutável - Guia de Referência

## 📋 Princípios

A implementação segue o princípio de **infraestrutura imutável**:

1. ✅ **Tudo configurável via `config.yaml`** - Nenhuma configuração hardcoded
2. ✅ **Instalação via `make install`** - Processo único e repetível
3. ✅ **Templates renderizados** - Todos os manifests são gerados a partir de templates
4. ✅ **Sem scripts manuais** - Tudo automatizado e versionado

---

## 🚀 Instalação Completa

### Pré-requisitos

```bash
# Verificar ferramentas necessárias
make doctor
```

### Instalação em 1 Comando

```bash
make install
```

Este comando executa:
1. `validate-config` - Valida `config.yaml`
2. `terraform` - Provisiona infraestrutura AWS
3. `bootstrap` - Instala ArgoCD e aplica root app
4. `verify` - Verifica saúde da instalação

---

## ⚙️ Configuração via config.yaml

### Estrutura Principal

```yaml
# Cluster
cluster_name: "idp-poc-darede-cluster"
region: "us-east-1"
auto_mode: "false"
use_karpenter: "true"

# Karpenter (instâncias Graviton)
karpenter:
  instance_types:
    - "t4g.small"   # Graviton2 ARM (prioritário)
    - "t4g.medium"  # Graviton2 ARM
    - "t3a.small"   # x86_64 fallback
  limits:
    cpu: 20
    memory: 80Gi

# Backstage
secrets:
  backstage:
    terraform_version: "1.7.5"  # Versão do Terraform para scaffolder
    postgres_host: "backstage-postgresql"
    # ... outras configurações
```

### Todas as Configurações

Todas as configurações são centralizadas em `config.yaml`:
- ✅ Instâncias EC2 (Karpenter)
- ✅ Versão do Terraform (Backstage scaffolder)
- ✅ Credenciais e secrets
- ✅ Domínios e subdomínios
- ✅ Tags AWS
- ✅ Configurações de VPC

---

## 🔄 Fluxo de Renderização

### Templates (.tpl)

Todos os manifests Kubernetes são templates:
- `platform/karpenter/nodepool.yaml.tpl`
- `platform/karpenter/ec2nodeclass.yaml.tpl`
- `packages/backstage/terraform-installer-configmap.yaml.tpl`
- `platform/*/*.tpl`

### Renderização Automática

O script `render-templates.sh` é executado automaticamente durante:
- `make install` (via `bootstrap`)
- `make terraform` (se necessário)

**Variáveis disponíveis nos templates:**
- `{{ cluster_name }}`
- `{{ terraform_version }}`
- `{{ karpenter_limits_cpu }}`
- `{{ karpenter_limits_memory }}`
- E muitas outras (ver `scripts/render-templates.sh`)

---

## 📦 Componentes Imutáveis

### 1. Terraform Installer (Backstage)

**Localização:** `packages/backstage/terraform-installer-configmap.yaml.tpl`

**Configuração via config.yaml:**
```yaml
secrets:
  backstage:
    terraform_version: "1.7.5"  # Configurável
```

**Características:**
- ✅ Detecta arquitetura automaticamente (ARM64/x86_64)
- ✅ Baixa Terraform correto para arquitetura
- ✅ Configura paths dinâmicos
- ✅ Sem scripts separados - tudo no ConfigMap

**Renderização:**
```bash
./scripts/render-templates.sh
# Gera: packages/backstage/terraform-installer-configmap.yaml
```

### 2. Karpenter NodePool

**Localização:** `platform/karpenter/nodepool.yaml.tpl`

**Configuração via config.yaml:**
```yaml
karpenter:
  instance_types:
    - "t4g.small"
    - "t4g.medium"
  limits:
    cpu: 20
    memory: 80Gi
```

**Renderização:**
```bash
./scripts/render-templates.sh
# Gera: platform/karpenter/nodepool.yaml
```

### 3. Bootstrap Nodes (Terraform)

**Localização:** `cluster/terraform/karpenter.tf`

**Configuração:** Usa instâncias do `config.yaml` via `locals.tf`

---

## 🛠️ Comandos Principais

### Instalação

```bash
make install          # Instalação completa
make validate-config  # Valida config.yaml
make terraform        # Apenas infraestrutura
make bootstrap        # Apenas ArgoCD
make verify           # Verifica instalação
```

### Manutenção

```bash
# Renderizar templates manualmente
./scripts/render-templates.sh

# Aplicar mudanças no cluster
kubectl apply -f platform/karpenter/nodepool.yaml
kubectl apply -f packages/backstage/terraform-installer-configmap.yaml
```

### Limpeza

```bash
make clean  # Remove todos os recursos
```

---

## ✅ Checklist de Mudanças

Ao modificar configurações:

- [ ] Atualizar `config.yaml` (nunca editar manifests diretamente)
- [ ] Executar `make validate-config` para validar
- [ ] Executar `./scripts/render-templates.sh` para renderizar templates
- [ ] Revisar manifests gerados (`.yaml` sem `.tpl`)
- [ ] Aplicar mudanças: `make install` ou `kubectl apply`

---

## 🚫 O que NÃO fazer

❌ **NÃO editar manifests `.yaml` diretamente** - Eles são gerados de templates
❌ **NÃO criar scripts separados** - Tudo deve estar em templates ou ConfigMaps
❌ **NÃO hardcodar valores** - Tudo deve vir de `config.yaml`
❌ **NÃO aplicar patches manuais** - Use `config.yaml` + `make install`

---

## 📚 Estrutura de Arquivos

```
.
├── config.yaml                           # ⭐ ÚNICA fonte de configuração
├── Makefile                              # Comandos principais
├── scripts/
│   ├── render-templates.sh               # Renderiza templates
│   ├── install-infra.sh                  # Terraform
│   ├── bootstrap-kubernetes.sh           # ArgoCD
│   └── verify-installation.sh            # Validação
├── cluster/terraform/                    # Infraestrutura
│   ├── main.tf
│   ├── karpenter.tf
│   └── locals.tf                         # Lê config.yaml
├── platform/
│   └── karpenter/
│       ├── nodepool.yaml.tpl             # Template
│       └── nodepool.yaml                 # Gerado (não editar)
└── packages/
    └── backstage/
        ├── terraform-installer-configmap.yaml.tpl  # Template
        └── terraform-installer-configmap.yaml      # Gerado (não editar)
```

---

## 🔍 Troubleshooting

### Templates não renderizados

```bash
# Renderizar manualmente
./scripts/render-templates.sh

# Verificar se templates foram gerados
ls -la platform/karpenter/*.yaml
ls -la packages/backstage/*.yaml
```

### Configuração não aplicada

```bash
# Verificar se config.yaml está correto
make validate-config

# Verificar se templates foram renderizados
grep -r "{{" platform/ packages/  # Não deve encontrar nada (exceto .tpl)
```

### Mudanças não refletidas

```bash
# 1. Atualizar config.yaml
# 2. Renderizar templates
./scripts/render-templates.sh

# 3. Aplicar mudanças
kubectl apply -f <manifest-gerado>
```

---

## 📖 Referências

- [Makefile](../Makefile) - Comandos disponíveis
- [config.yaml.example](../config.yaml.example) - Exemplo de configuração
- [render-templates.sh](../scripts/render-templates.sh) - Script de renderização
