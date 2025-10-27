.PHONY: help bootstrap init plan apply deploy destroy clean validate fmt lint check test

# ============================================================================
# InfraForge GitOps Makefile
# ============================================================================
# Organize all infrastructure operations with simple make commands
#
# Usage:
#   make help       - Show this help message
#   make bootstrap  - Create S3 bucket and DynamoDB table
#   make init       - Initialize Terraform
#   make plan       - Plan infrastructure changes
#   make apply      - Apply infrastructure changes
#   make deploy     - Full deployment (bootstrap + init + apply)
#   make destroy    - Destroy all infrastructure
#   make clean      - Clean up Terraform files
# ============================================================================

# Configuration
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Directories
TERRAFORM_DIR := terraform
SCRIPTS_DIR := scripts
CONFIG_DIR := config

# Colors for output
RESET := \033[0m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RED := \033[31m

# Helper function to print colored output
define print_header
	@echo -e "$(GREEN)============================================$(RESET)"
	@echo -e "$(GREEN)  $(1)$(RESET)"
	@echo -e "$(GREEN)============================================$(RESET)"
endef

define print_info
	@echo -e "$(BLUE)[INFO]$(RESET) $(1)"
endef

define print_success
	@echo -e "$(GREEN)[SUCCESS]$(RESET) $(1)"
endef

define print_warning
	@echo -e "$(YELLOW)[WARNING]$(RESET) $(1)"
endef

define print_error
	@echo -e "$(RED)[ERROR]$(RESET) $(1)"
endef

# ============================================================================
# Main Targets
# ============================================================================

## help: Show this help message
help:
	@echo ""
	$(call print_header,InfraForge GitOps - Available Commands)
	@echo ""
	@echo "Setup Commands:"
	@echo "  make bootstrap      - Create S3 bucket and DynamoDB table for Terraform state"
	@echo "  make init           - Initialize Terraform (after bootstrap)"
	@echo ""
	@echo "Infrastructure Commands:"
	@echo "  make validate       - Validate Terraform configuration"
	@echo "  make fmt            - Format Terraform files"
	@echo "  make plan           - Show infrastructure changes"
	@echo "  make apply          - Apply infrastructure changes"
	@echo "  make deploy         - Full deployment (bootstrap + init + apply)"
	@echo ""
	@echo "Destroy Commands:"
	@echo "  make destroy        - Destroy all infrastructure (with confirmation)"
	@echo "  make destroy-force  - Destroy without confirmation (DANGEROUS!)"
	@echo "  make clean          - Clean up Terraform cache files"
	@echo ""
	@echo "Kubernetes Commands:"
	@echo "  make kubeconfig     - Update kubeconfig for EKS cluster"
	@echo "  make k8s-status     - Show Kubernetes cluster status"
	@echo "  make argocd-ui      - Open ArgoCD UI (port-forward)"
	@echo "  make grafana-ui     - Open Grafana UI (port-forward)"
	@echo ""
	@echo "Application Commands:"
	@echo "  make create-app     - Create new application from template"
	@echo "  make list-apps      - List all applications"
	@echo "  make deploy-app     - Deploy application to ArgoCD"
	@echo "  make app-status     - Show application status in ArgoCD"
	@echo ""
	@echo "Cleanup Commands:"
	@echo "  make cleanup-ns     - Clean up stuck Kubernetes namespaces"
	@echo "  make full-cleanup   - Full infrastructure cleanup (interactive)"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make check          - Run all checks (validate + fmt-check + lint)"
	@echo "  make outputs        - Show Terraform outputs"
	@echo "  make state          - Show Terraform state"
	@echo "  make cost           - Estimate infrastructure costs (requires infracost)"
	@echo ""

## bootstrap: Create S3 bucket and DynamoDB table for Terraform backend
bootstrap:
	$(call print_header,Bootstrap Terraform Backend)
	@$(SCRIPTS_DIR)/bootstrap-backend.sh

## init: Initialize Terraform
init:
	$(call print_header,Initialize Terraform)
	@cd $(TERRAFORM_DIR) && tofu init -upgrade

## validate: Validate Terraform configuration
validate:
	$(call print_header,Validate Terraform Configuration)
	@cd $(TERRAFORM_DIR) && tofu validate

## fmt: Format Terraform files
fmt:
	$(call print_header,Format Terraform Files)
	@cd $(TERRAFORM_DIR) && tofu fmt -recursive

## fmt-check: Check if Terraform files are formatted
fmt-check:
	$(call print_header,Check Terraform Formatting)
	@cd $(TERRAFORM_DIR) && tofu fmt -recursive -check

## plan: Show infrastructure changes
plan: validate
	$(call print_header,Plan Infrastructure Changes)
	@cd $(TERRAFORM_DIR) && tofu plan

## plan-out: Save plan to file
plan-out: validate
	$(call print_header,Generate Terraform Plan)
	@cd $(TERRAFORM_DIR) && tofu plan -out=tfplan
	$(call print_success,Plan saved to terraform/tfplan)

## apply: Apply infrastructure changes
apply:
	$(call print_header,Apply Infrastructure Changes)
	$(call print_warning,This will make changes to your AWS infrastructure!)
	@read -p "Are you sure? (yes/no): " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		cd $(TERRAFORM_DIR) && tofu apply; \
	else \
		$(call print_info,Apply cancelled); \
	fi

## apply-auto: Apply without confirmation (use with caution!)
apply-auto:
	$(call print_header,Apply Infrastructure Changes (Auto-approve))
	@cd $(TERRAFORM_DIR) && tofu apply -auto-approve

## deploy: Full deployment (bootstrap + init + apply)
deploy: bootstrap init plan
	$(call print_header,Full Deployment)
	$(call print_warning,This will deploy the entire infrastructure!)
	@read -p "Continue with apply? (yes/no): " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		$(MAKE) apply-auto; \
		$(call print_success,Deployment complete!); \
	else \
		$(call print_info,Deployment cancelled); \
	fi

## destroy: Destroy all infrastructure
destroy:
	$(call print_header,Destroy Infrastructure)
	$(call print_warning,This will DESTROY ALL infrastructure!)
	@$(SCRIPTS_DIR)/full-cleanup.sh

## destroy-force: Destroy without interactive prompts (DANGEROUS!)
destroy-force:
	$(call print_header,Force Destroy Infrastructure)
	@cd $(TERRAFORM_DIR) && tofu destroy -auto-approve

## clean: Clean up Terraform cache files
clean:
	$(call print_header,Clean Terraform Files)
	$(call print_info,Removing .terraform directories...)
	@find $(TERRAFORM_DIR) -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	$(call print_info,Removing lock files...)
	@find $(TERRAFORM_DIR) -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	$(call print_info,Removing plan files...)
	@find $(TERRAFORM_DIR) -type f -name "tfplan*" -delete 2>/dev/null || true
	$(call print_success,Cleanup complete!)

# ============================================================================
# Kubernetes Commands
# ============================================================================

## kubeconfig: Update kubeconfig for EKS cluster
kubeconfig:
	$(call print_header,Update Kubeconfig)
	@aws eks update-kubeconfig --region eu-west-1 --name infraforge-eks

## k8s-status: Show Kubernetes cluster status
k8s-status: kubeconfig
	$(call print_header,Kubernetes Cluster Status)
	@echo ""
	@echo "Cluster Info:"
	@kubectl cluster-info
	@echo ""
	@echo "Nodes:"
	@kubectl get nodes
	@echo ""
	@echo "Namespaces:"
	@kubectl get namespaces
	@echo ""
	@echo "Pods (all namespaces):"
	@kubectl get pods --all-namespaces

## argocd-ui: Open ArgoCD UI (port-forward)
argocd-ui: kubeconfig
	$(call print_header,ArgoCD UI)
	$(call print_info,Opening ArgoCD UI at http://localhost:8080)
	$(call print_info,Username: admin)
	$(call print_info,Password: Run 'kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d')
	@kubectl port-forward svc/argocd-server -n argocd 8080:443

## grafana-ui: Open Grafana UI (port-forward)
grafana-ui: kubeconfig
	$(call print_header,Grafana UI)
	$(call print_info,Opening Grafana UI at http://localhost:3000)
	$(call print_info,Username: admin)
	$(call print_info,Password: From Secrets Manager)
	@kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

## prometheus-ui: Open Prometheus UI (port-forward)
prometheus-ui: kubeconfig
	$(call print_header,Prometheus UI)
	$(call print_info,Opening Prometheus UI at http://localhost:9090)
	@kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

# ============================================================================
# Cleanup Commands
# ============================================================================

## cleanup-ns: Clean up stuck Kubernetes namespaces
cleanup-ns:
	$(call print_header,Cleanup Stuck Namespaces)
	@$(SCRIPTS_DIR)/cleanup-namespaces.sh

## full-cleanup: Full infrastructure cleanup (interactive)
full-cleanup:
	$(call print_header,Full Infrastructure Cleanup)
	@$(SCRIPTS_DIR)/full-cleanup.sh

# ============================================================================
# Utility Commands
# ============================================================================

## check: Run all checks (validate + fmt-check)
check: validate fmt-check
	$(call print_success,All checks passed!)

## outputs: Show Terraform outputs
outputs:
	$(call print_header,Terraform Outputs)
	@cd $(TERRAFORM_DIR) && tofu output

## state: Show Terraform state
state:
	$(call print_header,Terraform State)
	@cd $(TERRAFORM_DIR) && tofu state list

## state-show: Show detailed state for a resource
state-show:
	@read -p "Enter resource name: " resource && \
	cd $(TERRAFORM_DIR) && tofu state show $$resource

## cost: Estimate infrastructure costs (requires infracost)
cost:
	$(call print_header,Infrastructure Cost Estimate)
	@if command -v infracost &> /dev/null; then \
		cd $(TERRAFORM_DIR) && infracost breakdown --path .; \
	else \
		$(call print_error,infracost is not installed); \
		$(call print_info,Install from: https://www.infracost.io/docs/); \
	fi

## graph: Generate Terraform dependency graph
graph:
	$(call print_header,Generate Terraform Graph)
	@cd $(TERRAFORM_DIR) && tofu graph | dot -Tpng > infrastructure-graph.png
	$(call print_success,Graph saved to terraform/infrastructure-graph.png)

## lint: Lint configuration files
lint:
	$(call print_header,Lint Configuration Files)
	@if command -v tflint &> /dev/null; then \
		cd $(TERRAFORM_DIR) && tflint; \
	else \
		$(call print_warning,tflint is not installed, skipping); \
	fi
	@if command -v yamllint &> /dev/null; then \
		yamllint $(CONFIG_DIR)/; \
	else \
		$(call print_warning,yamllint is not installed, skipping); \
	fi

## tfsec: Run security checks
tfsec:
	$(call print_header,Security Scan)
	@if command -v tfsec &> /dev/null; then \
		cd $(TERRAFORM_DIR) && tfsec .; \
	else \
		$(call print_error,tfsec is not installed); \
		$(call print_info,Install from: https://github.com/aquasecurity/tfsec); \
	fi

# ============================================================================
# Development Commands
# ============================================================================

## watch: Watch for changes and plan
watch:
	$(call print_header,Watch Mode)
	@while true; do \
		inotifywait -r -e modify $(TERRAFORM_DIR) 2>/dev/null || \
		fswatch -1 -r $(TERRAFORM_DIR) 2>/dev/null; \
		$(MAKE) plan; \
	done

## docs: Generate documentation
docs:
	$(call print_header,Generate Documentation)
	@if command -v terraform-docs &> /dev/null; then \
		terraform-docs markdown table $(TERRAFORM_DIR) > $(TERRAFORM_DIR)/README.md; \
		$(call print_success,Documentation generated in terraform/README.md); \
	else \
		$(call print_error,terraform-docs is not installed); \
		$(call print_info,Install from: https://terraform-docs.io/); \
	fi

# ============================================================================
# Quick Start
# ============================================================================

## quickstart: Quick setup for new environments
quickstart:
	$(call print_header,Quick Start Setup)
	$(call print_info,Step 1: Bootstrapping backend...)
	@$(MAKE) bootstrap
	@echo ""
	$(call print_info,Step 2: Initializing Terraform...)
	@$(MAKE) init
	@echo ""
	$(call print_info,Step 3: Validating configuration...)
	@$(MAKE) validate
	@echo ""
	$(call print_success,Setup complete! Run 'make plan' to see what will be created.)

# ============================================================================
# CI/CD Integration
# ============================================================================

## ci-check: CI validation (no changes)
ci-check: fmt-check validate
	$(call print_header,CI Checks)
	$(call print_success,CI checks passed!)

## ci-plan: CI plan (with formatted output)
ci-plan: validate
	$(call print_header,CI Plan)
	@cd $(TERRAFORM_DIR) && tofu plan -no-color

## ci-apply: CI apply (auto-approve)
ci-apply:
	$(call print_header,CI Apply)
	@cd $(TERRAFORM_DIR) && tofu apply -auto-approve -no-color

# ============================================================================
# Application Management
# ============================================================================

## create-app: Create new application from template
create-app:
	$(call print_header,Create New Application)
	@$(SCRIPTS_DIR)/create-app.sh

## list-apps: List all applications
list-apps:
	$(call print_header,Applications)
	@echo ""
	@echo "Local Applications:"
	@find applications -maxdepth 1 -mindepth 1 -type d ! -name '_template' ! -name 'argocd-apps' -exec basename {} \;
	@echo ""
	@echo "ArgoCD Applications:"
	@kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not accessible (run 'make kubeconfig' first)"

## deploy-app: Deploy application to ArgoCD
deploy-app:
	$(call print_header,Deploy Application)
	@read -p "Enter application name: " app_name && \
	read -p "Enter environment (dev/prod): " env && \
	if [ -f "applications/argocd-apps/$$app_name-$$env.yaml" ]; then \
		kubectl apply -f applications/argocd-apps/$$app_name-$$env.yaml; \
		$(call print_success,Application deployed: $$app_name-$$env); \
	else \
		$(call print_error,Application manifest not found: $$app_name-$$env); \
		exit 1; \
	fi

## app-status: Show application status in ArgoCD
app-status: kubeconfig
	$(call print_header,Application Status)
	@kubectl get applications -n argocd
	@echo ""
	@read -p "Enter application name for details (or press Enter to skip): " app_name && \
	if [ -n "$$app_name" ]; then \
		kubectl describe application $$app_name -n argocd; \
	fi

## app-logs: Show application logs
app-logs: kubeconfig
	$(call print_header,Application Logs)
	@read -p "Enter application name: " app_name && \
	read -p "Enter namespace (dev/production): " namespace && \
	kubectl logs -n $$namespace -l app=$$app_name --tail=100 -f

## app-restart: Restart application
app-restart: kubeconfig
	$(call print_header,Restart Application)
	@read -p "Enter application name: " app_name && \
	read -p "Enter namespace (dev/production): " namespace && \
	kubectl rollout restart deployment $$app_name -n $$namespace && \
	$(call print_success,Rollout initiated for $$app_name)
