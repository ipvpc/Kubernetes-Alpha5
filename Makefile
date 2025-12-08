.PHONY: help init plan apply destroy validate clean

ENVIRONMENT ?= dev
ACTION ?= plan

help:
	@echo "Terraform Kubernetes Deployment"
	@echo ""
	@echo "Usage: make [target] [ENVIRONMENT=env] [ACTION=action]"
	@echo ""
	@echo "Targets:"
	@echo "  init      - Initialize Terraform"
	@echo "  plan      - Plan Terraform deployment"
	@echo "  apply     - Apply Terraform configuration"
	@echo "  destroy   - Destroy Terraform resources"
	@echo "  validate  - Validate Terraform configuration"
	@echo "  clean     - Clean Terraform files"
	@echo ""
	@echo "Environments: dev, staging, prod"
	@echo "Actions: init, plan, apply, destroy, validate"

init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan \
		-var-file="../environments/$(ENVIRONMENT)/terraform.tfvars" \
		-out="tfplan-$(ENVIRONMENT)"

apply:
	@if [ -f "terraform/tfplan-$(ENVIRONMENT)" ]; then \
		cd terraform && terraform apply "tfplan-$(ENVIRONMENT)"; \
	else \
		cd terraform && terraform apply \
			-var-file="../environments/$(ENVIRONMENT)/terraform.tfvars" \
			-auto-approve; \
	fi

destroy:
	@echo "WARNING: This will destroy all resources in $(ENVIRONMENT) environment!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	cd terraform && terraform destroy \
		-var-file="../environments/$(ENVIRONMENT)/terraform.tfvars" \
		-auto-approve

validate:
	cd terraform && terraform validate

clean:
	rm -rf terraform/.terraform
	rm -f terraform/.terraform.lock.hcl
	rm -f terraform/*.tfplan
	rm -f terraform/*.tfstate
	rm -f terraform/*.tfstate.backup

