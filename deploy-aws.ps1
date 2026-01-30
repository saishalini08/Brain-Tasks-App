param(
    [string]$AwsRegion = "ap-south-1"
)

# Setup
$ErrorActionPreference = "Continue"
$ImageName = "brain-tasks-app"
$ClusterName = "brain-tasks-cluster"
$EcrRegistry = ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "AWS EKS DEPLOYMENT - Brain Tasks App" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify AWS
Write-Host "STEP 1: Verifying AWS credentials..." -ForegroundColor Yellow
try {
    $AwsAccountId = aws sts get-caller-identity --query Account --output text
    if (-not $AwsAccountId -or $AwsAccountId -like "*Error*") {
        throw "Invalid AWS credentials"
    }
    Write-Host "AWS Account: $AwsAccountId" -ForegroundColor Green
    $EcrRegistry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
} catch {
    Write-Host "ERROR: AWS credentials not valid" -ForegroundColor Red
    exit 1
}

Write-Host "Region: $AwsRegion" -ForegroundColor Green
Write-Host "ECR Registry: $EcrRegistry" -ForegroundColor Green
Write-Host ""

# Step 2: Build Docker image
Write-Host "STEP 2: Building Docker image..." -ForegroundColor Yellow
try {
    docker build -t ${ImageName}:latest . --quiet
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
    Write-Host "Docker image built successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Docker build failed: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 3: Create ECR repository
Write-Host "STEP 3: Creating ECR repository..." -ForegroundColor Yellow
aws ecr create-repository --repository-name $ImageName --region $AwsRegion 2>&1 | Out-Null
Write-Host "ECR repository ready: $EcrRegistry/$ImageName" -ForegroundColor Green
Write-Host ""

# Step 4: Push to ECR
Write-Host "STEP 4: Pushing image to ECR..." -ForegroundColor Yellow
try {
    $loginCmd = aws ecr get-login-password --region $AwsRegion 2>&1
    $loginCmd | docker login --username AWS --password-stdin $EcrRegistry 2>&1 | Out-Null
    docker tag ${ImageName}:latest ${EcrRegistry}/${ImageName}:latest 2>&1 | Out-Null
    docker push ${EcrRegistry}/${ImageName}:latest 2>&1 | Out-Null
    Write-Host "Image pushed successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to push to ECR: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 5: Create IAM roles
Write-Host "STEP 5: Creating IAM roles..." -ForegroundColor Yellow

$eksTrust = @'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "eks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
'@

$eksTrust | Out-File -FilePath "$env:TEMP\eks-trust.json" -Encoding UTF8 -Force
aws iam create-role --role-name brain-tasks-eks-cluster-role --assume-role-policy-document "file://$env:TEMP\eks-trust.json" 2>&1 | Out-Null
aws iam attach-role-policy --role-name brain-tasks-eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>&1 | Out-Null

$nodeTrust = @'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
'@

$nodeTrust | Out-File -FilePath "$env:TEMP\node-trust.json" -Encoding UTF8 -Force
aws iam create-role --role-name brain-tasks-eks-node-role --assume-role-policy-document "file://$env:TEMP\node-trust.json" 2>&1 | Out-Null
aws iam attach-role-policy --role-name brain-tasks-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>&1 | Out-Null
aws iam attach-role-policy --role-name brain-tasks-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>&1 | Out-Null
aws iam attach-role-policy --role-name brain-tasks-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>&1 | Out-Null

Write-Host "IAM roles created" -ForegroundColor Green
Write-Host ""

# Step 6: Create VPC and Subnets
Write-Host "STEP 6: Creating VPC and subnets..." -ForegroundColor Yellow

$vpcId = aws ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16" --region $AwsRegion --query "Vpcs[0].VpcId" --output text 2>&1
if ($vpcId -eq "None" -or [string]::IsNullOrEmpty($vpcId)) {
    $vpcId = aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $AwsRegion --query "Vpc.VpcId" --output text 2>&1
    Write-Host "VPC created: $vpcId" -ForegroundColor Green
} else {
    Write-Host "VPC exists: $vpcId" -ForegroundColor Green
}

$subnet1 = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.1.0/24 --availability-zone "${AwsRegion}a" --region $AwsRegion --query "Subnet.SubnetId" --output text 2>&1
if ($subnet1 -like "*InvalidParameterValue*") {
    $subnet1 = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" "Name=cidr-block,Values=10.0.1.0/24" --region $AwsRegion --query "Subnets[0].SubnetId" --output text 2>&1
}

$subnet2 = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.2.0/24 --availability-zone "${AwsRegion}b" --region $AwsRegion --query "Subnet.SubnetId" --output text 2>&1
if ($subnet2 -like "*InvalidParameterValue*") {
    $subnet2 = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" "Name=cidr-block,Values=10.0.2.0/24" --region $AwsRegion --query "Subnets[0].SubnetId" --output text 2>&1
}

Write-Host "Subnets created: $subnet1, $subnet2" -ForegroundColor Green
Write-Host ""

# Step 7: Create EKS Cluster
Write-Host "STEP 7: Creating EKS cluster (15-20 minutes)..." -ForegroundColor Yellow

$clusterStatus = aws eks describe-cluster --name $ClusterName --region $AwsRegion --query "cluster.status" --output text 2>&1
if ($clusterStatus -ne "ACTIVE" -and $clusterStatus -ne "CREATING") {
    aws eks create-cluster `
        --name $ClusterName `
        --version 1.28 `
        --role-arn "arn:aws:iam::${AwsAccountId}:role/brain-tasks-eks-cluster-role" `
        --resources-vpc-config "subnetIds=$subnet1,$subnet2" `
        --region $AwsRegion 2>&1 | Out-Null
    Write-Host "Cluster creation initiated" -ForegroundColor Green
} else {
    Write-Host "Cluster already exists: $clusterStatus" -ForegroundColor Green
}

Write-Host "Waiting for cluster to be ACTIVE..." -ForegroundColor Yellow
$maxRetries = 50
$retry = 0
while ($retry -lt $maxRetries) {
    $status = aws eks describe-cluster --name $ClusterName --region $AwsRegion --query "cluster.status" --output text 2>&1
    if ($status -eq "ACTIVE") {
        Write-Host "Cluster is ACTIVE" -ForegroundColor Green
        break
    }
    Write-Host "Status: $status (attempt $retry/$maxRetries)"
    Start-Sleep -Seconds 30
    $retry++
}

if ($retry -ge $maxRetries) {
    Write-Host "ERROR: Cluster creation timeout" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 8: Update kubeconfig
Write-Host "STEP 8: Updating kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig --name $ClusterName --region $AwsRegion 2>&1 | Out-Null
kubectl cluster-info 2>&1 | Out-Null
Write-Host "kubeconfig updated" -ForegroundColor Green
Write-Host ""

# Step 9: Create Node Group
Write-Host "STEP 9: Creating node group (10-15 minutes)..." -ForegroundColor Yellow

aws eks create-nodegroup `
    --cluster-name $ClusterName `
    --nodegroup-name brain-tasks-nodegroup `
    --scaling-config minSize=2,maxSize=4,desiredSize=3 `
    --subnets $subnet1 $subnet2 `
    --node-role "arn:aws:iam::${AwsAccountId}:role/brain-tasks-eks-node-role" `
    --instance-types t3.medium `
    --region $AwsRegion 2>&1 | Out-Null

Write-Host "Waiting for nodes to be Ready..." -ForegroundColor Yellow
$maxRetries = 50
$retry = 0
while ($retry -lt $maxRetries) {
    $nodes = kubectl get nodes --no-headers 2>&1 | Select-String "Ready" | Measure-Object
    if ($nodes.Count -ge 3) {
        Write-Host "All 3 nodes are Ready" -ForegroundColor Green
        break
    }
    Write-Host "Ready nodes: $($nodes.Count)/3 (attempt $retry/$maxRetries)"
    Start-Sleep -Seconds 30
    $retry++
}
Write-Host ""

# Step 10: Create ImagePullSecret
Write-Host "STEP 10: Creating ImagePullSecret..." -ForegroundColor Yellow
$ecrPassword = aws ecr get-login-password --region $AwsRegion 2>&1
kubectl create secret docker-registry ecr-secret `
    --docker-server=$EcrRegistry `
    --docker-username=AWS `
    --docker-password=$ecrPassword `
    --docker-email=user@example.com `
    --namespace=default 2>&1 | Out-Null
Write-Host "ImagePullSecret created" -ForegroundColor Green
Write-Host ""

# Step 11: Deploy to Kubernetes
Write-Host "STEP 11: Deploying to Kubernetes..." -ForegroundColor Yellow

$deploymentFile = "k8s-manifests/deployment.yaml"
if (Test-Path $deploymentFile) {
    $content = Get-Content $deploymentFile -Raw
    $content = $content -replace "ACCOUNT_ID\.dkr\.ecr\.REGION\.amazonaws\.com/brain-tasks-app:latest", "${EcrRegistry}/${ImageName}:latest"
    $content | Set-Content $deploymentFile -Encoding UTF8
}

kubectl apply -f k8s-manifests/deployment.yaml 2>&1 | Out-Null
kubectl apply -f k8s-manifests/service.yaml 2>&1 | Out-Null
Write-Host "Manifests applied" -ForegroundColor Green

Write-Host "Waiting for pods to be Running..." -ForegroundColor Yellow
$maxRetries = 30
$retry = 0
while ($retry -lt $maxRetries) {
    $pods = kubectl get pods -l app=brain-tasks-app --field-selector=status.phase=Running --no-headers 2>&1 | Measure-Object
    if ($pods.Count -ge 3) {
        Write-Host "All 3 pods are Running" -ForegroundColor Green
        break
    }
    Write-Host "Running pods: $($pods.Count)/3 (attempt $retry/$maxRetries)"
    Start-Sleep -Seconds 10
    $retry++
}
Write-Host ""

# Step 12: Get LoadBalancer URL
Write-Host "STEP 12: Getting LoadBalancer URL (5-10 minutes)..." -ForegroundColor Yellow
$maxRetries = 40
$retry = 0
$LoadBalancerUrl = ""
while ($retry -lt $maxRetries) {
    $LoadBalancerUrl = kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>&1
    if ($LoadBalancerUrl -and $LoadBalancerUrl -notlike "*items*" -and $LoadBalancerUrl -notlike "*<*") {
        Write-Host "LoadBalancer URL obtained" -ForegroundColor Green
        break
    }
    Write-Host "Waiting for LoadBalancer URL (attempt $retry/$maxRetries)"
    Start-Sleep -Seconds 30
    $retry++
}

# Final Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "DEPLOYMENT SUCCESSFUL" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Cyan
Write-Host "AWS Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "EKS Cluster: $ClusterName" -ForegroundColor Cyan
Write-Host "ECR Registry: $EcrRegistry/$ImageName" -ForegroundColor Cyan
Write-Host ""

if ($LoadBalancerUrl) {
    Write-Host "========== APP URL (COPY THIS) ==========" -ForegroundColor Yellow
    Write-Host "http://$LoadBalancerUrl" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Yellow
} else {
    Write-Host "LoadBalancer URL not yet available" -ForegroundColor Yellow
    Write-Host "Check later with: kubectl get svc brain-tasks-app-service" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  kubectl get pods"
Write-Host "  kubectl logs -l app=brain-tasks-app -f"
Write-Host "  kubectl get svc brain-tasks-app-service"
Write-Host "  kubectl get nodes"
Write-Host ""
Write-Host "Deployment finished successfully!" -ForegroundColor Green
