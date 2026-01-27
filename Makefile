.PHONY: help init-all init-vpc init-eks init-addons init-gitops plan-all plan-vpc plan-eks plan-addons plan-gitops \
        apply-vpc apply-eks apply-addons apply-gitops destroy-addons destroy-eks destroy-vpc destroy-gitops destroy-cluster \
        configure-kubectl validate validate-gitops test-karpenter install destroy

AWS_PROFILE := darede
AWS_REGION := us-east-1
CLUSTER_NAME := platform-eks

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

##@ Infrastructure - Init

init-vpc: ## Initialize VPC Terraform
	@echo "==> Initializing VPC..."
	cd terraform/vpc && terraform init -reconfigure -backend-config="profile=$(AWS_PROFILE)"

init-eks: ## Initialize EKS Terraform
	@echo "==> Initializing EKS..."
	cd terraform/eks && terraform init -reconfigure -backend-config="profile=$(AWS_PROFILE)"

init-addons: ## Initialize Addons Terraform
	@echo "==> Initializing Addons..."
	cd terraform/addons && terraform init -reconfigure -backend-config="profile=$(AWS_PROFILE)"

init-gitops: ## Initialize Platform GitOps Terraform
	@echo "==> Initializing Platform GitOps..."
	cd terraform/platform-gitops && terraform init -reconfigure -backend-config="profile=$(AWS_PROFILE)"

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
	cd terraform/vpc && terraform apply -auto-approve

apply-eks: init-eks ## Apply EKS infrastructure (requires VPC)
	@echo "==> Applying EKS..."
	cd terraform/eks && terraform apply -auto-approve

apply-addons: init-addons ## Apply addons - Karpenter, NodePool, EC2NodeClass (requires EKS)
	@echo "==> Applying Addons..."
	cd terraform/addons && terraform apply -auto-approve

apply-gitops: init-gitops ## Apply platform GitOps - Cognito, ArgoCD, AWS LB Controller, External-DNS (requires Addons)
	@echo "==> Applying Platform GitOps..."
	cd terraform/platform-gitops && terraform apply -auto-approve
	@echo "==> Waiting for ArgoCD server..."
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || true
	@echo "\n✅ GitOps stack deployed: https://argocd.timedevops.click"

##@ Infrastructure - Destroy (order: GitOps -> Addons -> EKS -> VPC)

destroy-gitops: init-gitops ## Destroy platform GitOps stack
	@echo "==> Destroying Platform GitOps..."
	@echo "Deleting ArgoCD applications first..."
	kubectl delete applications --all -n argocd --ignore-not-found || true
	@sleep 10
	cd terraform/platform-gitops && terraform destroy -auto-approve

destroy-addons: init-addons ## Destroy addons (Karpenter, NodePool, EC2NodeClass)
	@echo "==> Destroying Addons..."
	cd terraform/addons && terraform destroy -auto-approve

destroy-eks: init-eks ## Destroy EKS cluster and node groups
	@echo "==> Destroying EKS..."
	cd terraform/eks && terraform destroy -auto-approve

destroy-vpc: init-vpc ## Destroy VPC (requires EKS destroyed first)
	@echo "==> Destroying VPC..."
	cd terraform/vpc && terraform destroy -auto-approve

destroy-cluster: destroy-gitops destroy-addons destroy-eks ## Destroy GitOps + EKS + Addons only (keeps VPC)
	@echo "\n✅ GitOps, EKS cluster and addons destroyed. VPC preserved."

##@ Kubernetes

configure-kubectl: ## Configure kubectl for EKS cluster
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME) --profile $(AWS_PROFILE)

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
	dig +short argocd.timedevops.click
	@echo "\n=== Checking ArgoCD Applications ==="
	kubectl get applications -n argocd
	@echo "\n=== ArgoCD URL ==="
	@echo "https://argocd.timedevops.click"

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

bootstrap-platform: configure-kubectl ## Create platform-apps ApplicationSet
	@echo "=== Creating Platform ApplicationSet ==="
	kubectl apply -f argocd-apps/platform/backstage-appset.yaml
	@echo "✅ ApplicationSet created. ArgoCD will sync automatically."
	@echo "Monitor: kubectl get applications -n argocd -w"

install-backstage: bootstrap-platform ## Install Backstage (via ApplicationSet)
	@echo "=== Waiting for Backstage Application ==="
	kubectl wait --for=condition=Ready application/backstage -n argocd --timeout=60s || true
	@echo "=== Checking Backstage sync status ==="
	kubectl get application backstage -n argocd
	@echo "\n=== Waiting for Backstage pods ==="
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=300s || true
	@echo "\n✅ Backstage deployed"
	@echo "URL: https://backstage.timedevops.click"

validate-platform: configure-kubectl ## Validate platform applications
	@echo "=== Checking Platform ApplicationSet ==="
	kubectl get applicationset -n argocd
	@echo "\n=== Checking Platform Applications ==="
	kubectl get applications -n argocd
	@echo "\n=== Checking Backstage ==="
	kubectl get pods -n backstage
	kubectl get ingress -n backstage
	@echo "\n=== Checking DNS ==="
	dig +short backstage.timedevops.click

get-credentials: ## Show all login credentials
	@echo "=== ArgoCD Admin ==="
	@cd terraform/platform-gitops && terraform output -json argocd_admin_credentials | jq -r
	@echo "\n=== ArgoCD Cognito SSO ==="
	@cd terraform/platform-gitops && terraform output -json cognito_admin_credentials | jq -r 2>/dev/null || echo "(Run terraform apply first)"
	@echo "\n=== Backstage ==="
	@echo "URL: https://backstage.timedevops.click"
	@echo "Login: Cognito SSO (same credentials as ArgoCD)"

##@ Complete workflows

install: apply-vpc apply-eks apply-addons apply-gitops configure-kubectl validate validate-gitops ## Install everything (VPC -> EKS -> Addons -> GitOps)
	@echo "\n✅ Platform infrastructure deployed successfully"
	@echo "\n🎯 Access ArgoCD: https://argocd.timedevops.click"
	@echo "\n📝 Create admin user:"
	@cd terraform/platform-gitops && terraform output -raw create_admin_user_command

destroy: destroy-gitops destroy-addons destroy-eks destroy-vpc ## Destroy everything (GitOps -> Addons -> EKS -> VPC)
	@echo "\n✅ All infrastructure destroyed"
