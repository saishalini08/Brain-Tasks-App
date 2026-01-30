# Brain Tasks App - Windows Deployment Script
# Simplified version that focuses on core deployment

param(
    [string]$AwsRegion = "ap-south-1"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "BRAIN TASKS APP - DEPLOYMENT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow
$tools = @("git", "aws", "docker", "kubectl")
foreach ($tool in $tools) {
    try {
        $null = & $tool --version 2>&1
        Write-Host "✅ $tool is installed" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ $tool is NOT installed" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Verifying AWS credentials..." -ForegroundColor Yellow
try {
    $account = & aws sts get-caller-identity --query Account --output text 2>&1
    if ($account -match "^[0-9]+$") {
        Write-Host "✅ AWS credentials configured - Account: $account" -ForegroundColor Green
    } else {
        Write-Host "❌ AWS credentials not valid" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "❌ AWS credentials error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Starting deployment process..." -ForegroundColor Cyan
Write-Host ""

# Run the bash script
Write-Host "Running deployment script..." -ForegroundColor Yellow
bash deploy.sh

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✅ DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "❌ DEPLOYMENT FAILED!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit $LASTEXITCODE
}
