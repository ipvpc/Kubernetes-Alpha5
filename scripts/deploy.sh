#!/bin/bash

# Terraform Kubernetes Deployment Script
# Usage: ./scripts/deploy.sh [environment] [action]
# Example: ./scripts/deploy.sh dev plan

set -e

ENVIRONMENT=${1:-manager}
ACTION=${2:-plan}

case "$ENVIRONMENT" in
    dev|staging|prod|manager)
        ;;
    *)
        echo "Error: Environment must be one of: dev, staging, prod, manager"
        exit 1
        ;;
esac

case "$ACTION" in
    init|plan|apply|destroy|validate)
        ;;
    *)
        echo "Error: Action must be one of: init, plan, apply, destroy, validate"
        exit 1
        ;;
esac

echo "=========================================="
echo "Terraform Kubernetes Deployment"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "=========================================="

# Function to check and install Terraform
check_and_install_terraform() {
    if command -v terraform &> /dev/null; then
        TERRAFORM_VERSION=$(terraform version | head -n1)
        echo "✓ Terraform is installed: $TERRAFORM_VERSION"
        return 0
    fi
    
    echo "Terraform is not installed. Attempting to install..."
    
    # Detect OS
    OS=$(uname -s)
    ARCH=$(uname -m)
    
    # Map architecture
    case $ARCH in
        x86_64) TERRAFORM_ARCH="amd64" ;;
        arm64|aarch64) TERRAFORM_ARCH="arm64" ;;
        *) TERRAFORM_ARCH="amd64" ;;
    esac
    
    # Install Terraform based on OS
    if [ "$OS" == "Linux" ]; then
        TERRAFORM_VERSION="1.6.0"
        TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip"
        
        echo "Downloading Terraform..."
        cd /tmp
        curl -LO "$TERRAFORM_URL" || wget "$TERRAFORM_URL"
        unzip -o terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
        sudo mv terraform /usr/local/bin/
        rm terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
        cd - > /dev/null
        
    elif [ "$OS" == "Darwin" ]; then
        # macOS - try Homebrew first
        if command -v brew &> /dev/null; then
            echo "Installing Terraform via Homebrew..."
            brew install terraform
        else
            # Fallback to manual download
            TERRAFORM_VERSION="1.6.0"
            TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_darwin_${TERRAFORM_ARCH}.zip"
            
            echo "Downloading Terraform..."
            cd /tmp
            curl -LO "$TERRAFORM_URL"
            unzip -o terraform_${TERRAFORM_VERSION}_darwin_${TERRAFORM_ARCH}.zip
            sudo mv terraform /usr/local/bin/
            rm terraform_${TERRAFORM_VERSION}_darwin_${TERRAFORM_ARCH}.zip
            cd - > /dev/null
        fi
    else
        echo "Error: Unsupported OS: $OS"
        echo "Please install Terraform manually from https://www.terraform.io/downloads"
        exit 1
    fi
    
    # Verify installation
    if command -v terraform &> /dev/null; then
        echo "✓ Terraform installed successfully"
        return 0
    else
        echo "Error: Terraform installation failed. Please install manually."
        exit 1
    fi
}

# Function to check and install Helm
check_and_install_helm() {
    if command -v helm &> /dev/null; then
        HELM_VERSION=$(helm version --short 2>/dev/null || helm version | head -n1)
        echo "✓ Helm is installed: $HELM_VERSION"
        return 0
    fi
    
    echo "Helm is not installed. Attempting to install..."
    
    # Detect OS
    OS=$(uname -s)
    ARCH=$(uname -m)
    
    # Map architecture
    case $ARCH in
        x86_64) HELM_ARCH="amd64" ;;
        arm64|aarch64) HELM_ARCH="arm64" ;;
        *) HELM_ARCH="amd64" ;;
    esac
    
    # Install Helm based on OS
    if [ "$OS" == "Linux" ]; then
        HELM_VERSION="3.13.0"
        HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
        
        echo "Downloading Helm..."
        cd /tmp
        curl -LO "$HELM_URL" || wget "$HELM_URL"
        tar -zxvf helm-v${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz
        sudo mv linux-${HELM_ARCH}/helm /usr/local/bin/
        rm -rf linux-${HELM_ARCH} helm-v${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz
        cd - > /dev/null
        
    elif [ "$OS" == "Darwin" ]; then
        # macOS - try Homebrew first
        if command -v brew &> /dev/null; then
            echo "Installing Helm via Homebrew..."
            brew install helm
        else
            # Fallback to manual download
            HELM_VERSION="3.13.0"
            HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-darwin-${HELM_ARCH}.tar.gz"
            
            echo "Downloading Helm..."
            cd /tmp
            curl -LO "$HELM_URL"
            tar -zxvf helm-v${HELM_VERSION}-darwin-${HELM_ARCH}.tar.gz
            sudo mv darwin-${HELM_ARCH}/helm /usr/local/bin/
            rm -rf darwin-${HELM_ARCH} helm-v${HELM_VERSION}-darwin-${HELM_ARCH}.tar.gz
            cd - > /dev/null
        fi
    else
        echo "Error: Unsupported OS: $OS"
        echo "Please install Helm manually from https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    # Verify installation
    if command -v helm &> /dev/null; then
        echo "✓ Helm installed successfully"
        return 0
    else
        echo "Error: Helm installation failed. Please install manually."
        exit 1
    fi
}

# Check dependencies
echo "Checking dependencies..."
check_and_install_terraform
check_and_install_helm

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
            echo "Checking if saved plan is still valid..."
            # Check if plan is stale by trying to validate it
            if terraform show "tfplan-$ENVIRONMENT" >/dev/null 2>&1; then
                echo "Applying saved Terraform plan..."
                terraform apply "tfplan-$ENVIRONMENT"
            else
                echo "Saved plan is stale. Regenerating plan..."
                terraform plan \
                    -var-file="../environments/$ENVIRONMENT/terraform.tfvars" \
                    -out="tfplan-$ENVIRONMENT"
                echo "Applying new plan..."
                terraform apply "tfplan-$ENVIRONMENT"
            fi
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

