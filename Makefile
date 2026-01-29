.PHONY: help init-all init-vpc init-eks init-addons init-gitops plan-all plan-vpc plan-eks plan-addons plan-gitops \
        apply-vpc apply-eks apply-addons apply-gitops destroy-addons destroy-eks destroy-vpc destroy-gitops destroy-cluster \
        configure-kubectl validate validate-gitops test-karpenter install destroy validate-env validate-params status \
        validate-backstage build-backstage-image push-backstage-image install-app-platform validate-app-platform destroy-app-platform \
        validate-platform-params validate-argocd-discovery validate-new-app-flow test-new-app

ENV_FILE ?= .env
ENV_LOADER = set -a; [ -f "$(ENV_FILE)" ] && . "$(ENV_FILE)"; set +a
CONFIG_FILE ?= config/platform-params.yaml

# Backstage image build (values.yaml is the source of truth)
BACKSTAGE_VALUES_FILE ?= platform-apps/backstage/values.yaml
BACKSTAGE_DIR ?= backstage-custom
BACKSTAGE_PLATFORM ?= linux/arm64
BACKSTAGE_IMAGE_REGISTRY ?= $(shell yq eval '.backstage.image.registry' $(BACKSTAGE_VALUES_FILE))
BACKSTAGE_IMAGE_REPOSITORY ?= $(shell yq eval '.backstage.image.repository' $(BACKSTAGE_VALUES_FILE))
BACKSTAGE_IMAGE_TAG ?= $(shell yq eval '.backstage.image.tag' $(BACKSTAGE_VALUES_FILE))
BACKSTAGE_IMAGE ?= $(BACKSTAGE_IMAGE_REGISTRY)/$(BACKSTAGE_IMAGE_REPOSITORY):$(BACKSTAGE_IMAGE_TAG)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

status: configure-kubectl ## Show platform installation status checklist
	@echo "=== Platform Status ==="
	@DOMAIN=$$(yq eval '.infrastructure.domain' config/platform-params.yaml 2>/dev/null || echo ""); \
	BACKSTAGE_DOMAIN=$$(yq eval '.infrastructure.backstageDomain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo ""; \
	if kubectl get deployment/argocd-server -n argocd >/dev/null 2>&1; then echo "[x] apply-gitops"; else echo "[ ] apply-gitops"; fi; \
	if kubectl get applicationset/platform-apps -n argocd >/dev/null 2>&1; then echo "[x] bootstrap-platform"; else echo "[ ] bootstrap-platform"; fi; \
	if kubectl get application/backstage -n argocd >/dev/null 2>&1; then echo "[x] install-backstage"; else echo "[ ] install-backstage"; fi; \
	if kubectl get ingress -n backstage >/dev/null 2>&1; then echo "[x] validate-platform"; else echo "[ ] validate-platform"; fi; \
	echo ""; \
	echo "ArgoCD URL: https://argocd.$$DOMAIN"; \
	echo "Backstage URL: https://$$BACKSTAGE_DOMAIN"

validate-env: ## Validate required environment variables in .env
	@SKIP_K8S_CHECKS=1 ./scripts/validate-params.sh >/dev/null
	@echo "✅ Environment validation passed"

##@ Infrastructure - Init

init-vpc: validate-env ## Initialize VPC Terraform
	@echo "==> Initializing VPC..."
	@PROFILE=$$(yq eval '.infrastructure.awsProfile' $(CONFIG_FILE)); \
	cd terraform/vpc && terraform init -reconfigure -backend-config="profile=$$PROFILE"

init-eks: validate-env ## Initialize EKS Terraform
	@echo "==> Initializing EKS..."
	@PROFILE=$$(yq eval '.infrastructure.awsProfile' $(CONFIG_FILE)); \
	cd terraform/eks && terraform init -reconfigure -backend-config="profile=$$PROFILE"

init-addons: validate-env ## Initialize Addons Terraform
	@echo "==> Initializing Addons..."
	@PROFILE=$$(yq eval '.infrastructure.awsProfile' $(CONFIG_FILE)); \
	cd terraform/addons && terraform init -reconfigure -backend-config="profile=$$PROFILE"

init-gitops: validate-env ## Initialize Platform GitOps Terraform
	@echo "==> Initializing Platform GitOps..."
	@PROFILE=$$(yq eval '.infrastructure.awsProfile' $(CONFIG_FILE)); \
	cd terraform/platform-gitops && terraform init -reconfigure -backend-config="profile=$$PROFILE"

init-all: init-vpc init-eks init-addons init-gitops ## Initialize all Terraform modules

##@ Infrastructure - Plan

plan-vpc: init-vpc ## Plan VPC changes
	cd terraform/vpc && terraform plan

plan-eks: init-eks ## Plan EKS changes
	cd terraform/eks && terraform plan

plan-addons: init-addons ## Plan addons changes
	cd terraform/addons && terraform plan

plan-gitops: init-gitops ## Plan platform GitOps changes
	cd terraform/platform-gitops && terraform plan

plan-all: plan-vpc plan-eks plan-addons plan-gitops ## Plan all changes

##@ Infrastructure - Apply (order: VPC -> EKS -> Addons)

apply-vpc: init-vpc ## Apply VPC infrastructure
	@echo "==> Applying VPC..."
	@cd terraform/vpc && terraform apply -auto-approve

apply-eks: init-eks ## Apply EKS infrastructure (requires VPC)
	@echo "==> Applying EKS..."
	@cd terraform/eks && terraform apply -auto-approve

apply-addons: init-addons ## Apply addons - Karpenter, NodePool, EC2NodeClass (requires EKS)
	@echo "==> Applying Addons..."
	@cd terraform/addons && terraform apply -auto-approve

apply-gitops: init-gitops ## Apply platform GitOps - Cognito, ArgoCD, AWS LB Controller, External-DNS (requires Addons)
	@echo "==> Applying Platform GitOps..."
	@$(ENV_LOADER); \
	export TF_VAR_github_token=$$GITHUB_TOKEN; \
	export TF_VAR_cognito_admin_temp_password=$$COGNITO_ADMIN_TEMP_PASSWORD; \
	cd terraform/platform-gitops && terraform apply -auto-approve
	@echo "==> Waiting for ArgoCD server..."
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || true
	@DOMAIN=$$(yq eval '.infrastructure.domain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo "\n✅ GitOps stack deployed: https://argocd.$$DOMAIN"
	@echo "\nNext steps:"
	@echo "  [x] apply-gitops"
	@echo "  [ ] bootstrap-platform   (run: make bootstrap-platform)"
	@echo "  [ ] install-backstage    (run: make install-backstage)"
	@echo "  [ ] validate-platform    (run: make validate-platform)"

##@ Infrastructure - Destroy (order: GitOps -> Addons -> EKS -> VPC)

destroy-gitops: init-gitops ## Destroy platform GitOps stack
	@echo "==> Destroying Platform GitOps..."
	@echo "Deleting ArgoCD applications first..."
	kubectl delete applications --all -n argocd --ignore-not-found || true
	@sleep 10
	@$(ENV_LOADER); cd terraform/platform-gitops && terraform destroy -auto-approve

destroy-addons: init-addons ## Destroy addons (Karpenter, NodePool, EC2NodeClass)
	@echo "==> Destroying Addons..."
	@$(ENV_LOADER); cd terraform/addons && terraform destroy -auto-approve

destroy-eks: init-eks ## Destroy EKS cluster and node groups
	@echo "==> Destroying EKS..."
	@$(ENV_LOADER); cd terraform/eks && terraform destroy -auto-approve

destroy-vpc: init-vpc ## Destroy VPC (requires EKS destroyed first)
	@echo "==> Destroying VPC..."
	@$(ENV_LOADER); cd terraform/vpc && terraform destroy -auto-approve

destroy-cluster: destroy-gitops destroy-addons destroy-eks ## Destroy GitOps + EKS + Addons only (keeps VPC)
	@echo "\n✅ GitOps, EKS cluster and addons destroyed. VPC preserved."

##@ Kubernetes

configure-kubectl: validate-env ## Configure kubectl for EKS cluster
	@REGION=$$(yq eval '.infrastructure.awsRegion' $(CONFIG_FILE)); \
	CLUSTER=$$(yq eval '.infrastructure.clusterName' $(CONFIG_FILE)); \
	PROFILE=$$(yq eval '.infrastructure.awsProfile' $(CONFIG_FILE)); \
	aws eks update-kubeconfig --region $$REGION --name $$CLUSTER --profile $$PROFILE

validate: configure-kubectl ## Validate cluster is ready
	@echo "=== Checking nodes ==="
	kubectl get nodes
	@echo "\n=== Checking pods ==="
	kubectl get pods -A
	@echo "\n=== Checking Karpenter ==="
	kubectl get pods -n karpenter
	kubectl get nodepool
	kubectl get ec2nodeclass
	@echo "\n=== Checking cluster info ==="
	kubectl cluster-info

validate-gitops: configure-kubectl ## Validate GitOps components
	@echo "=== Checking ArgoCD ==="
	kubectl get pods -n argocd
	kubectl get ingress -n argocd
	@echo "\n=== Checking External-DNS ==="
	kubectl get pods -n external-dns
	@echo "\n=== Checking AWS LB Controller ==="
	kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
	@echo "\n=== Checking DNS resolution ==="
	@DOMAIN=$$(yq eval '.infrastructure.domain' config/platform-params.yaml 2>/dev/null || echo ""); \
	dig +short argocd.$$DOMAIN
	@echo "\n=== Checking ArgoCD Applications ==="
	kubectl get applications -n argocd
	@echo "\n=== ArgoCD URL ==="
	@DOMAIN=$$(yq eval '.infrastructure.domain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo "https://argocd.$$DOMAIN"

test-karpenter: configure-kubectl ## Test Karpenter node provisioning
	@echo "Creating test deployment to trigger Karpenter..."
	kubectl create deployment nginx --image=nginx --replicas=3 || true
	@echo "Waiting 60s for nodes..."
	@sleep 60
	kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type
	kubectl get pods -l app=nginx
	@echo "\nCleanup: kubectl delete deployment nginx"

cleanup-test: configure-kubectl ## Cleanup test deployment
	kubectl delete deployment nginx --ignore-not-found

##@ Platform Applications (GitOps)

validate-params: ## Validate platform parametrization (Git config + ConfigMap + ApplicationSet)
	@./scripts/validate-params.sh
	@echo "✅ Platform parameters validated"
ifneq ($(filter validate-params,$(MAKECMDGOALS)),)
	@echo "\nNext steps:"
	@echo "  [ ] apply-gitops          (run: make apply-gitops)"
	@echo "  [ ] bootstrap-platform    (run: make bootstrap-platform)"
	@echo "  [ ] install-backstage     (run: make install-backstage)"
	@echo "  [ ] validate-platform     (run: make validate-platform)"
endif

validate-platform-params: validate-params ## Validate central platform params

validate-argocd-discovery: configure-kubectl ## Validate ArgoCD discovery components
	@echo "=== Checking AppProject ==="
	kubectl get appproject apps -n argocd
	@echo "\n=== Checking Workloads ApplicationSet ==="
	kubectl get applicationset workloads -n argocd
	@echo "\n=== Checking Discovered Workloads ==="
	kubectl get applications -n argocd -l platform.darede.io/workload=true || echo "No workloads discovered yet"
	@echo "\n✅ ArgoCD discovery validation complete"

validate-new-app-flow: configure-kubectl ## Validate app deployment (requires APP=<repo-name>)
	@if [ -z "$(APP)" ]; then \
		echo "❌ APP is required. Example: make validate-new-app-flow APP=idp-myapp1"; \
		exit 1; \
	fi
	@APP_NS=$$(echo "$(APP)" | sed 's/^idp-//'); \
	echo "=== Checking Application ($$APP) ==="; \
	kubectl get application "$$APP" -n argocd; \
	echo "\n=== Checking Namespace ($$APP_NS) ==="; \
	kubectl get namespace "$$APP_NS"; \
	echo "\n=== Checking Pods ($$APP_NS) ==="; \
	kubectl get pods -n "$$APP_NS"; \
	echo "\n=== Checking Ingress ($$APP_NS) ==="; \
	kubectl get ingress -n "$$APP_NS" || echo "Ingress not created (exposePublic=false)"; \
	echo "\n✅ App flow validation complete"

test-new-app: validate-new-app-flow ## Alias for validate-new-app-flow (requires APP=<repo-name>)

bootstrap-platform: validate-params configure-kubectl ## Create platform-apps ApplicationSet (validates params first)
	@echo "=== Creating Platform ApplicationSet ==="
	kubectl apply -f argocd-apps/platform/backstage-appset.yaml
	@echo "✅ ApplicationSet created. ArgoCD will sync automatically."
	@echo "Monitor: kubectl get applications -n argocd -w"
	@echo "\nNext steps:"
	@echo "  [x] apply-gitops"
	@echo "  [x] bootstrap-platform"
	@echo "  [ ] install-backstage    (run: make install-backstage)"
	@echo "  [ ] validate-platform    (run: make validate-platform)"

install-backstage: bootstrap-platform ## Install Backstage (via ApplicationSet, validates params first)
	@echo "=== Waiting for Backstage Application ==="
	kubectl wait --for=condition=Ready application/backstage -n argocd --timeout=60s || true
	@echo "=== Checking Backstage sync status ==="
	kubectl get application backstage -n argocd
	@echo "\n=== Waiting for Backstage pods ==="
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=300s || true
	@echo "\n✅ Backstage deployed"
	@BACKSTAGE_DOMAIN=$$(yq eval '.infrastructure.backstageDomain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo "URL: https://$$BACKSTAGE_DOMAIN"
	@echo "\nNext steps:"
	@echo "  [x] apply-gitops"
	@echo "  [x] bootstrap-platform"
	@echo "  [x] install-backstage"
	@echo "  [ ] validate-platform    (run: make validate-platform)"

validate-platform: configure-kubectl ## Validate platform applications deployment
	@echo "=== Checking Platform ApplicationSet ==="
	kubectl get applicationset -n argocd
	@echo "\n=== Checking Platform Applications ==="
	kubectl get applications -n argocd
	@echo "\n=== Checking Backstage ==="
	kubectl get pods -n backstage || echo "Backstage not deployed yet"
	kubectl get ingress -n backstage || echo "Backstage ingress not created yet"
	@echo "\n=== Checking DNS ==="
	@BACKSTAGE_DOMAIN=$$(yq eval '.infrastructure.backstageDomain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo "Testing DNS for: $$BACKSTAGE_DOMAIN"; \
	dig +short $$BACKSTAGE_DOMAIN
	@echo "\nNext steps:"
	@echo "  [x] apply-gitops"
	@echo "  [x] bootstrap-platform"
	@echo "  [x] install-backstage"
	@echo "  [x] validate-platform"

install-app-platform: init-gitops ## Install app platform components (Terraform-managed kubectl_manifests)
	@echo "=== Installing App Platform Components (Terraform) ==="
	@$(ENV_LOADER); \
	export TF_VAR_github_token=$$GITHUB_TOKEN; \
	export TF_VAR_cognito_admin_temp_password=$$COGNITO_ADMIN_TEMP_PASSWORD; \
	export TF_VAR_github_app_id=$${GITHUB_APP_ID:-}; \
	export TF_VAR_github_app_installation_id=$${GITHUB_APP_INSTALLATION_ID:-}; \
	export TF_VAR_github_app_private_key=$${GITHUB_APP_PRIVATE_KEY:-}; \
	cd terraform/platform-gitops && terraform apply -auto-approve \
		-target=kubernetes_secret.argocd_scm_token \
		-target=kubectl_manifest.apps_project \
		-target=kubectl_manifest.workloads_appset
	@echo "✅ App platform components installed"
	@echo "\nMonitor workload discovery:"
	@echo "  kubectl get applications -n argocd -l platform.darede.io/workload=true -w"

validate-app-platform: configure-kubectl ## Validate app platform (AppProject + ApplicationSet)
	@echo "=== Checking AppProject ==="
	kubectl get appproject apps -n argocd
	@echo "\n=== Checking Workloads ApplicationSet ==="
	kubectl get applicationset workloads -n argocd
	@echo "\n=== Checking Discovered Workloads ==="
	kubectl get applications -n argocd -l platform.darede.io/workload=true || echo "No workloads discovered yet"
	@echo "\n✅ App platform validation complete"

destroy-app-platform: configure-kubectl ## Remove app platform (AppProject + ApplicationSet)
	@echo "=== Removing Workloads ApplicationSet ==="
	kubectl delete applicationset workloads -n argocd --ignore-not-found
	@echo "=== Removing AppProject ==="
	kubectl delete appproject apps -n argocd --ignore-not-found
	@echo "\n✅ App platform components removed"

validate-backstage: ## Validate Backstage deps + build (deterministic)
	@echo "==> Validating Backstage (yarn install --immutable + build)"
	@cd $(BACKSTAGE_DIR) && \
		corepack enable && \
		corepack yarn install --immutable && \
		corepack yarn tsc && \
		corepack yarn build:backend

build-backstage-image: ## Build Backstage ARM64 image from backstage-custom/
	@echo "==> Building Backstage image: $(BACKSTAGE_IMAGE)"
	@cd $(BACKSTAGE_DIR) && \
		docker buildx build --platform $(BACKSTAGE_PLATFORM) \
			-f packages/backend/Dockerfile \
			-t $(BACKSTAGE_IMAGE) --load .

push-backstage-image: build-backstage-image ## Push Backstage image to ECR (uses awsProfile from config)
	@echo "==> Pushing Backstage image: $(BACKSTAGE_IMAGE)"
	@PROFILE=$$(yq eval '.infrastructure.awsProfile' $(CONFIG_FILE)); \
	REGION=$$(yq eval '.infrastructure.awsRegion' $(CONFIG_FILE)); \
	aws ecr get-login-password --region $$REGION --profile $$PROFILE | \
		docker login --username AWS --password-stdin $(BACKSTAGE_IMAGE_REGISTRY)
	docker push $(BACKSTAGE_IMAGE)

get-credentials: ## Show all login credentials
	@echo "=== ArgoCD Admin ==="
	@cd terraform/platform-gitops && terraform output -json argocd_admin_credentials | jq -r
	@echo "\n=== ArgoCD Cognito SSO ==="
	@cd terraform/platform-gitops && terraform output -json cognito_admin_credentials | jq -r 2>/dev/null || echo "(Run terraform apply first)"
	@echo "\n=== Backstage ==="
	@BACKSTAGE_DOMAIN=$$(yq eval '.infrastructure.backstageDomain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo "URL: https://$$BACKSTAGE_DOMAIN"; \
	echo "Login: Cognito SSO (same credentials as ArgoCD)"

##@ Complete workflows

install: apply-vpc apply-eks apply-addons apply-gitops configure-kubectl validate validate-gitops ## Install everything (VPC -> EKS -> Addons -> GitOps)
	@echo "\n✅ Platform infrastructure deployed successfully"
	@DOMAIN=$$(yq eval '.infrastructure.domain' config/platform-params.yaml 2>/dev/null || echo ""); \
	echo "\n🎯 Access ArgoCD: https://argocd.$$DOMAIN"
	@echo "\n📝 Create admin user:"
	@cd terraform/platform-gitops && terraform output -raw create_admin_user_command

destroy: destroy-gitops destroy-addons destroy-eks destroy-vpc ## Destroy everything (GitOps -> Addons -> EKS -> VPC)
	@echo "\n✅ All infrastructure destroyed"
