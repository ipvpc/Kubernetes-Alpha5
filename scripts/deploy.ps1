# Terraform Kubernetes Deployment Script (PowerShell)
# Usage: .\scripts\deploy.ps1 [environment] [action]
# Example: .\scripts\deploy.ps1 dev plan

param(
    [Parameter(Position=0)]
    [ValidateSet("dev", "staging", "prod", "manager")]
    [string]$Environment = "dev",
    
    [Parameter(Position=1)]
    [ValidateSet("init", "plan", "apply", "destroy", "validate")]
    [string]$Action = "plan"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Terraform Kubernetes Deployment" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Action: $Action" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

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

# Check Terraform installation
Write-Host "Checking dependencies..." -ForegroundColor Green
Check-AndInstall-Terraform

Set-Location terraform

# Initialize Terraform
if ($Action -ne "init") {
    Write-Host "Initializing Terraform..." -ForegroundColor Green
    terraform init
}

# Run Terraform action
switch ($Action) {
    "init" {
        Write-Host "Initializing Terraform..." -ForegroundColor Green
        terraform init
    }
    "plan" {
        Write-Host "Planning Terraform deployment..." -ForegroundColor Green
        terraform plan `
            -var-file="../environments/$Environment/terraform.tfvars" `
            -out="tfplan-$Environment"
    }
    "apply" {
        if (Test-Path "tfplan-$Environment") {
            Write-Host "Applying Terraform plan..." -ForegroundColor Green
            terraform apply "tfplan-$Environment"
        } else {
            Write-Host "No plan file found. Running terraform apply..." -ForegroundColor Yellow
            terraform apply `
                -var-file="../environments/$Environment/terraform.tfvars" `
                -auto-approve
        }
    }
    "destroy" {
        Write-Host "WARNING: This will destroy all resources in $Environment environment!" -ForegroundColor Red
        $confirm = Read-Host "Are you sure? (yes/no)"
        if ($confirm -eq "yes") {
            terraform destroy `
                -var-file="../environments/$Environment/terraform.tfvars" `
                -auto-approve
        } else {
            Write-Host "Destroy cancelled." -ForegroundColor Yellow
        }
    }
    "validate" {
        Write-Host "Validating Terraform configuration..." -ForegroundColor Green
        terraform validate
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment completed!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan

Set-Location ..

