#!/bin/bash

# Automated Kubernetes Installation Script
# This script uses Ansible to install Kubernetes on remote hosts
# Usage: ./scripts/install-kubernetes.sh [environment] [install_method]
# Example: ./scripts/install-kubernetes.sh manager kubeadm

set -e

ENVIRONMENT=${1:-manager}
INSTALL_METHOD=${2:-kubeadm}
INVENTORY_FILE="ansible/inventory-mgt.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "Kubernetes Automated Installation"
echo "Environment: $ENVIRONMENT"
echo "Install Method: $INSTALL_METHOD"
echo "==========================================${NC}"

# Function to check and install Ansible
check_and_install_ansible() {
    if command -v ansible-playbook &> /dev/null; then
        ANSIBLE_VERSION=$(ansible-playbook --version | head -n1)
        echo -e "${GREEN}✓ Ansible is installed: $ANSIBLE_VERSION${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Ansible is not installed. Attempting to install...${NC}"
    
    # Detect Python and pip
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        PIP_CMD="pip3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
        PIP_CMD="pip"
    else
        echo -e "${RED}Error: Python is not installed. Please install Python 3.x first.${NC}"
        exit 1
    fi
    
    # Check if pip is available
    if ! command -v $PIP_CMD &> /dev/null; then
        echo -e "${YELLOW}pip is not installed. Installing pip...${NC}"
        if [ "$(uname)" = "Darwin" ]; then
            # macOS
            if command -v brew &> /dev/null; then
                brew install python3
            else
                echo -e "${RED}Error: Homebrew not found. Please install pip manually.${NC}"
                exit 1
            fi
        else
            # Linux
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y python3-pip
            elif command -v yum &> /dev/null; then
                sudo yum install -y python3-pip
            else
                echo -e "${RED}Error: Could not detect package manager. Please install pip manually.${NC}"
                exit 1
            fi
        fi
    fi
    
    # Install Ansible
    echo -e "${YELLOW}Installing Ansible...${NC}"
    $PIP_CMD install --user ansible || sudo $PIP_CMD install ansible
    
    # Verify installation
    if command -v ansible-playbook &> /dev/null; then
        echo -e "${GREEN}✓ Ansible installed successfully${NC}"
        return 0
    else
        # Try adding user bin to PATH
        export PATH="$HOME/.local/bin:$PATH"
        if command -v ansible-playbook &> /dev/null; then
            echo -e "${GREEN}✓ Ansible installed successfully${NC}"
            echo -e "${YELLOW}Note: Added ~/.local/bin to PATH for this session${NC}"
            return 0
        else
            echo -e "${RED}Error: Ansible installation failed. Please install manually:${NC}"
            echo "  pip install ansible"
            exit 1
        fi
    fi
}

# Function to check and install Terraform
check_and_install_terraform() {
    if command -v terraform &> /dev/null; then
        TERRAFORM_VERSION=$(terraform version | head -n1)
        echo -e "${GREEN}✓ Terraform is installed: $TERRAFORM_VERSION${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Terraform is not installed. Attempting to install...${NC}"
    
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
    if [ "$OS" = "Linux" ]; then
        TERRAFORM_VERSION="1.6.0"
        TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip"
        
        echo -e "${YELLOW}Downloading Terraform...${NC}"
        cd /tmp
        curl -LO "$TERRAFORM_URL" || wget "$TERRAFORM_URL"
        unzip -o terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
        sudo mv terraform /usr/local/bin/
        rm terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip
        cd - > /dev/null
        
    elif [ "$OS" = "Darwin" ]; then
        # macOS - try Homebrew first
        if command -v brew &> /dev/null; then
            echo -e "${YELLOW}Installing Terraform via Homebrew...${NC}"
            brew install terraform
        else
            # Fallback to manual download
            TERRAFORM_VERSION="1.6.0"
            TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_darwin_${TERRAFORM_ARCH}.zip"
            
            echo -e "${YELLOW}Downloading Terraform...${NC}"
            cd /tmp
            curl -LO "$TERRAFORM_URL"
            unzip -o terraform_${TERRAFORM_VERSION}_darwin_${TERRAFORM_ARCH}.zip
            sudo mv terraform /usr/local/bin/
            rm terraform_${TERRAFORM_VERSION}_darwin_${TERRAFORM_ARCH}.zip
            cd - > /dev/null
        fi
    else
        echo -e "${RED}Error: Unsupported OS: $OS${NC}"
        echo "Please install Terraform manually from https://www.terraform.io/downloads"
        exit 1
    fi
    
    # Verify installation
    if command -v terraform &> /dev/null; then
        echo -e "${GREEN}✓ Terraform installed successfully${NC}"
        return 0
    else
        echo -e "${RED}Error: Terraform installation failed. Please install manually.${NC}"
        exit 1
    fi
}

# Check and install dependencies
echo -e "${GREEN}Checking dependencies...${NC}"
check_and_install_ansible
check_and_install_terraform

# Ensure ansible-playbook is in PATH
export PATH="$HOME/.local/bin:$PATH"

# Check if inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
    echo -e "${RED}Error: Inventory file not found: $INVENTORY_FILE${NC}"
    echo -e "${YELLOW}Please copy ansible/inventory.example.yml to ansible/inventory.yml and configure your hosts${NC}"
    exit 1
fi

# Check if ansible.cfg exists
if [ ! -f "ansible/ansible.cfg" ]; then
    echo -e "${YELLOW}Creating ansible.cfg...${NC}"
    cat > ansible/ansible.cfg << EOF
[defaults]
inventory = inventory.yml
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
EOF
fi

# Update install_method in group_vars if different
if [ -f "ansible/group_vars/all.yml" ]; then
    CURRENT_METHOD=$(grep "^install_method:" ansible/group_vars/all.yml | awk '{print $2}' | tr -d '"')
    if [ "$CURRENT_METHOD" != "$INSTALL_METHOD" ]; then
        echo -e "${YELLOW}Updating install_method to $INSTALL_METHOD...${NC}"
        sed -i.bak "s/^install_method:.*/install_method: \"$INSTALL_METHOD\"/" ansible/group_vars/all.yml
    fi
fi

# Run Ansible playbook
echo -e "${GREEN}Running Ansible playbook...${NC}"
cd ansible

case $INSTALL_METHOD in
    kubeadm)
        ansible-playbook playbooks/kubeadm-install.yml -i inventory.yml
        ;;
    k3s)
        ansible-playbook playbooks/k3s-install.yml -i inventory.yml
        ;;
    *)
        echo -e "${RED}Error: Unsupported install method: $INSTALL_METHOD${NC}"
        echo "Supported methods: kubeadm, k3s"
        exit 1
        ;;
esac

cd ..

# Get kubeconfig from first master
echo -e "${GREEN}Retrieving kubeconfig...${NC}"
FIRST_MASTER=$(ansible-inventory -i ansible/inventory.yml --list | jq -r '.control_plane.hosts[0] // empty')

if [ -n "$FIRST_MASTER" ]; then
    echo -e "${YELLOW}Downloading kubeconfig from $FIRST_MASTER...${NC}"
    
    if [ "$INSTALL_METHOD" = "k3s" ]; then
        ansible $FIRST_MASTER -i ansible/inventory.yml -m fetch \
            -a "src=/root/.kube/config dest=~/.kube/config-$ENVIRONMENT flat=yes" \
            --become
    else
        ansible $FIRST_MASTER -i ansible/inventory.yml -m fetch \
            -a "src=/root/.kube/config dest=~/.kube/config-$ENVIRONMENT flat=yes" \
            --become
    fi
    
    # Update kubeconfig context name
    if [ -f ~/.kube/config-$ENVIRONMENT ]; then
        if [ "$INSTALL_METHOD" = "k3s" ]; then
            # Update server URL for k3s
            MASTER_IP=$(ansible-inventory -i ansible/inventory.yml --host $FIRST_MASTER | jq -r '.ansible_host')
            sed -i.bak "s/127\.0\.0\.1:6443/$MASTER_IP:6443/g" ~/.kube/config-$ENVIRONMENT
        fi
        
        # Set context name
        kubectl config --kubeconfig=~/.kube/config-$ENVIRONMENT rename-context default $ENVIRONMENT 2>/dev/null || true
        
        echo -e "${GREEN}Kubeconfig saved to ~/.kube/config-$ENVIRONMENT${NC}"
        echo -e "${YELLOW}To use this cluster, run:${NC}"
        echo "  export KUBECONFIG=~/.kube/config-$ENVIRONMENT"
        echo "  kubectl get nodes"
    fi
fi

echo -e "${GREEN}=========================================="
echo "Kubernetes installation completed!"
echo "==========================================${NC}"

# Verify cluster
if [ -f ~/.kube/config-$ENVIRONMENT ]; then
    echo -e "${GREEN}Verifying cluster...${NC}"
    export KUBECONFIG=~/.kube/config-$ENVIRONMENT
    kubectl get nodes
    echo ""
    echo -e "${GREEN}Cluster is ready! You can now deploy Rancher.${NC}"
fi
