# ApplicationSet Auto-Discovery

## Overview

The `workloads` ApplicationSet automatically discovers and deploys applications based on their presence in the platform GitOps repository.

## How It Works

1. **Directory Structure:**
   ```
   platform-gitops/
   └── applications/
       └── workloads/
           ├── default/
           │   ├── hello-world/
           │   │   └── application.yaml
           │   └── api-gateway/
           │       └── application.yaml
           ├── team-alpha/
           │   └── service-a/
           │       └── application.yaml
           └── team-beta/
               └── service-b/
                   └── application.yaml
   ```

2. **Git Generator:**
   - Scans `applications/workloads/*/*` every 60 seconds
   - Discovers all directories at this level
   - Extracts application name and namespace from path

3. **Template:**
   - Creates ArgoCD Application for each discovered directory
   - Application name: `{{.path.basename}}` (last directory in path)
   - Target namespace: `{{.path[1]}}` (second segment of path)
   - GitOps repo: `https://github.com/{org}/{app-name}-gitops.git`

## Naming Conventions

### Application Name
- Derived from directory name
- Must match GitOps repository name (without `-gitops` suffix)
- Example: `hello-world` → GitOps repo: `hello-world-gitops`

### Namespace
- Derived from parent directory name
- Must exist in cluster (or be created by syncPolicy)
- Example: `applications/workloads/default/hello-world` → namespace: `default`

## Adding a New Application

### Option 1: Via Backstage (Recommended)

Use the "Create Application" template in Backstage. It will:
1. Create the application repository
2. Create the GitOps repository
3. Create a Pull Request to add the application manifest
4. Register the component in Backstage

### Option 2: Manual

1. **Create application directory:**
   ```bash
   mkdir -p applications/workloads/{namespace}/{app-name}
   ```

2. **Create application.yaml:**
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
     labels:
       app.kubernetes.io/name: my-app
       app.kubernetes.io/managed-by: backstage
     finalizers:
       - resources-finalizer.argocd.argoproj.io
   spec:
     project: default
     source:
       repoURL: https://github.com/my-org/my-app-gitops.git
       targetRevision: main
       path: manifests
     destination:
       server: https://kubernetes.default.svc
       namespace: default
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
         allowEmpty: false
       syncOptions:
         - CreateNamespace=true
       retry:
         limit: 5
         backoff:
           duration: 5s
           factor: 2
           maxDuration: 3m
   ```

3. **Commit and push:**
   ```bash
   git add applications/workloads/{namespace}/{app-name}/
   git commit -m "feat: add {app-name} application"
   git push
   ```

4. **Wait for ApplicationSet:**
   - ApplicationSet checks every 60 seconds
   - ArgoCD Application will be created automatically
   - Application will start syncing

## Sync Policy

All applications inherit this sync policy:

- **Automated Sync:** Yes
  - **Prune:** Delete resources removed from Git
  - **Self-Heal:** Revert manual changes to Git state
  - **Allow Empty:** No (prevent accidental deletion)

- **Sync Options:**
  - **CreateNamespace:** Auto-create target namespace
  - **PruneLast:** Delete resources after new ones are healthy
  - **RespectIgnoreDifferences:** Ignore configured differences

- **Retry Policy:**
  - **Limit:** 5 attempts
  - **Backoff:** Exponential (5s → 10s → 20s → 40s → 3m)

## Ignored Differences

The following fields are ignored to prevent sync drift:

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/replicas  # Allow HPA to manage replicas
```

## Monitoring

### List All Discovered Applications

```bash
kubectl get applications -n argocd -l app.kubernetes.io/managed-by=applicationset
```

### Check ApplicationSet Status

```bash
kubectl get applicationset workloads -n argocd -o yaml
```

### View ApplicationSet Logs

```bash
kubectl logs -n argocd -l app.kubernetes.io/component=applicationset-controller --tail=100 -f
```

### Debug Application Discovery

```bash
# Check if directory is being scanned
argocd appset get workloads

# Force refresh
argocd appset refresh workloads
```

## Troubleshooting

### Application Not Discovered

1. **Check directory structure:**
   ```bash
   tree applications/workloads
   ```
   - Must be exactly 3 levels deep: `workloads/{namespace}/{app}/application.yaml`

2. **Check ApplicationSet logs:**
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/component=applicationset-controller --tail=50
   ```

3. **Verify Git access:**
   ```bash
   argocd repo list
   ```

4. **Force refresh:**
   ```bash
   argocd appset refresh workloads
   ```

### Application Created but Not Syncing

1. **Check Application status:**
   ```bash
   argocd app get {app-name}
   ```

2. **Verify GitOps repo exists:**
   ```bash
   git ls-remote https://github.com/{org}/{app-name}-gitops.git
   ```

3. **Check manifests path:**
   ```bash
   # Should contain valid Kubernetes manifests
   tree {app-name}-gitops/manifests
   ```

4. **Manual sync:**
   ```bash
   argocd app sync {app-name}
   ```

### Namespace Not Created

1. **Check sync options:**
   ```yaml
   syncOptions:
     - CreateNamespace=true  # Must be present
   ```

2. **Create namespace manually:**
   ```bash
   kubectl create namespace {namespace}
   kubectl label namespace {namespace} app.kubernetes.io/managed-by=backstage
   ```

## Security Considerations

### Git Repository Access

- ApplicationSet requires read access to platform GitOps repo
- Individual Applications require read access to their GitOps repos
- Use SSH keys or GitHub App for authentication

### RBAC

- ApplicationSet controller runs with cluster-admin privileges
- Individual Applications inherit project permissions
- Use ArgoCD Projects to restrict what Applications can deploy

### Namespace Isolation

- Applications can only deploy to their target namespace
- Cross-namespace references are blocked by default
- Use NetworkPolicies for additional isolation

## Best Practices

1. **One Application Per Directory:**
   - Each app gets its own directory
   - Multiple manifests can live in same directory if related

2. **Consistent Naming:**
   - Directory name = Application name
   - GitOps repo: `{app-name}-gitops`

3. **Use Labels:**
   - Add `backstage.io/owner` for ownership tracking
   - Add `app.kubernetes.io/part-of` for system grouping

4. **Namespace Organization:**
   - Use namespace for team isolation
   - Consider: `team-{name}`, `env-{name}`, or by business domain

5. **Sync Policy:**
   - Always use automated sync for GitOps
   - Enable prune to prevent drift
   - Enable self-heal to revert manual changes

## Migration from Manual Applications

If you have existing ArgoCD Applications not managed by ApplicationSet:

1. **Move application manifest:**
   ```bash
   mv argocd-apps/{app}.yaml applications/workloads/{namespace}/{app}/application.yaml
   ```

2. **Update labels:**
   ```yaml
   labels:
     app.kubernetes.io/managed-by: applicationset  # Add this
   ```

3. **Commit and push:**
   ```bash
   git add applications/workloads/{namespace}/{app}/
   git commit -m "feat: migrate {app} to ApplicationSet"
   git push
   ```

4. **Delete old Application:**
   ```bash
   kubectl delete application {app} -n argocd
   ```

5. **Wait for rediscovery:**
   - ApplicationSet will recreate the Application
   - Existing resources remain untouched
   - Sync status preserved

## References

- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [ArgoCD Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
