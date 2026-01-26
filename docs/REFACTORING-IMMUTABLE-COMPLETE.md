# Refatoração para Instalação Imutável - Completa

## ✅ Status: Refatoração Completa

Data: 2026-01-21
Objetivo: Remover scripts separados e consolidar tudo em instalação imutável via `make install` e `config.yaml`

---

## 📋 Mudanças Implementadas

### 1. Remoção de Scripts Separados

**Scripts Removidos:**
- ❌ `packages/backstage/fix-terraform.sh` - Removido
- ❌ `packages/backstage/fix-git-libs.sh` - Removido
- ❌ `packages/backstage/install-terraform-git.sh` - Removido

**Razão:** Toda a lógica agora está no ConfigMap template (`terraform-installer-configmap.yaml.tpl`)

---

### 2. ConfigMap como Template

**Arquivo Convertido:**
- `packages/backstage/terraform-installer-configmap.yaml` → `terraform-installer-configmap.yaml.tpl`

**Benefícios:**
- ✅ Versão do Terraform configurável via `config.yaml`
- ✅ Renderização automática durante `make install`
- ✅ Sem scripts separados para manter

**Configuração:**
```yaml
# config.yaml
secrets:
  backstage:
    terraform_version: "1.7.5"  # Configurável
```

---

### 3. Renderização Automática

**Script Atualizado:**
- `scripts/render-templates.sh`

**Mudanças:**
- ✅ Adicionada variável `TERRAFORM_VERSION` do `config.yaml`
- ✅ Incluído diretório `packages` na busca de templates
- ✅ Suporte para `{{ terraform_version }}` nos templates

**Integração:**
- ✅ `bootstrap-kubernetes.sh` agora renderiza templates automaticamente
- ✅ Executado antes de aplicar manifests Kubernetes

---

### 4. Documentação

**Documentos Criados/Atualizados:**
- ✅ `docs/IMMUTABLE-INSTALLATION.md` - Guia completo de instalação imutável
- ✅ `docs/GRAVITON-MIGRATION-COMPLETE.md` - Atualizado (removidas referências a scripts)
- ✅ `docs/REFACTORING-IMMUTABLE-COMPLETE.md` - Este documento

---

## 🎯 Princípios Implementados

### ✅ Infraestrutura Imutável

1. **Tudo via `config.yaml`**
   - Nenhuma configuração hardcoded
   - Versão do Terraform configurável
   - Instâncias EC2 configuráveis
   - Todos os secrets configuráveis

2. **Instalação via `make install`**
   - Processo único e repetível
   - Renderização automática de templates
   - Aplicação via GitOps (ArgoCD)

3. **Templates Renderizados**
   - Todos os manifests são templates (`.tpl`)
   - Renderização automática durante bootstrap
   - Variáveis do `config.yaml` injetadas

4. **Sem Scripts Manuais**
   - Tudo automatizado
   - Nada para executar manualmente
   - Versionado no Git

---

## 📦 Estrutura Final

```
.
├── config.yaml                                    # ⭐ ÚNICA fonte de configuração
├── Makefile                                       # make install
├── scripts/
│   ├── render-templates.sh                       # Renderiza .tpl → .yaml
│   ├── bootstrap-kubernetes.sh                  # Renderiza + aplica ArgoCD
│   └── install-infra.sh                          # Terraform
├── packages/backstage/
│   ├── terraform-installer-configmap.yaml.tpl   # Template (editar)
│   └── terraform-installer-configmap.yaml        # Gerado (não editar)
└── platform/karpenter/
    ├── nodepool.yaml.tpl                         # Template (editar)
    └── nodepool.yaml                             # Gerado (não editar)
```

---

## 🚀 Como Usar

### Instalação Completa

```bash
# 1. Configurar config.yaml
vim config.yaml

# 2. Instalar tudo
make install
```

### Atualizar Configuração

```bash
# 1. Editar config.yaml
vim config.yaml

# 2. Reinstalar (renderiza templates automaticamente)
make install

# Ou apenas renderizar templates
./scripts/render-templates.sh
```

### Mudar Versão do Terraform

```yaml
# config.yaml
secrets:
  backstage:
    terraform_version: "1.8.0"  # Nova versão
```

```bash
# Renderizar e aplicar
./scripts/render-templates.sh
kubectl apply -f packages/backstage/terraform-installer-configmap.yaml
kubectl rollout restart deployment/backstage -n backstage
```

---

## ✅ Checklist de Validação

- [x] Scripts separados removidos
- [x] ConfigMap convertido para template
- [x] Versão Terraform configurável via config.yaml
- [x] Renderização automática no bootstrap
- [x] Documentação atualizada
- [x] Suporte multi-arch (ARM64/x86_64) mantido
- [x] Instalação via `make install` funciona

---

## 🔍 Verificação

### Verificar Templates Renderizados

```bash
# Não deve encontrar {{ }} nos arquivos .yaml (exceto .tpl)
grep -r "{{" platform/ packages/ | grep -v ".tpl"

# Deve encontrar apenas nos .tpl
grep -r "{{" platform/ packages/ | grep ".tpl"
```

### Verificar ConfigMap

```bash
# Verificar se foi renderizado
cat packages/backstage/terraform-installer-configmap.yaml | grep -v "1.7.5"
# Deve mostrar a versão do config.yaml
```

### Testar Instalação Limpa

```bash
# Limpar tudo
make clean

# Instalar do zero
make install

# Verificar se tudo funciona
make verify
```

---

## 📚 Referências

- [IMMUTABLE-INSTALLATION.md](./IMMUTABLE-INSTALLATION.md) - Guia completo
- [config.yaml.example](../config.yaml.example) - Exemplo de configuração
- [Makefile](../Makefile) - Comandos disponíveis

---

**Refatoração concluída com sucesso!** 🎉

Agora a implementação segue 100% o princípio de infraestrutura imutável:
- ✅ Tudo configurável via `config.yaml`
- ✅ Instalação via `make install`
- ✅ Sem scripts separados
- ✅ Templates renderizados automaticamente
