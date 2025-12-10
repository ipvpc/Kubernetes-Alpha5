# Automated Kubernetes Installation Script (PowerShell)
# This script uses Ansible to install Kubernetes on remote hosts
# Usage: .\scripts\install-kubernetes.ps1 [environment] [install_method]
# Example: .\scripts\install-kubernetes.ps1 manager kubeadm

param(
    [Parameter(Position=0)]
    [string]$Environment = "manager",
    
    [Parameter(Position=1)]
    [ValidateSet("kubeadm", "k3s")]
    [string]$InstallMethod = "kubeadm"
)

$ErrorActionPreference = "Stop"
$InventoryFile = "ansible\inventory.yml"

Write-Host "==========================================" -ForegroundColor Green
Write-Host "Kubernetes Automated Installation" -ForegroundColor Green
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Install Method: $InstallMethod" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Green

# Function to check and install Ansible
function Check-AndInstall-Ansible {
    try {
        $ansibleVersion = ansible-playbook --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Ansible is installed: $($ansibleVersion[0])" -ForegroundColor Green
            return $true
        }
    } catch {
        # Ansible not found, continue to installation
    }
    
    Write-Host "Ansible is not installed. Attempting to install..." -ForegroundColor Yellow
    
    # Check if Python is installed
    $pythonCmd = $null
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $pythonCmd = "python"
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        $pythonCmd = "python3"
    } else {
        Write-Host "Error: Python is not installed. Please install Python 3.x first." -ForegroundColor Red
        Write-Host "Download from: https://www.python.org/downloads/" -ForegroundColor Yellow
        exit 1
    }
    
    # Check if pip is available
    $pipCmd = $null
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        $pipCmd = "pip"
    } elseif (Get-Command pip3 -ErrorAction SilentlyContinue) {
        $pipCmd = "pip3"
    } else {
        Write-Host "Error: pip is not installed. Please install pip first." -ForegroundColor Red
        exit 1
    }
    
    # Install Ansible
    Write-Host "Installing Ansible..." -ForegroundColor Yellow
    & $pipCmd install --user ansible
    
    # Verify installation
    $env:Path = "$env:USERPROFILE\AppData\Local\Programs\Python\Python*\Scripts;$env:Path"
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    
    try {
        $ansibleVersion = ansible-playbook --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Ansible installed successfully" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "Error: Ansible installation failed. Please install manually:" -ForegroundColor Red
        Write-Host "  pip install ansible" -ForegroundColor Yellow
        exit 1
    }
    
    return $false
}

# Function to check and install Terraform
function Check-AndInstall-Terraform {
    try {
        $terraformVersion = terraform version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Terraform is installed: $($terraformVersion[0])" -ForegroundColor Green
            return $true
        }
    } catch {
        # Terraform not found, continue to installation
    }
    
    Write-Host "Terraform is not installed. Attempting to install..." -ForegroundColor Yellow
    
    # Try Chocolatey first (common on Windows)
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Installing Terraform via Chocolatey..." -ForegroundColor Yellow
        choco install terraform -y
    } else {
        # Manual installation
        Write-Host "Chocolatey not found. Downloading Terraform manually..." -ForegroundColor Yellow
        
        $terraformVersion = "1.6.0"
        $terraformUrl = "https://releases.hashicorp.com/terraform/${terraformVersion}/terraform_${terraformVersion}_windows_amd64.zip"
        $downloadPath = "$env:TEMP\terraform.zip"
        $installPath = "$env:USERPROFILE\.terraform\bin"
        
        # Create install directory
        if (-not (Test-Path $installPath)) {
            New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        }
        
        # Download Terraform
        Write-Host "Downloading Terraform..." -ForegroundColor Yellow
        try {
            Invoke-WebRequest -Uri $terraformUrl -OutFile $downloadPath -UseBasicParsing
        } catch {
            Write-Host "Error: Failed to download Terraform. Please install manually:" -ForegroundColor Red
            Write-Host "  Download from: https://www.terraform.io/downloads" -ForegroundColor Yellow
            exit 1
        }
        
        # Extract Terraform
        Write-Host "Extracting Terraform..." -ForegroundColor Yellow
        Expand-Archive -Path $downloadPath -DestinationPath $installPath -Force
        Remove-Item $downloadPath -Force
        
        # Add to PATH for current session
        $env:Path = "$installPath;$env:Path"
        
        # Add to user PATH permanently
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$installPath*") {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$installPath", "User")
        }
    }
    
    # Verify installation
    try {
        $terraformVersion = terraform version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Terraform installed successfully" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "Error: Terraform installation failed. Please install manually:" -ForegroundColor Red
        Write-Host "  Download from: https://www.terraform.io/downloads" -ForegroundColor Yellow
        exit 1
    }
    
    return $false
}

# Check and install dependencies
Write-Host "Checking dependencies..." -ForegroundColor Green
Check-AndInstall-Ansible
Check-AndInstall-Terraform

# Ensure Ansible is in PATH
$env:Path = "$env:USERPROFILE\AppData\Local\Programs\Python\Python*\Scripts;$env:Path"
$env:Path = "$env:USERPROFILE\.local\bin;$env:Path"

# Check if inventory file exists
if (-not (Test-Path $InventoryFile)) {
    Write-Host "Error: Inventory file not found: $InventoryFile" -ForegroundColor Red
    Write-Host "Please copy ansible\inventory.example.yml to ansible\inventory.yml and configure your hosts" -ForegroundColor Yellow
    exit 1
}

# Check if ansible.cfg exists
if (-not (Test-Path "ansible\ansible.cfg")) {
    Write-Host "Creating ansible.cfg..." -ForegroundColor Yellow
    @"
[defaults]
inventory = inventory.yml
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
"@ | Out-File -FilePath "ansible\ansible.cfg" -Encoding utf8
}

# Update install_method in group_vars if different
if (Test-Path "ansible\group_vars\all.yml") {
    $content = Get-Content "ansible\group_vars\all.yml"
    $currentMethod = ($content | Select-String "^install_method:").ToString() -replace ".*install_method:\s*['`"]?([^'`"]*)['`"]?.*", '$1'
    
    if ($currentMethod -ne $InstallMethod) {
        Write-Host "Updating install_method to $InstallMethod..." -ForegroundColor Yellow
        $content = $content -replace "^(install_method:).*", "install_method: `"$InstallMethod`""
        $content | Set-Content "ansible\group_vars\all.yml"
    }
}

# Run Ansible playbook
Write-Host "Running Ansible playbook..." -ForegroundColor Green
Set-Location ansible

switch ($InstallMethod) {
    "kubeadm" {
        ansible-playbook playbooks\kubeadm-install.yml -i inventory.yml
    }
    "k3s" {
        ansible-playbook playbooks\k3s-install.yml -i inventory.yml
    }
    default {
        Write-Host "Error: Unsupported install method: $InstallMethod" -ForegroundColor Red
        Write-Host "Supported methods: kubeadm, k3s" -ForegroundColor Yellow
        Set-Location ..
        exit 1
    }
}

Set-Location ..

# Get kubeconfig from first master
Write-Host "Retrieving kubeconfig..." -ForegroundColor Green

# Try to get first master from inventory
$inventoryContent = Get-Content $InventoryFile -Raw
$firstMaster = $null

if ($inventoryContent -match "control_plane:\s*\n\s*hosts:\s*\n\s*(\w+):") {
    $firstMaster = $matches[1]
}

if ($firstMaster) {
    Write-Host "Downloading kubeconfig from $firstMaster..." -ForegroundColor Yellow
    
    $kubeconfigPath = "$env:USERPROFILE\.kube\config-$Environment"
    $kubeconfigDir = Split-Path $kubeconfigPath -Parent
    
    if (-not (Test-Path $kubeconfigDir)) {
        New-Item -ItemType Directory -Path $kubeconfigDir -Force | Out-Null
    }
    
    ansible $firstMaster -i ansible\inventory.yml -m fetch `
        -a "src=/root/.kube/config dest=$kubeconfigPath flat=yes" `
        --become
    
    if (Test-Path $kubeconfigPath) {
        if ($InstallMethod -eq "k3s") {
            # Update server URL for k3s
            $masterHost = (ansible-inventory -i ansible\inventory.yml --host $firstMaster | ConvertFrom-Json).ansible_host
            (Get-Content $kubeconfigPath) -replace "127\.0\.0\.1:6443", "$masterHost`:6443" | Set-Content $kubeconfigPath
        }
        
        Write-Host "Kubeconfig saved to $kubeconfigPath" -ForegroundColor Green
        Write-Host "To use this cluster, run:" -ForegroundColor Yellow
        Write-Host "  `$env:KUBECONFIG='$kubeconfigPath'" -ForegroundColor Cyan
        Write-Host "  kubectl get nodes" -ForegroundColor Cyan
    }
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "Kubernetes installation completed!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# Verify cluster
if (Test-Path $kubeconfigPath) {
    Write-Host "Verifying cluster..." -ForegroundColor Green
    $env:KUBECONFIG = $kubeconfigPath
    kubectl get nodes
    Write-Host ""
    Write-Host "Cluster is ready! You can now deploy Rancher." -ForegroundColor Green
}
