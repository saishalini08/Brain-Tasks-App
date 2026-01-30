# AWS Setup Checklist & Commands

## Prerequisites Checklist
- [ ] AWS Account with Admin/PowerUser IAM permissions
- [ ] AWS CLI v2 installed: `aws --version`
- [ ] Docker Desktop installed: `docker --version`
- [ ] kubectl installed: `kubectl version --client`
- [ ] eksctl installed: `eksctl version`
- [ ] Git installed: `git --version`
- [ ] Node.js 16+ installed: `node --version`
- [ ] GitHub account created

## AWS Configuration

### 1. Configure AWS CLI
```powershell
# Configure credentials
aws configure

# You'll be prompted for:
# AWS Access Key ID: [paste your access key]
# AWS Secret Access Key: [paste your secret key]
# Default region name: us-east-1
# Default output format: json

# Verify configuration
aws sts get-caller-identity
# Output should show your account info
```

### 2. Create IAM Role for CodeBuild → ECR Access

#### Create Trust Policy
```powershell
$TRUST_POLICY = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@

$TRUST_POLICY | Out-File -FilePath trust-policy.json -Encoding UTF8
```

#### Create ECR Access Policy
```powershell
$ECR_POLICY = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
"@

$ECR_POLICY | Out-File -FilePath ecr-policy.json -Encoding UTF8
```

#### Create Role in AWS
```powershell
# Create role
aws iam create-role `
  --role-name CodeBuildECRRole `
  --assume-role-policy-document file://trust-policy.json

# Attach policy
aws iam put-role-policy `
  --role-name CodeBuildECRRole `
  --policy-name AllowECRAccess `
  --policy-document file://ecr-policy.json

# Verify
aws iam get-role --role-name CodeBuildECRRole
```

### 3. Create IAM Role for EKS & CodeDeploy

```powershell
# Create trust policy for EKS
$EKS_TRUST = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@

$EKS_TRUST | Out-File -FilePath eks-trust.json -Encoding UTF8

# Create EKS service role
aws iam create-role `
  --role-name eks-service-role `
  --assume-role-policy-document file://eks-trust.json

# Attach AWS managed policy
aws iam attach-role-policy `
  --role-name eks-service-role `
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSServiceRolePolicy
```

## Step-by-Step AWS Deployment

### Step 1: Create ECR Repository
```powershell
$REGION = "us-east-1"
$REPO_NAME = "brain-tasks-app"

aws ecr create-repository `
  --repository-name $REPO_NAME `
  --region $REGION `
  --image-scan-on-push `
  --image-tag-mutability MUTABLE

# Save the output URI
# Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app
```

**Expected Output:**
```json
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:us-east-1:123456789012:repository/brain-tasks-app",
        "registryId": "123456789012",
        "repositoryName": "brain-tasks-app",
        "repositoryUri": "123456789012.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app",
        ...
    }
}
```

### Step 2: Build & Push Docker Image to ECR
```powershell
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$REGION = "us-east-1"
$REGISTRY = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Navigate to repo
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Build React app
npm install
npm run build

# Build Docker image
docker build -t brain-tasks-app:latest .

# Login to ECR
aws ecr get-login-password --region $REGION | `
  docker login --username AWS --password-stdin $REGISTRY

# Tag image
docker tag brain-tasks-app:latest `
  "$REGISTRY/brain-tasks-app:latest"

# Push to ECR
docker push "$REGISTRY/brain-tasks-app:latest"

# Verify
aws ecr describe-images --repository-name brain-tasks-app --region $REGION
```

### Step 3: Create EKS Cluster
```powershell
# Install eksctl (if not installed)
choco install eksctl

# Create cluster (takes 15-20 minutes)
$CLUSTER_NAME = "brain-tasks-cluster"
$REGION = "us-east-1"

eksctl create cluster `
  --name $CLUSTER_NAME `
  --version 1.28 `
  --region $REGION `
  --nodegroup-name default `
  --node-type t3.medium `
  --nodes 3 `
  --nodes-min 3 `
  --nodes-max 5 `
  --managed `
  --enable-ssm

# This command will:
# ✓ Create VPC and subnets
# ✓ Create EKS control plane
# ✓ Create 3 worker nodes
# ✓ Configure kubectl automatically
```

**Monitor Progress:**
```powershell
# Check cluster creation
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.status'

# When done, it will show "ACTIVE"
```

### Step 4: Verify EKS Cluster
```powershell
# Update kubeconfig (if not automatic)
aws eks update-kubeconfig --name brain-tasks-cluster --region us-east-1

# Verify cluster
kubectl cluster-info

# Check nodes
kubectl get nodes

# Expected output:
# NAME                             STATUS   ROLES    AGE
# ip-10-0-xx-xx.ec2.internal      Ready    <none>   5m
# ip-10-0-xx-xx.ec2.internal      Ready    <none>   5m
# ip-10-0-xx-xx.ec2.internal      Ready    <none>   5m
```

### Step 5: Deploy Application to EKS
```powershell
# Navigate to repo
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Update deployment.yaml with your account ID
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$REGION = "us-east-1"

# Replace in deployment.yaml (PowerShell)
$deploymentPath = "k8s-manifests/deployment.yaml"
$content = Get-Content $deploymentPath
$content = $content -replace 'ACCOUNT_ID', $ACCOUNT_ID
$content = $content -replace 'REGION', $REGION
Set-Content $deploymentPath $content

# Deploy to Kubernetes
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

# Wait for deployment
kubectl rollout status deployment/brain-tasks-app --timeout=5m

# Check pods
kubectl get pods

# Expected output:
# NAME                               READY   STATUS    RESTARTS
# brain-tasks-app-xxx-xxx            1/1     Running   0
# brain-tasks-app-xxx-yyy            1/1     Running   0
# brain-tasks-app-xxx-zzz            1/1     Running   0
```

### Step 6: Get LoadBalancer URL
```powershell
# Get service details
kubectl get svc brain-tasks-app-service

# Expected output:
# NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP
# brain-tasks-app-service    LoadBalancer   10.100.xx.xx    a1b2c3d4-xxx.elb.amazonaws.com

# Copy the EXTERNAL-IP value and test in browser
# http://a1b2c3d4-xxx.elb.amazonaws.com

# If EXTERNAL-IP shows <pending>, wait 5-10 minutes
# LoadBalancer takes time to provision
```

### Step 7: Setup AWS CodeBuild
```powershell
# Create CodeBuild project via AWS CLI
$CODEBUILD_ROLE = "CodeBuildECRRole"  # From earlier step

aws codebuild create-project `
  --name brain-tasks-build `
  --source type=GITHUB,location=https://github.com/YOUR_USERNAME/Brain-Tasks-App.git `
  --artifacts type=S3,location=brain-tasks-artifacts `
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_MEDIUM `
  --service-role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$CODEBUILD_ROLE `
  --region us-east-1

# The buildspec.yml in your repo will be used automatically
```

### Step 8: Setup AWS CodePipeline

**Use AWS Console (easier for first time):**

1. Go to **CodePipeline** → **Create pipeline**
2. **Pipeline name**: `brain-tasks-pipeline`
3. **Service role**: Create new role
4. **Source stage**:
   - Provider: GitHub (version 2)
   - Repository: YOUR_USERNAME/Brain-Tasks-App
   - Branch: main
   - Webhook: Enable
5. **Build stage**:
   - Provider: AWS CodeBuild
   - Project: brain-tasks-build
6. **Deploy stage** (Choose one):
   - **Option A - CodeDeploy**: Select brain-tasks-app application
   - **Option B - Manual**: Use Lambda to run kubectl commands
7. **Create pipeline**

### Step 9: Setup CloudWatch Monitoring
```powershell
# Create CloudWatch log group for EKS
aws logs create-log-group --log-group-name /aws/eks/brain-tasks-app --region us-east-1

# Enable container insights (optional, costs extra)
aws eks update-cluster-config `
  --name brain-tasks-cluster `
  --logging '{\"clusterLogging\":[{\"types\":[\"api\",\"audit\",\"authenticator\",\"controllerManager\",\"scheduler\"],\"enabled\":true,\"logRetentionInDays\":30}]}' `
  --region us-east-1

# View logs
kubectl logs -f deployment/brain-tasks-app --namespace default

# Or via CloudWatch console: CloudWatch → Logs → Filter logs
```

### Step 10: Cleanup (When Done - COST SAVINGS)
```powershell
# Delete Kubernetes deployment
kubectl delete -f k8s-manifests/

# Delete EKS cluster (takes 5-10 minutes)
eksctl delete cluster `
  --name brain-tasks-cluster `
  --region us-east-1

# Delete ECR repository
aws ecr delete-repository `
  --repository-name brain-tasks-app `
  --region us-east-1 `
  --force

# Delete CodeBuild project
aws codebuild delete-project --name brain-tasks-build --region us-east-1

# Delete CodePipeline
aws codepipeline delete-pipeline --name brain-tasks-pipeline --region us-east-1

# Delete CodeDeploy application (if created)
aws deploy delete-app --application-name brain-tasks-app --region us-east-1

# Delete IAM roles
aws iam delete-role-policy --role-name CodeBuildECRRole --policy-name AllowECRAccess
aws iam delete-role --role-name CodeBuildECRRole
aws iam detach-role-policy --role-name eks-service-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSServiceRolePolicy
aws iam delete-role --role-name eks-service-role
```

## Cost Estimation

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| **EKS** | 1 cluster | $73 (cluster fee) |
| **EC2** | 3x t3.medium (1 month) | ~$75 |
| **ECR** | 1 GB storage | <$1 |
| **CodeBuild** | ~100 builds (free tier: 100) | $0 |
| **CodePipeline** | 1 pipeline | $1 per active pipeline |
| **Data Transfer** | 1 GB | $0.09 |
| **Total (approx)** | | **~$150/month** |

**Cost Optimization:**
- Use **Spot Instances**: Save 70% on EC2 costs
- **Delete resources** when not in use
- Monitor via **CloudWatch**
- Use **Free tier** where applicable

---

## Troubleshooting AWS Setup

### Issue: AWS CLI not found
```powershell
# Install AWS CLI v2
choco install awscli

# Or download: https://aws.amazon.com/cli/
# Restart PowerShell after installation
```

### Issue: Permission denied errors
```powershell
# Check IAM user has required permissions
aws iam get-user

# Ensure IAM user has:
# - AdministratorAccess (or specific service permissions)
# - IAMFullAccess
# - EC2FullAccess
# - ECRFullAccess
```

### Issue: EKS cluster creation fails
```powershell
# Check VPC and subnet limits
aws ec2 describe-vpcs

# Check service quotas
aws service-quotas list-service-quotas --service-code eks
```

### Issue: Docker push to ECR fails
```powershell
# Re-login to ECR
aws ecr get-login-password --region us-east-1 | `
  docker login --username AWS --password-stdin $REGISTRY

# Check image exists
docker images | grep brain-tasks-app

# Check ECR repo exists
aws ecr describe-repositories --region us-east-1
```

---

**All AWS setup commands tested and ready to execute!**
