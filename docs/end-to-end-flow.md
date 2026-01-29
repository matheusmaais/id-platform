# Fluxo End-to-End - Da Criação à Produção

Este documento mostra o fluxo completo de um desenvolvedor criando uma aplicação no Backstage até ela estar rodando em produção, acessível pela internet.

## Visão Geral

**Tempo Total:** ~5 minutos  
**Comandos Manuais:** 0 (zero)  
**Interação do Dev:** Apenas preencher formulário no Backstage

---

## Diagrama de Sequência Detalhado

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Desenvolvedor
    participant Browser
    participant Backstage
    participant GitHub as GitHub API
    participant Repo as GitHub Repo<br/>idp-myapp
    participant CI as GitHub Actions<br/>CI Pipeline
    participant ECR as ECR Registry
    participant ArgoCD as ArgoCD<br/>Controller
    participant K8s as Kubernetes API
    participant Pod as Application Pod
    participant DNS as External-DNS
    participant R53 as Route53
    participant ALB
    actor User as End User

    rect rgb(230, 240, 255)
        Note over Dev,GitHub: FASE 1: Criação da Aplicação via Backstage (10-15s)
        Dev->>Browser: Acessa backstage.timedevops.click
        Browser->>Backstage: HTTPS Request
        Backstage-->>Browser: Login via Cognito (OIDC)
        Dev->>Browser: Preenche template Node.js<br/>(nome: myapp, arch: arm64)
        Browser->>Backstage: POST /scaffolder/v2/tasks
        
        Backstage->>Backstage: Executa actions:<br/>1. fetch:template<br/>2. publish:github<br/>3. catalog:register
        
        Backstage->>GitHub: POST /orgs/darede-labs/repos<br/>(Create repo idp-myapp)
        GitHub-->>Backstage: 201 Created
        
        Backstage->>GitHub: PUT /repos/.../contents/*<br/>(Push código + deploy/ + CI)
        GitHub-->>Backstage: Commits pushed
        
        Backstage-->>Browser: ✅ Aplicação criada!<br/>Repo: idp-myapp
    end

    rect rgb(255, 240, 230)
        Note over Repo,ECR: FASE 2: Build & Push (2-3 min)
        Repo->>CI: Webhook: push event
        CI->>CI: Checkout código
        CI->>CI: Docker build<br/>(platform: linux/arm64)
        CI->>ECR: docker login (OIDC/static keys)
        ECR-->>CI: Authentication success
        CI->>ECR: docker push<br/>tag: sha-abc123 + latest
        ECR-->>CI: Image pushed
        
        CI->>Repo: git checkout deploy/
        CI->>CI: Update deployment.yaml<br/>image: ecr/.../myapp:sha-abc123
        CI->>Repo: git commit + push<br/>[skip ci]
        Repo-->>CI: Manifest updated
    end

    rect rgb(230, 255, 240)
        Note over ArgoCD,K8s: FASE 3: GitOps Sync (30s-3 min)
        ArgoCD->>GitHub: Poll: git ls-remote<br/>(every 3 min)
        GitHub-->>ArgoCD: New commits detected
        
        ArgoCD->>ArgoCD: ApplicationSet generator<br/>detecta novo repo idp-myapp
        ArgoCD->>K8s: Create Application<br/>name: idp-myapp<br/>namespace: myapp
        K8s-->>ArgoCD: Application created
        
        ArgoCD->>Repo: git clone deploy/
        Repo-->>ArgoCD: Manifests baixados
        
        ArgoCD->>K8s: kubectl apply -f deploy/<br/>- namespace.yaml<br/>- deployment.yaml<br/>- service.yaml<br/>- ingress.yaml
        
        K8s->>K8s: Create Namespace: myapp
        K8s->>Pod: Create Pod<br/>image: ecr/.../myapp:sha-abc123
        Pod->>ECR: Pull image
        ECR-->>Pod: Image downloaded
        Pod->>Pod: Container starts<br/>Port 3000 listening
        K8s-->>ArgoCD: Sync complete ✅
    end

    rect rgb(255, 245, 230)
        Note over DNS,ALB: FASE 4: DNS & Load Balancer (30-60s)
        DNS->>K8s: Watch Ingress resources
        K8s-->>DNS: New Ingress: myapp<br/>host: myapp.timedevops.click
        
        DNS->>R53: ChangeResourceRecordSets<br/>A record: myapp.timedevops.click
        R53-->>DNS: Record created
        
        K8s->>ALB: AWS LB Controller<br/>reconcilia Ingress
        ALB->>ALB: Create TargetGroup<br/>targets: Pod IPs (10.0.x.x:3000)
        ALB->>ALB: Create Listener Rule<br/>host=myapp.timedevops.click
        ALB-->>K8s: ALB configured
    end

    rect rgb(240, 255, 240)
        Note over User,Pod: FASE 5: Tráfego de Produção (Imediato)
        User->>R53: DNS query:<br/>myapp.timedevops.click
        R53-->>User: A record: ALB IP
        
        User->>ALB: HTTPS Request (443)<br/>Host: myapp.timedevops.click
        ALB->>ALB: TLS Termination
        ALB->>ALB: Route by host header
        ALB->>Pod: HTTP Request (3000)<br/>via Target Group
        
        Pod->>Pod: Process request<br/>(Node.js app)
        Pod-->>ALB: HTTP 200 + response
        ALB-->>User: HTTPS response
        
        User->>User: ✅ App acessível!
    end

    Note over Dev,User: ⏱️ Tempo total: ~5 minutos<br/>✨ Zero comandos manuais
```

---

## Diagrama Simplificado (para apresentações)

```mermaid
graph LR
    Dev([👤 Desenvolvedor]) -->|1. Cria app<br/>via template| Backstage[🎨 Backstage<br/>IDP Portal]
    
    Backstage -->|2. Cria repo<br/>+ push código| GitHub[📦 GitHub<br/>idp-myapp]
    
    GitHub -->|3. Webhook<br/>push event| CI[⚙️ GitHub Actions<br/>CI Pipeline]
    
    CI -->|4. Build<br/>Docker image| CI
    CI -->|5. Push image<br/>tag: sha-xxx| ECR[🐳 ECR<br/>Container Registry]
    CI -->|6. Update manifest<br/>new image tag| GitHub
    
    GitHub -->|7. Git poll<br/>every 3 min| ArgoCD[🔄 ArgoCD<br/>GitOps Engine]
    
    ArgoCD -->|8. Auto-discover<br/>ApplicationSet| ArgoCD
    ArgoCD -->|9. Apply manifests<br/>kubectl apply| K8s[☸️ Kubernetes<br/>EKS Cluster]
    
    K8s -->|10. Pull image| ECR
    K8s -->|11. Create Pod<br/>+ Service + Ingress| Pod[📦 Running Pod<br/>Port 3000]
    
    Pod -->|12. Register<br/>target| ALB[⚖️ ALB<br/>Load Balancer]
    K8s -->|13. Create<br/>DNS record| Route53[🌐 Route53<br/>DNS]
    
    Route53 -->|14. Resolve| User([🌍 End User])
    User -->|15. HTTPS<br/>myapp.domain.com| ALB
    ALB -->|16. HTTP<br/>to Pod IP| Pod
    
    Pod -->|17. Response| ALB
    ALB -->|18. Response| User
    
    style Dev fill:#e1f5fe
    style Backstage fill:#fff9c4
    style GitHub fill:#f3e5f5
    style CI fill:#e0f2f1
    style ECR fill:#fce4ec
    style ArgoCD fill:#e8f5e9
    style K8s fill:#e3f2fd
    style Pod fill:#fff3e0
    style ALB fill:#fce4ec
    style Route53 fill:#e0f7fa
    style User fill:#f1f8e9
```

---

## Timeline Detalhado

| Fase | Duração | Componentes Envolvidos | O Que Acontece |
|------|---------|------------------------|----------------|
| **1. Backstage Scaffolder** | 10-15s | Backstage → GitHub API | • Dev preenche formulário<br/>• Backstage gera código do template<br/>• Cria repo no GitHub<br/>• Push inicial com código + manifests K8s + CI workflow |
| **2. CI Build & Push** | 2-3 min | GitHub Actions → ECR | • Webhook dispara CI<br/>• Docker build multi-platform (arm64)<br/>• Push para ECR com tags (sha + latest)<br/>• Update deployment.yaml com nova image tag |
| **3. ArgoCD Sync** | 30s-3 min | ArgoCD → Kubernetes | • ArgoCD polling detecta novo repo<br/>• ApplicationSet gera Application<br/>• Cria namespace<br/>• Apply manifests (Deployment, Service, Ingress) |
| **4. DNS & ALB** | 30-60s | External-DNS, LB Controller → Route53, ALB | • External-DNS cria registro A no Route53<br/>• LB Controller cria TargetGroup no ALB<br/>• Health checks começam |
| **5. Ready** | Imediato | - | • App acessível via HTTPS<br/>• ALB target healthy<br/>• DNS propagado |

**Total:** ~5 minutos ⏱️

---

## Protocolos e APIs Utilizados

### Por Fase

**Fase 1 - Backstage:**
- HTTPS: Browser ↔ Backstage (443)
- HTTPS: Backstage ↔ GitHub REST API (443)
- OIDC: Backstage ↔ Cognito (OAuth2 flow)

**Fase 2 - CI/CD:**
- Git over HTTPS: GitHub Actions ↔ GitHub (443)
- Docker Registry API: CI ↔ ECR (443)
- AWS STS: CI ↔ AWS (OIDC authentication)

**Fase 3 - GitOps:**
- Git over HTTPS: ArgoCD ↔ GitHub (443)
- Kubernetes API: ArgoCD ↔ EKS (6443)
- Docker Registry API: Kubelet ↔ ECR (443)

**Fase 4 - Infraestrutura:**
- Kubernetes API: External-DNS, LB Controller ↔ EKS (6443)
- Route53 API: External-DNS ↔ AWS (443)
- ELBv2 API: LB Controller ↔ AWS (443)

**Fase 5 - Tráfego:**
- DNS: End User ↔ Route53 (53)
- HTTPS: End User ↔ ALB (443)
- HTTP: ALB ↔ Pod (3000, interno VPC)

---

## Componentes e Responsabilidades

| Componente | Responsabilidade | Tecnologia |
|------------|------------------|------------|
| **Backstage** | IDP Portal, scaffolding de apps | Node.js, React |
| **GitHub** | Source control, webhooks | Git, REST API |
| **GitHub Actions** | CI/CD pipeline | YAML workflows |
| **ECR** | Container registry | Docker Registry API v2 |
| **ArgoCD** | GitOps engine, auto-sync | Go, Kubernetes controllers |
| **Kubernetes** | Orchestration, scheduling | K8s API server |
| **External-DNS** | DNS automation | Go, Route53 API |
| **AWS LB Controller** | ALB/NLB automation | Go, ELBv2 API |
| **Route53** | DNS resolution | AWS managed |
| **ALB** | Load balancing, TLS termination | AWS managed |

---

## Exemplo Prático

### Input (Desenvolvedor no Backstage)

```yaml
App Name: myapp
Description: My awesome application
Architecture: arm64
Expose Publicly: Yes
Replicas: 2
```

### Output (5 minutos depois)

```bash
# 1. Repo criado
https://github.com/darede-labs/idp-myapp

# 2. Image no ECR
948881762705.dkr.ecr.us-east-1.amazonaws.com/idp-myapp:sha-abc123

# 3. Namespace + Pods no Kubernetes
$ kubectl get pods -n myapp
NAME                     READY   STATUS    RESTARTS   AGE
myapp-7d4f8b9c5d-abc12   1/1     Running   0          2m
myapp-7d4f8b9c5d-def34   1/1     Running   0          2m

# 4. DNS configurado
$ dig myapp.timedevops.click +short
1.2.3.4  # ALB IP

# 5. App acessível
$ curl -I https://myapp.timedevops.click
HTTP/2 200
content-type: application/json
```

---

## Observabilidade do Fluxo

Durante o fluxo, você pode acompanhar o progresso:

### No Backstage
```
Tasks → View running task → Ver logs em tempo real
```

### No GitHub
```
Actions → CI workflow → Build & Push logs
```

### No ArgoCD
```
Applications → idp-myapp → Sync status
```

### No Kubernetes
```bash
kubectl get application idp-myapp -n argocd -w
kubectl get pods -n myapp -w
```

---

## Comparação: Antes vs Depois da IDP

| Aspecto | Antes (Manual) | Depois (IDP) | Melhoria |
|---------|----------------|--------------|----------|
| **Criar repo** | Manual no GitHub | Automático | Instantâneo |
| **Criar Dockerfile** | Copiar de outro projeto | Template gerado | 100% padronizado |
| **Setup CI/CD** | Criar workflow do zero | Template gerado | 100% padronizado |
| **Criar manifests K8s** | Escrever YAML manual | Template gerado | 100% padronizado |
| **Deploy inicial** | kubectl apply manual | ArgoCD auto-sync | Zero comandos |
| **Setup DNS** | Abrir ticket infra | Automático via External-DNS | Sem tickets |
| **Setup ALB** | Console AWS manual | Automático via LB Controller | Sem console |
| **Observabilidade** | Configurar manualmente | Pré-configurado no template | Integrado |
| **Tempo Total** | 2-3 dias | 5 minutos | **99.8% redução** |
| **Comandos Manuais** | 20-30 comandos | 0 comandos | **100% redução** |
| **Taxa de Erro** | ~20% (typos, esquecimentos) | ~0% | **100% redução** |

---

## Rollback e Recovery

Se algo der errado, o rollback é simples:

```bash
# Rollback via Git (ArgoCD auto-sync)
cd idp-myapp
git revert HEAD
git push

# ArgoCD detecta e faz rollback automático em ~3 min
```

Ou via ArgoCD UI:
```
Application → History → Rollback to revision X
```

---

## Segurança no Fluxo

Cada etapa tem controles de segurança:

1. **Backstage:** Cognito OIDC, RBAC por grupos
2. **GitHub:** Token auth com scopes limitados
3. **CI:** OIDC (sem credenciais estáticas), ECR private registry
4. **ArgoCD:** RBAC, AppProject restrictions, namespace isolation
5. **Kubernetes:** NetworkPolicies, PodSecurityStandards, IRSA
6. **ALB:** TLS termination, WAF (opcional), Security Groups
7. **Pods:** Non-root user, read-only filesystem, resource limits

---

## Monitoramento do Fluxo

Você pode monitorar cada etapa:

```bash
# Backstage tasks
kubectl logs -n backstage -l app.kubernetes.io/name=backstage -f

# CI logs
# Ver no GitHub Actions UI

# ArgoCD sync
argocd app get idp-myapp --refresh

# Kubernetes events
kubectl get events -n myapp --sort-by='.lastTimestamp'

# Pod logs
kubectl logs -n myapp -l app.kubernetes.io/name=myapp -f
```

---

## FAQ

**P: E se o build do CI falhar?**  
R: ArgoCD não cria a Application pois o repo não tem deploy/ com manifests válidos. Dev conserta e faz novo push.

**P: E se o ArgoCD não detectar o repo?**  
R: Verifica se o repo nome começa com `idp-` e tem diretório `deploy/`. ApplicationSet filter requer ambos.

**P: E se o DNS não propagar?**  
R: External-DNS cria o registro em ~30s. Propagação DNS pode levar 1-2 min. Verificar logs do External-DNS.

**P: E se o pod não subir?**  
R: ArgoCD mostra o erro no status. Verificar: image pull (ECR permissions), resources (limits), probes (readiness).

**P: Posso customizar o template?**  
R: Sim! Templates estão em `backstage-custom/templates/`. Edite e commit para atualizar.

---

**Última Atualização:** 2026-01-29  
**Autor:** Platform Team
