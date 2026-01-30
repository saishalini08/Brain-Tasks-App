# Quick AWS EKS Deployment

$ErrorActionPreference = "Continue"

# Configuration
$REGION = "ap-south-1"
$CLUSTER_NAME = "brain-tasks-cluster"
$IMAGE_NAME = "brain-tasks-app"
$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text).Trim()
$ECR_REGISTRY = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "AWS EKS DEPLOYMENT - Brain Tasks App" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Account: $ACCOUNT_ID" -ForegroundColor Green
Write-Host "Region: $REGION" -ForegroundColor Green
Write-Host "ECR: $ECR_REGISTRY/$IMAGE_NAME" -ForegroundColor Green
Write-Host ""

# Step 1: Check if cluster exists
Write-Host "STEP 1: Checking cluster status..." -ForegroundColor Yellow
$clusterExists = aws eks list-clusters --region $REGION --query "clusters[?contains(@, 'brain-tasks')]" --output text 2>&1
if ($clusterExists) {
    Write-Host "Cluster found: $clusterExists" -ForegroundColor Green
    $CLUSTER_NAME = $clusterExists.Trim()
} else {
    Write-Host "No existing cluster found, creating new cluster..." -ForegroundColor Yellow
    
    # Get default VPC and subnets
    $VPC = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --region $REGION --query "Vpcs[0].VpcId" --output text 2>&1
    if (-not $VPC -or $VPC -eq "None") {
        Write-Host "ERROR: No default VPC found" -ForegroundColor Red
        exit 1
    }
    Write-Host "Using VPC: $VPC" -ForegroundColor Green
    
    $SUBNETS = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --region $REGION --query "Subnets[0:2].SubnetId" --output text 2>&1
    if (-not $SUBNETS) {
        Write-Host "ERROR: No subnets found" -ForegroundColor Red
        exit 1
    }
    Write-Host "Using Subnets: $SUBNETS" -ForegroundColor Green
    
    # Create cluster
    Write-Host "Creating EKS cluster (this takes 15-20 minutes)..." -ForegroundColor Yellow
    aws eks create-cluster `
        --name $CLUSTER_NAME `
        --version 1.28 `
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/brain-tasks-eks-cluster-role" `
        --resources-vpc-config "subnetIds=$SUBNETS" `
        --region $REGION 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Cluster creation initiated" -ForegroundColor Green
    } else {
        Write-Host "Note: Cluster may already exist" -ForegroundColor Yellow
    }
}

# Step 2: Wait for cluster to be ACTIVE
Write-Host ""
Write-Host "STEP 2: Waiting for cluster to be ACTIVE..." -ForegroundColor Yellow
$maxAttempts = 60
$attempt = 0

while ($attempt -lt $maxAttempts) {
    try {
        $statusOutput = aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.status' --output text 2>&1
        if ($statusOutput -eq "ACTIVE") {
            Write-Host "Cluster is ACTIVE!" -ForegroundColor Green
            break
        }
        Write-Host "Status: $statusOutput (attempt $($attempt + 1)/$maxAttempts)"
    }
    catch {
        Write-Host "Status: Creating... (attempt $($attempt + 1)/$maxAttempts)"
    }
    Start-Sleep -Seconds 30
    $attempt++
}

if ($attempt -ge $maxAttempts) {
    Write-Host "WARNING: Cluster not yet ACTIVE, but continuing with deployment..." -ForegroundColor Yellow
}

# Step 3: Update kubeconfig
Write-Host ""
Write-Host "STEP 3: Updating kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION 2>&1 | Out-Null
$kube_check = kubectl cluster-info 2>&1
if ($kube_check -like "*running*") {
    Write-Host "kubeconfig updated successfully" -ForegroundColor Green
} else {
    Write-Host "WARNING: kubectl may not be fully connected yet" -ForegroundColor Yellow
}

# Step 4: Create node group
Write-Host ""
Write-Host "STEP 4: Creating node group..." -ForegroundColor Yellow
aws eks create-nodegroup `
    --cluster-name $CLUSTER_NAME `
    --nodegroup-name "brain-tasks-ng" `
    --scaling-config minSize=2,maxSize=4,desiredSize=3 `
    --node-role "arn:aws:iam::${ACCOUNT_ID}:role/brain-tasks-eks-node-role" `
    --instance-types "t3.medium" `
    --region $REGION 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Node group creation initiated" -ForegroundColor Green
} else {
    Write-Host "Note: Node group may already exist" -ForegroundColor Yellow
}

Write-Host "Waiting for nodes to be ready (this takes 10-15 minutes)..." -ForegroundColor Yellow
$maxAttempts = 50
$attempt = 0

while ($attempt -lt $maxAttempts) {
    $nodes = kubectl get nodes --no-headers 2>&1
    if ($nodes -like "*Ready*") {
        $readyCount = ($nodes | Select-String "Ready" | Measure-Object).Count
        if ($readyCount -ge 3) {
            Write-Host "All nodes are Ready!" -ForegroundColor Green
            break
        }
        Write-Host "Ready nodes: $readyCount/3 (attempt $($attempt + 1)/$maxAttempts)"
    } else {
        Write-Host "Waiting for nodes (attempt $($attempt + 1)/$maxAttempts)"
    }
    
    Start-Sleep -Seconds 30
    $attempt++
}

# Step 5: Create image pull secret
Write-Host ""
Write-Host "STEP 5: Creating image pull secret..." -ForegroundColor Yellow
$ecrPassword = aws ecr get-login-password --region $REGION 2>&1
kubectl create secret docker-registry ecr-secret `
    --docker-server="$ECR_REGISTRY" `
    --docker-username="AWS" `
    --docker-password="$ecrPassword" `
    --docker-email="user@example.com" `
    --namespace=default 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Image pull secret created" -ForegroundColor Green
} else {
    Write-Host "Note: Secret may already exist" -ForegroundColor Yellow
}

# Step 6: Update and deploy Kubernetes manifests
Write-Host ""
Write-Host "STEP 6: Deploying application to Kubernetes..." -ForegroundColor Yellow

# Update deployment manifest with correct image
$deploymentFile = "k8s-manifests/deployment.yaml"
if (Test-Path $deploymentFile) {
    $content = Get-Content $deploymentFile -Raw
    $content = $content -replace "ACCOUNT_ID\.dkr\.ecr\.REGION\.amazonaws\.com/brain-tasks-app:latest", "$ECR_REGISTRY/$IMAGE_NAME:latest"
    $content | Set-Content $deploymentFile -Encoding UTF8 -Force
    Write-Host "Deployment manifest updated with ECR image" -ForegroundColor Green
}

# Apply manifests
kubectl apply -f k8s-manifests/deployment.yaml 2>&1 | Out-Null
kubectl apply -f k8s-manifests/service.yaml 2>&1 | Out-Null
Write-Host "Kubernetes manifests applied" -ForegroundColor Green

# Step 7: Wait for pods
Write-Host ""
Write-Host "STEP 7: Waiting for pods to be Running..." -ForegroundColor Yellow
$maxAttempts = 30
$attempt = 0

while ($attempt -lt $maxAttempts) {
    $pods = kubectl get pods -l app=brain-tasks-app --field-selector=status.phase=Running --no-headers 2>&1
    if ($pods) {
        $runningCount = ($pods | Measure-Object).Count
        if ($runningCount -ge 3) {
            Write-Host "All pods are Running!" -ForegroundColor Green
            break
        }
        Write-Host "Running pods: $runningCount/3 (attempt $($attempt + 1)/$maxAttempts)"
    } else {
        Write-Host "Waiting for pods (attempt $($attempt + 1)/$maxAttempts)"
    }
    
    Start-Sleep -Seconds 10
    $attempt++
}

# Step 8: Get LoadBalancer URL
Write-Host ""
Write-Host "STEP 8: Getting LoadBalancer URL..." -ForegroundColor Yellow
$maxAttempts = 40
$attempt = 0
$LoadBalancerUrl = ""

while ($attempt -lt $maxAttempts) {
    try {
        $svcOutput = kubectl get svc brain-tasks-app-service -o json 2>&1
        if ($svcOutput -notlike "*error*" -and $svcOutput -notlike "*Error*") {
            $svc = $svcOutput | ConvertFrom-Json
            $LoadBalancerUrl = $svc.status.loadBalancer.ingress[0].hostname
        }
    }
    catch {}
    
    if ($LoadBalancerUrl) {
        Write-Host "LoadBalancer URL obtained!" -ForegroundColor Green
        break
    }
    
    Write-Host "Waiting for LoadBalancer URL (attempt $($attempt + 1)/$maxAttempts)"
    Start-Sleep -Seconds 30
    $attempt++
}

# Final Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Deployment Details:" -ForegroundColor Cyan
Write-Host "  Account ID: $ACCOUNT_ID"
Write-Host "  Region: $REGION"
Write-Host "  Cluster: $CLUSTER_NAME"
Write-Host "  ECR Image: $ECR_REGISTRY/$IMAGE_NAME:latest"
Write-Host ""

if ($LoadBalancerUrl) {
    Write-Host "========== APP URL ==========" -ForegroundColor Yellow
    Write-Host "http://$LoadBalancerUrl" -ForegroundColor Green
    Write-Host "===========================" -ForegroundColor Yellow
} else {
    Write-Host "LoadBalancer URL not yet available" -ForegroundColor Yellow
    Write-Host "Check again with: kubectl get svc brain-tasks-app-service" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  kubectl get pods -l app=brain-tasks-app"
Write-Host "  kubectl logs -l app=brain-tasks-app -f"
Write-Host "  kubectl get svc brain-tasks-app-service"
Write-Host "  kubectl get nodes"
Write-Host ""
