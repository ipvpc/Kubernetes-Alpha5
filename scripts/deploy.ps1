# Terraform Kubernetes Deployment Script (PowerShell)
# Usage: .\scripts\deploy.ps1 [environment] [action]
# Example: .\scripts\deploy.ps1 dev plan

param(
    [Parameter(Position=0)]
    [ValidateSet("dev", "staging", "prod")]
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

