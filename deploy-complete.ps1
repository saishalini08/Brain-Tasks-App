param(
    [string]$AwsRegion = "ap-south-1"
)

Write-Host "Starting Brain Tasks App Deployment..." -ForegroundColor Cyan

# Verify AWS
try {
    $AwsAccountId = aws sts get-caller-identity --query Account --output text
    Write-Host "AWS Account: $AwsAccountId" -ForegroundColor Green
} catch {
    Write-Host "AWS credentials error" -ForegroundColor Red
    exit 1
}

$ImageName = "brain-tasks-app"
$ClusterName = "brain-tasks-cluster"
$EcrRegistry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"

Write-Host "Starting deployment process..." -ForegroundColor Yellow
Write-Host "Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "ECR Registry: $EcrRegistry" -ForegroundColor Cyan
Write-Host ""

# STEP 1: Build Docker Image
Write-Host "STEP 1: Building Docker image..." -ForegroundColor Yellow
docker build -t ${ImageName}:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker build failed" -ForegroundColor Red
    exit 1
}
Write-Host "Docker image built successfully" -ForegroundColor Green

# STEP 2: Create ECR Repository
Write-Host ""
Write-Host "STEP 2: Creating ECR repository..." -ForegroundColor Yellow
aws ecr create-repository --repository-name $ImageName --region $AwsRegion 2> $null
Write-Host "ECR repository ready" -ForegroundColor Green

# STEP 3: Push to ECR
Write-Host ""
Write-Host "STEP 3: Pushing image to ECR..." -ForegroundColor Yellow
$loginCmd = aws ecr get-login-password --region $AwsRegion
$loginCmd | docker login --username AWS --password-stdin $EcrRegistry
docker tag ${ImageName}:latest ${EcrRegistry}/${ImageName}:latest
docker push ${EcrRegistry}/${ImageName}:latest
Write-Host "Image pushed successfully" -ForegroundColor Green

# STEP 4: Create IAM Roles
Write-Host ""
Write-Host "STEP 4: Creating IAM roles..." -ForegroundColor Yellow

$trustPolicy = '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "eks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'
$trustPolicy | Out-File -FilePath "$env:TEMP\eks-trust.json" -Encoding UTF8 -Force

aws iam create-role --role-name brain-tasks-eks-cluster-role --assume-role-policy-document "file://$env:TEMP\eks-trust.json" 2> $null
aws iam attach-role-policy --role-name brain-tasks-eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2> $null

$nodeTrust = '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'
$nodeTrust | Out-File -FilePath "$env:TEMP\node-trust.json" -Encoding UTF8 -Force

aws iam create-role --role-name brain-tasks-eks-node-role --assume-role-policy-document "file://$env:TEMP\node-trust.json" 2> $null
aws iam attach-role-policy --role-name brain-tasks-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2> $null
aws iam attach-role-policy --role-name brain-tasks-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2> $null
aws iam attach-role-policy --role-name brain-tasks-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2> $null

Write-Host "IAM roles created" -ForegroundColor Green

# STEP 5: Create VPC and Subnets
Write-Host ""
Write-Host "STEP 5: Creating VPC and Subnets..." -ForegroundColor Yellow

$vpcId = aws ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16" --region $AwsRegion --query "Vpcs[0].VpcId" --output text 2>&1
if ($vpcId -eq "None" -or [string]::IsNullOrEmpty($vpcId)) {
    $vpcId = aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $AwsRegion --query "Vpc.VpcId" --output text
    Write-Host "VPC created: $vpcId" -ForegroundColor Green
} else {
    Write-Host "VPC exists: $vpcId" -ForegroundColor Green
}

$subnet1 = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.1.0/24 --availability-zone "${AwsRegion}a" --region $AwsRegion --query "Subnet.SubnetId" --output text 2>&1
if ($subnet1 -like "*InvalidParameterValue*") {
    $subnet1 = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" "Name=cidr-block,Values=10.0.1.0/24" --region $AwsRegion --query "Subnets[0].SubnetId" --output text
}

$subnet2 = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.2.0/24 --availability-zone "${AwsRegion}b" --region $AwsRegion --query "Subnet.SubnetId" --output text 2>&1
if ($subnet2 -like "*InvalidParameterValue*") {
    $subnet2 = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" "Name=cidr-block,Values=10.0.2.0/24" --region $AwsRegion --query "Subnets[0].SubnetId" --output text
}

Write-Host "Subnets created: $subnet1, $subnet2" -ForegroundColor Green

# STEP 6: Create EKS Cluster
Write-Host ""
Write-Host "STEP 6: Creating EKS Cluster (this takes 15-20 minutes)..." -ForegroundColor Yellow

$clusterStatus = aws eks describe-cluster --name $ClusterName --region $AwsRegion --query "cluster.status" --output text 2>&1
if ($clusterStatus -ne "ACTIVE" -and $clusterStatus -ne "CREATING") {
    aws eks create-cluster --name $ClusterName --version 1.28 --role-arn "arn:aws:iam::${AwsAccountId}:role/brain-tasks-eks-cluster-role" --resources-vpc-config "subnetIds=$subnet1,$subnet2" --region $AwsRegion
}

Write-Host "Waiting for cluster to be ACTIVE..." -ForegroundColor Yellow
$count = 0
while ($count -lt 40) {
    $status = aws eks describe-cluster --name $ClusterName --region $AwsRegion --query "cluster.status" --output text 2>&1
    if ($status -eq "ACTIVE") {
        Write-Host "Cluster is ACTIVE" -ForegroundColor Green
        break
    }
    Write-Host "Status: $status (attempt $count/40)"
    Start-Sleep -Seconds 30
    $count++
}

# STEP 7: Update kubeconfig
Write-Host ""
Write-Host "STEP 7: Updating kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig --name $ClusterName --region $AwsRegion
kubectl cluster-info
Write-Host "kubeconfig updated" -ForegroundColor Green

# STEP 8: Create Node Group
Write-Host ""
Write-Host "STEP 8: Creating Node Group (this takes 10-15 minutes)..." -ForegroundColor Yellow

aws eks create-nodegroup --cluster-name $ClusterName --nodegroup-name brain-tasks-nodegroup --scaling-config minSize=2,maxSize=4,desiredSize=3 --subnets $subnet1 $subnet2 --node-role "arn:aws:iam::${AwsAccountId}:role/brain-tasks-eks-node-role" --instance-types t3.medium --region $AwsRegion 2> $null

Write-Host "Waiting for nodes to be Ready..." -ForegroundColor Yellow
$count = 0
while ($count -lt 40) {
    $nodes = kubectl get nodes --no-headers 2>&1 | Select-String "Ready" | Measure-Object
    if ($nodes.Count -ge 3) {
        Write-Host "All 3 nodes are Ready" -ForegroundColor Green
        break
    }
    Write-Host "Ready nodes: $($nodes.Count)/3 (attempt $count/40)"
    Start-Sleep -Seconds 30
    $count++
}

# STEP 9: Create ImagePullSecret
Write-Host ""
Write-Host "STEP 9: Creating ImagePullSecret..." -ForegroundColor Yellow
$ecrPassword = aws ecr get-login-password --region $AwsRegion
kubectl create secret docker-registry ecr-secret --docker-server=$EcrRegistry --docker-username=AWS --docker-password=$ecrPassword --docker-email=user@example.com --namespace=default 2> $null
Write-Host "ImagePullSecret created" -ForegroundColor Green

# STEP 10: Deploy to Kubernetes
Write-Host ""
Write-Host "STEP 10: Deploying to Kubernetes..." -ForegroundColor Yellow

$deploymentFile = "k8s-manifests/deployment.yaml"
if (Test-Path $deploymentFile) {
    $content = Get-Content $deploymentFile -Raw
    $content = $content -replace "ACCOUNT_ID\.dkr\.ecr\.REGION\.amazonaws\.com/brain-tasks-app:latest", "${EcrRegistry}/${ImageName}:latest"
    $content | Set-Content $deploymentFile -Encoding UTF8
}

kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml
Write-Host "Manifests applied" -ForegroundColor Green

Write-Host ""
Write-Host "Waiting for pods to be Running..." -ForegroundColor Yellow
$count = 0
while ($count -lt 40) {
    $pods = kubectl get pods -l app=brain-tasks-app --field-selector=status.phase=Running --no-headers 2>&1 | Measure-Object
    if ($pods.Count -ge 3) {
        Write-Host "All 3 pods are Running" -ForegroundColor Green
        break
    }
    Write-Host "Running pods: $($pods.Count)/3 (attempt $count/40)"
    Start-Sleep -Seconds 10
    $count++
}

# STEP 11: Get LoadBalancer URL
Write-Host ""
Write-Host "STEP 11: Getting LoadBalancer URL (5-10 minutes)..." -ForegroundColor Yellow
$count = 0
$LoadBalancerUrl = ""
while ($count -lt 40) {
    $LoadBalancerUrl = kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>&1
    if ($LoadBalancerUrl -and $LoadBalancerUrl -notlike "*items*") {
        Write-Host "LoadBalancer URL obtained" -ForegroundColor Green
        break
    }
    Write-Host "Waiting for LoadBalancer URL (attempt $count/40)"
    Start-Sleep -Seconds 30
    $count++
}

# Summary
Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Cyan
Write-Host "AWS Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "EKS Cluster: $ClusterName" -ForegroundColor Cyan
Write-Host "ECR Registry: $EcrRegistry/$ImageName" -ForegroundColor Cyan
Write-Host ""
if ($LoadBalancerUrl) {
    Write-Host "Application URL: http://$LoadBalancerUrl" -ForegroundColor Green
} else {
    Write-Host "LoadBalancer URL pending" -ForegroundColor Yellow
    Write-Host "Check with: kubectl get svc brain-tasks-app-service" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  kubectl get pods"
Write-Host "  kubectl logs -l app=brain-tasks-app -f"
Write-Host "  kubectl get svc brain-tasks-app-service"
Write-Host "  kubectl get nodes"
Write-Host ""
Write-Host "Deployment finished successfully!" -ForegroundColor Green
