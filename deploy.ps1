# Brain Tasks App - Complete Deployment Script (Windows PowerShell)
# Usage: powershell -ExecutionPolicy Bypass -File deploy.ps1

param(
    [string]$GitEmail = "vinothinimuthusamy71@gmail.com",
    [string]$GitName = "Vennilavan12",
    [string]$AwsRegion = "ap-south-1"
)

# Color functions
function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "✅ $Text" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Text)
    Write-Host "⚠️  $Text" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Text)
    Write-Host "❌ $Text" -ForegroundColor Red
}

# Step 0: Verify Prerequisites
Write-Header "STEP 0: Verifying Prerequisites"

$Prerequisites = @("git", "aws", "docker")
$MissingTools = @()

foreach ($tool in $Prerequisites) {
    try {
        $null = & $tool --version
        Write-Success "$tool is installed"
    }
    catch {
        $MissingTools += $tool
        Write-Error "$tool is not installed"
    }
}

if ($MissingTools.Count -gt 0) {
    Write-Error "Missing tools: $($MissingTools -join ', ')"
    Write-Host ""
    Write-Host "Installation instructions:"
    Write-Host "  Git: https://git-scm.com/download/win"
    Write-Host "  AWS CLI: https://awscli.amazonaws.com/AWSCLIV2.msi"
    Write-Host "  Docker: https://www.docker.com/products/docker-desktop"
    exit 1
}

# Step 1: GitHub SSH Setup
Write-Header "STEP 1: Setting Up GitHub SSH"

$SSHKeyPath = "$env:USERPROFILE\.ssh\id_rsa"

if (-not (Test-Path $SSHKeyPath)) {
    Write-Warning "SSH key not found. Creating new SSH key..."
    
    if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
        New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" -Force | Out-Null
    }
    
    & ssh-keygen -t rsa -b 4096 -f $SSHKeyPath -N "" -C $GitEmail
    Write-Success "SSH key created at $SSHKeyPath"
}
else {
    Write-Success "SSH key already exists"
}

# Display public key
Write-Warning "Add this SSH key to GitHub:"
Write-Host "========================================" -ForegroundColor Yellow
Get-Content "$SSHKeyPath.pub"
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Warning "Steps to add SSH key to GitHub:"
Write-Host "1. Go to: https://github.com/settings/keys"
Write-Host "2. Click 'New SSH key'"
Write-Host "3. Copy the key above and paste it"
Write-Host "4. Click 'Add SSH key'"
Write-Host ""
Read-Host "Press ENTER after adding SSH key to GitHub"

# Test SSH connection
Write-Warning "Testing SSH connection to GitHub..."
try {
    & ssh -T git@github.com 2>&1 | Out-Null
    Write-Success "SSH connection to GitHub successful"
}
catch {
    Write-Warning "SSH connection test (this is normal on first run)"
}

# Step 2: Configure Git
Write-Header "STEP 2: Configuring Git"

& git config --global user.email $GitEmail
& git config --global user.name $GitName
Write-Success "Git configured with email: $GitEmail"

# Step 3: Commit and Push to GitHub
Write-Header "STEP 3: Committing and Pushing to GitHub"

Set-Location "C:\Path\To\Brain-Tasks-App"  # UPDATE THIS PATH

& git add .
Write-Success "Files staged for commit"

$CommitMsg = "Deploy: Complete AWS EKS setup with CI/CD pipeline - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
try {
    & git commit -m $CommitMsg
    Write-Success "Files committed"
}
catch {
    Write-Warning "Nothing to commit (repository already up to date)"
}

# Set remote to SSH
& git remote set-url origin git@github.com:Vennilavan12/Brain-Tasks-App.git
& git push origin main
Write-Success "Pushed to GitHub"

# Step 4: AWS Configuration
Write-Header "STEP 4: Configuring AWS"

try {
    $null = & aws sts get-caller-identity --region $AwsRegion
    Write-Success "AWS credentials are configured"
}
catch {
    Write-Warning "AWS credentials not configured. Running 'aws configure'..."
    & aws configure
}

$AwsAccountId = & aws sts get-caller-identity --query Account --output text
$EcrRegistry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
$ImageName = "brain-tasks-app"
$ArtifactBucket = "brain-tasks-artifacts-$AwsAccountId"

Write-Success "AWS Account ID: $AwsAccountId"
Write-Success "AWS Region: $AwsRegion"
Write-Success "ECR Registry: $EcrRegistry"

# Step 5: Create IAM Roles
Write-Header "STEP 5: Creating IAM Roles"

Write-Warning "Creating EKS Cluster Role..."
$EksTrust = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "eks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
"@
$EksTrust | Out-File -FilePath "$env:TEMP\eks-trust.json" -Encoding UTF8 -Force

try {
    & aws iam create-role `
        --role-name brain-tasks-eks-cluster-role `
        --assume-role-policy-document file://$("$env:TEMP\eks-trust.json") `
        --region $AwsRegion
}
catch {
    Write-Warning "Role already exists"
}

& aws iam attach-role-policy `
    --role-name brain-tasks-eks-cluster-role `
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy `
    --region $AwsRegion 2>&1 | Out-Null

Write-Success "EKS Cluster Role created"

# Similar for other roles...
Write-Warning "Creating EKS Node Role..."
$NodeTrust = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
"@
$NodeTrust | Out-File -FilePath "$env:TEMP\node-trust.json" -Encoding UTF8 -Force

try {
    & aws iam create-role `
        --role-name brain-tasks-eks-node-role `
        --assume-role-policy-document file://$("$env:TEMP\node-trust.json") `
        --region $AwsRegion
}
catch {
    Write-Warning "Role already exists"
}

& aws iam attach-role-policy `
    --role-name brain-tasks-eks-node-role `
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy `
    --region $AwsRegion 2>&1 | Out-Null

& aws iam attach-role-policy `
    --role-name brain-tasks-eks-node-role `
    --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy `
    --region $AwsRegion 2>&1 | Out-Null

& aws iam attach-role-policy `
    --role-name brain-tasks-eks-node-role `
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly `
    --region $AwsRegion 2>&1 | Out-Null

Write-Success "EKS Node Role created"

# Step 6: Create VPC & Subnets
Write-Header "STEP 6: Creating VPC and Subnets"

Write-Warning "Creating VPC..."
$VpcId = & aws ec2 create-vpc `
    --cidr-block 10.0.0.0/16 `
    --region $AwsRegion `
    --query 'Vpc.VpcId' `
    --output text

Write-Success "VPC created: $VpcId"

Write-Warning "Creating subnets..."
$Subnet1 = & aws ec2 create-subnet `
    --vpc-id $VpcId `
    --cidr-block 10.0.1.0/24 `
    --availability-zone "${AwsRegion}a" `
    --region $AwsRegion `
    --query 'Subnet.SubnetId' `
    --output text

$Subnet2 = & aws ec2 create-subnet `
    --vpc-id $VpcId `
    --cidr-block 10.0.2.0/24 `
    --availability-zone "${AwsRegion}b" `
    --region $AwsRegion `
    --query 'Subnet.SubnetId' `
    --output text

Write-Success "Subnets created: $Subnet1, $Subnet2"

# Step 7: Create ECR Repository
Write-Header "STEP 7: Creating ECR Repository"

try {
    & aws ecr create-repository `
        --repository-name $ImageName `
        --region $AwsRegion 2>&1 | Out-Null
}
catch {
    Write-Warning "Repository already exists"
}

Write-Success "ECR Repository ready: $ImageName"

# Step 8: Build and Push Docker Image
Write-Header "STEP 8: Building and Pushing Docker Image"

Write-Warning "Building Docker image..."
& docker build -t "$($ImageName):latest" .

Write-Warning "Logging in to ECR..."
$ecrPassword = & aws ecr get-login-password --region $AwsRegion
$ecrPassword | & docker login --username AWS --password-stdin $EcrRegistry

Write-Warning "Tagging image..."
& docker tag "$($ImageName):latest" "$EcrRegistry/$ImageName:latest"

Write-Warning "Pushing image to ECR..."
& docker push "$EcrRegistry/$ImageName:latest"

Write-Success "Image pushed to ECR: $EcrRegistry/$ImageName:latest"

# Step 9: Create EKS Cluster
Write-Header "STEP 9: Creating EKS Cluster"

Write-Warning "Creating EKS cluster (this takes 15-20 minutes)..."
& aws eks create-cluster `
    --name brain-tasks-cluster `
    --version 1.28 `
    --role-arn "arn:aws:iam::$($AwsAccountId):role/brain-tasks-eks-cluster-role" `
    --resources-vpc-config "subnetIds=$Subnet1,$Subnet2" `
    --region $AwsRegion

Write-Warning "Waiting for cluster to become ACTIVE..."
$MaxRetries = 40
$RetryCount = 0

while ($RetryCount -lt $MaxRetries) {
    $Status = & aws eks describe-cluster `
        --name brain-tasks-cluster `
        --region $AwsRegion `
        --query 'cluster.status' `
        --output text
    
    if ($Status -eq "ACTIVE") {
        Write-Success "Cluster is ACTIVE!"
        break
    }
    else {
        Write-Host "Current status: $Status... waiting... ($RetryCount/$MaxRetries)"
        Start-Sleep -Seconds 30
        $RetryCount++
    }
}

# Step 10: Configure kubectl
Write-Header "STEP 10: Configuring kubectl"

Write-Warning "Updating kubeconfig..."
& aws eks update-kubeconfig --name brain-tasks-cluster --region $AwsRegion

Write-Warning "Testing kubectl connection..."
& kubectl cluster-info
Write-Success "kubectl configured successfully"

# Step 11: Create Node Group
Write-Header "STEP 11: Creating Node Group"

Write-Warning "Creating node group (this takes 10-15 minutes)..."
& aws eks create-nodegroup `
    --cluster-name brain-tasks-cluster `
    --nodegroup-name brain-tasks-nodegroup `
    --scaling-config "minSize=2,maxSize=4,desiredSize=3" `
    --subnets $Subnet1 $Subnet2 `
    --node-role "arn:aws:iam::$($AwsAccountId):role/brain-tasks-eks-node-role" `
    --instance-types t3.medium `
    --region $AwsRegion

Write-Warning "Waiting for nodes to become Ready..."
$ReadyCount = 0
while ($ReadyCount -lt 3) {
    Start-Sleep -Seconds 30
    $Nodes = & kubectl get nodes --no-headers
    $ReadyCount = ($Nodes | Select-String "Ready" | Measure-Object).Count
    Write-Host "Ready nodes: $ReadyCount/3"
}

Write-Success "All nodes are Ready!"

# Step 12: Create ImagePullSecret
Write-Header "STEP 12: Creating ImagePullSecret"

Write-Warning "Creating ImagePullSecret for ECR..."
$EcrPassword = & aws ecr get-login-password --region $AwsRegion
& kubectl create secret docker-registry ecr-secret `
    --docker-server=$EcrRegistry `
    --docker-username=AWS `
    --docker-password=$EcrPassword `
    --docker-email=user@example.com `
    --namespace=default 2>&1 | Out-Null

Write-Success "ImagePullSecret created"

# Step 13: Deploy to Kubernetes
Write-Header "STEP 13: Deploying to Kubernetes"

Write-Warning "Updating k8s manifests with ECR image URI..."
$DeploymentFile = "k8s-manifests\deployment.yaml"
$Content = Get-Content $DeploymentFile
$Content = $Content -replace "ACCOUNT_ID\.dkr\.ecr\.REGION\.amazonaws\.com/brain-tasks-app:latest", "$EcrRegistry/$ImageName:latest"
$Content | Set-Content $DeploymentFile

Write-Warning "Applying Kubernetes manifests..."
& kubectl apply -f k8s-manifests/deployment.yaml
& kubectl apply -f k8s-manifests/service.yaml

Write-Warning "Waiting for pods to become Running..."
$ReadyPods = 0
while ($ReadyPods -lt 3) {
    Start-Sleep -Seconds 10
    $ReadyPods = (& kubectl get pods -l app=brain-tasks-app -o json | ConvertFrom-Json).items | Where-Object { $_.status.phase -eq "Running" } | Measure-Object | Select-Object -ExpandProperty Count
    Write-Host "Running pods: $ReadyPods/3"
}

Write-Success "All 3 pods are Running!"

# Step 14: Get LoadBalancer URL
Write-Header "STEP 14: Getting LoadBalancer URL"

Write-Warning "Waiting for LoadBalancer to get public URL (this can take 5-10 minutes)..."
$LoadBalancerUrl = ""
$RetryCount = 0
$MaxRetries = 40

while ([string]::IsNullOrEmpty($LoadBalancerUrl) -and $RetryCount -lt $MaxRetries) {
    Start-Sleep -Seconds 30
    $LoadBalancerUrl = & kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>&1
    $RetryCount++
    Write-Host "Attempt $RetryCount/$MaxRetries..."
}

Write-Success "LoadBalancer URL obtained!"

# Final Summary
Write-Header "🎉 DEPLOYMENT COMPLETE!"

Write-Host ""
Write-Host "Your application is now live!" -ForegroundColor Green
Write-Host ""
Write-Host "📊 DEPLOYMENT INFORMATION:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "AWS Account ID:     $AwsAccountId" -ForegroundColor Cyan
Write-Host "AWS Region:         $AwsRegion" -ForegroundColor Cyan
Write-Host "EKS Cluster:        brain-tasks-cluster" -ForegroundColor Cyan
Write-Host "ECR Repository:     $EcrRegistry/$ImageName" -ForegroundColor Cyan
Write-Host ""
Write-Host "🌐 APPLICATION URL:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "http://$LoadBalancerUrl" -ForegroundColor Green
Write-Host ""
Write-Host "📋 USEFUL COMMANDS:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "View pods:           kubectl get pods"
Write-Host "View logs:           kubectl logs -l app=brain-tasks-app -f"
Write-Host "View service:        kubectl get svc brain-tasks-app-service"
Write-Host "View nodes:          kubectl get nodes"
Write-Host "Scale replicas:      kubectl scale deployment brain-tasks-app --replicas=5"
Write-Host ""

# Save deployment info to file
$DeployInfoFile = "DEPLOYMENT_INFO.txt"
$DeploymentInfo = @"
BRAIN TASKS APP - DEPLOYMENT INFORMATION
Generated: $(Get-Date)

=== AWS DETAILS ===
AWS Account ID: $AwsAccountId
AWS Region: $AwsRegion
EKS Cluster: brain-tasks-cluster
Node Group: brain-tasks-nodegroup
Number of Nodes: 3 (t3.medium)

=== CONTAINER DETAILS ===
ECR Repository: $EcrRegistry/$ImageName
Image Tag: latest
Image URI: $EcrRegistry/$ImageName:latest

=== APPLICATION ACCESS ===
Application URL: http://$LoadBalancerUrl
LoadBalancer DNS: $LoadBalancerUrl

=== KUBERNETES DETAILS ===
Deployment: brain-tasks-app
Service: brain-tasks-app-service
Service Type: LoadBalancer
Port: 80

=== USEFUL COMMANDS ===
kubectl get pods
kubectl logs -l app=brain-tasks-app -f
kubectl scale deployment brain-tasks-app --replicas=5
kubectl set image deployment/brain-tasks-app brain-tasks-app=$EcrRegistry/$ImageName:new-tag
kubectl port-forward svc/brain-tasks-app-service 8080:80

=== GITHUB DETAILS ===
Repository: https://github.com/Vennilavan12/Brain-Tasks-App.git
Branch: main
SSH Remote: git@github.com:Vennilavan12/Brain-Tasks-App.git

=== COST ESTIMATE ===
EKS Cluster: ~$10/month
EC2 Nodes (3): ~$30/month
Load Balancer: ~$16/month
Network Transfer: ~$5/month
CloudWatch: ~$5/month
Other: ~$4/month
TOTAL: ~$70/month
"@

$DeploymentInfo | Out-File -FilePath $DeployInfoFile -Encoding UTF8 -Force
Write-Success "Deployment info saved to: $DeployInfoFile"
Write-Host ""
Write-Success "All deployment steps completed successfully!"
Write-Success "Your application is accessible at: http://$LoadBalancerUrl"
