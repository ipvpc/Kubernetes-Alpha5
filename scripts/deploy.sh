#!/bin/bash

# Terraform Kubernetes Deployment Script
# Usage: ./scripts/deploy.sh [environment] [action]
# Example: ./scripts/deploy.sh dev plan

set -e

ENVIRONMENT=${1:-dev}
ACTION=${2:-plan}

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "Error: Environment must be one of: dev, staging, prod"
    exit 1
fi

if [[ ! "$ACTION" =~ ^(init|plan|apply|destroy|validate)$ ]]; then
    echo "Error: Action must be one of: init, plan, apply, destroy, validate"
    exit 1
fi

echo "=========================================="
echo "Terraform Kubernetes Deployment"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "=========================================="

cd terraform

# Initialize Terraform
if [ "$ACTION" != "init" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Run Terraform action
case $ACTION in
    init)
        echo "Initializing Terraform..."
        terraform init
        ;;
    plan)
        echo "Planning Terraform deployment..."
        terraform plan \
            -var-file="../environments/$ENVIRONMENT/terraform.tfvars" \
            -out="tfplan-$ENVIRONMENT"
        ;;
    apply)
        if [ -f "tfplan-$ENVIRONMENT" ]; then
            echo "Applying Terraform plan..."
            terraform apply "tfplan-$ENVIRONMENT"
        else
            echo "No plan file found. Running terraform apply..."
            terraform apply \
                -var-file="../environments/$ENVIRONMENT/terraform.tfvars" \
                -auto-approve
        fi
        ;;
    destroy)
        echo "WARNING: This will destroy all resources in $ENVIRONMENT environment!"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            terraform destroy \
                -var-file="../environments/$ENVIRONMENT/terraform.tfvars" \
                -auto-approve
        else
            echo "Destroy cancelled."
        fi
        ;;
    validate)
        echo "Validating Terraform configuration..."
        terraform validate
        ;;
esac

echo "=========================================="
echo "Deployment completed!"
echo "=========================================="

