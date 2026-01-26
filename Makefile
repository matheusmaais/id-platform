.PHONY: help init-all init-vpc init-eks init-addons plan-all plan-vpc plan-eks plan-addons \
        apply-vpc apply-eks apply-addons destroy-addons destroy-eks destroy-vpc destroy-cluster \
        configure-kubectl validate test-karpenter install destroy

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

init-all: init-vpc init-eks init-addons ## Initialize all Terraform modules

##@ Infrastructure - Plan

plan-vpc: init-vpc ## Plan VPC changes
	cd terraform/vpc && terraform plan

plan-eks: init-eks ## Plan EKS changes
	cd terraform/eks && terraform plan

plan-addons: init-addons ## Plan addons changes
	cd terraform/addons && terraform plan

plan-all: plan-vpc plan-eks plan-addons ## Plan all changes

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

##@ Infrastructure - Destroy (order: Addons -> EKS -> VPC)

destroy-addons: init-addons ## Destroy addons (Karpenter, NodePool, EC2NodeClass)
	@echo "==> Destroying Addons..."
	cd terraform/addons && terraform destroy -auto-approve

destroy-eks: init-eks ## Destroy EKS cluster and node groups
	@echo "==> Destroying EKS..."
	cd terraform/eks && terraform destroy -auto-approve

destroy-vpc: init-vpc ## Destroy VPC (requires EKS destroyed first)
	@echo "==> Destroying VPC..."
	cd terraform/vpc && terraform destroy -auto-approve

destroy-cluster: destroy-addons destroy-eks ## Destroy EKS + Addons only (keeps VPC)
	@echo "\n✅ EKS cluster and addons destroyed. VPC preserved."

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

##@ Complete workflows

install: apply-vpc apply-eks apply-addons configure-kubectl validate ## Install everything (VPC -> EKS -> Addons)
	@echo "\n✅ Platform infrastructure deployed successfully"

destroy: destroy-addons destroy-eks destroy-vpc ## Destroy everything (Addons -> EKS -> VPC)
	@echo "\n✅ All infrastructure destroyed"
