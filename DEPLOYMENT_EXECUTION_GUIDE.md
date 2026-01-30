# QUICK START: AWS Deployment Execution Checklist

This checklist provides a quick reference for deploying the Brain Tasks React application to AWS production.

## ✅ Pre-Deployment Checklist

- [ ] AWS Account created with appropriate IAM permissions
- [ ] AWS CLI v2 installed and configured (`aws --version`)
- [ ] Docker installed (`docker --version`)
- [ ] kubectl installed (`kubectl version --client`)
- [ ] Git installed (`git --version`)
- [ ] Node.js 16+ installed (`node --version`)
- [ ] Clone repository: `git clone https://github.com/Vennilavan12/Brain-Tasks-App.git`
- [ ] Navigate to project: `cd /workspaces/Brain-Tasks-App`

---

## 📋 Deployment Steps Overview

**Time Estimate**: 60-90 minutes (first time)

### Phase 1: Local Testing (5 minutes)
- Build and test React app locally
- Build and run Docker image locally
- Verify application runs on port 3000

### Phase 2: AWS Account Setup (15 minutes)
- Create IAM roles for EKS, CodeBuild, CodeDeploy, CodePipeline
- Create VPC, subnets, Internet Gateway (or use existing)
- Set environment variables

### Phase 3: Container Registry (10 minutes)
- Create AWS ECR repository
- Build Docker image
- Push image to ECR

### Phase 4: Kubernetes Cluster Setup (30-40 minutes)
- Create EKS cluster (15-20 minutes)
- Configure kubectl
- Create and wait for node group (10-15 minutes)
- Create ImagePullSecret

### Phase 5: Deploy to Kubernetes (5 minutes)
- Apply k8s manifests (deployment.yaml, service.yaml)
- Wait for pods to become Ready
- Get LoadBalancer URL

### Phase 6: CI/CD Pipeline Setup (20 minutes)
- Create CodeBuild project
- Create CodeDeploy application
- Create CodePipeline
- Authorize GitHub connection

### Phase 7: Monitoring (10 minutes)
- Create CloudWatch log groups
- Set up basic alarms
- Verify logs are flowing

---

## 🚀 Step-by-Step Execution Guide

### STEP 1: Local Testing & Verification

```bash
# Navigate to project
cd /workspaces/Brain-Tasks-App

# Install dependencies
npm install

# Build the application
npm run build

# Verify build succeeded
ls -la dist/
echo "Build successful if dist/ folder exists with files"

# Build Docker image
docker build -t brain-tasks-app:latest .

# Test Docker image
docker run -d -p 3000:80 --name test-app brain-tasks-app:latest

# Wait 5 seconds for container to start
sleep 5

# Test application
curl http://localhost:3000

# If curl shows HTML content, Docker image works!

# Stop test container
docker stop test-app
docker rm test-app

echo "✅ Local testing complete!"
```

---

### STEP 2: Set AWS Environment Variables

```bash
# Export these variables - you'll use them throughout

# Get your AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Set your preferred AWS region
export AWS_REGION=us-east-1  # Change to your region if needed

# Build other variable values
export ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
export IMAGE_NAME=brain-tasks-app
export IMAGE_TAG=latest

# Create artifact bucket name
export ARTIFACT_BUCKET="brain-tasks-artifacts-$AWS_ACCOUNT_ID"

# Verify variables are set
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "ECR Registry: $ECR_REGISTRY"
echo "Artifact Bucket: $ARTIFACT_BUCKET"

# ⚠️ IMPORTANT: Save these values!
# You'll need them for all subsequent commands
```

---

### STEP 3: Create IAM Roles

**This is critical - CodeBuild, CodeDeploy, and CodePipeline need IAM roles to function**

```bash
# 3.1: Create role for EKS Cluster
echo "Creating EKS Cluster Role..."
cat > /tmp/eks-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "eks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name brain-tasks-eks-cluster-role \
  --assume-role-policy-document file:///tmp/eks-trust.json

aws iam attach-role-policy \
  --role-name brain-tasks-eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

echo "✅ EKS Cluster Role created"

# 3.2: Create role for EKS Node Group
echo "Creating EKS Node Role..."
cat > /tmp/node-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name brain-tasks-eks-node-role \
  --assume-role-policy-document file:///tmp/node-trust.json

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

echo "✅ EKS Node Role created"

# 3.3: Create role for CodeBuild
echo "Creating CodeBuild Role..."
cat > /tmp/codebuild-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "codebuild.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name brain-tasks-codebuild-role \
  --assume-role-policy-document file:///tmp/codebuild-trust.json

cat > /tmp/codebuild-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["ecr:*", "logs:*", "s3:*"],
    "Resource": "*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name brain-tasks-codebuild-role \
  --policy-name codebuild-policy \
  --policy-document file:///tmp/codebuild-policy.json

echo "✅ CodeBuild Role created"

# 3.4: Create role for CodeDeploy
echo "Creating CodeDeploy Role..."
cat > /tmp/codedeploy-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "codedeploy.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name brain-tasks-codedeploy-role \
  --assume-role-policy-document file:///tmp/codedeploy-trust.json

aws iam attach-role-policy \
  --role-name brain-tasks-codedeploy-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS

echo "✅ CodeDeploy Role created"

# 3.5: Create role for CodePipeline
echo "Creating CodePipeline Role..."
cat > /tmp/codepipeline-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "codepipeline.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name brain-tasks-codepipeline-role \
  --assume-role-policy-document file:///tmp/codepipeline-trust.json

cat > /tmp/codepipeline-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*", "codebuild:*", "codedeploy:*", "iam:PassRole"],
    "Resource": "*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name brain-tasks-codepipeline-role \
  --policy-name codepipeline-policy \
  --policy-document file:///tmp/codepipeline-policy.json

echo "✅ CodePipeline Role created"
echo "✅ All IAM roles created successfully!"
```

---

### STEP 4: Create VPC & Networking (Skip if using existing VPC)

```bash
# Create VPC
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
export VPC_ID
echo "VPC ID: $VPC_ID"

# Create Subnets
echo "Creating subnets..."
SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${AWS_REGION}a \
  --query 'Subnet.SubnetId' \
  --output text)
export SUBNET_1

SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${AWS_REGION}b \
  --query 'Subnet.SubnetId' \
  --output text)
export SUBNET_2

echo "Subnet 1: $SUBNET_1"
echo "Subnet 2: $SUBNET_2"

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_2 --map-public-ip-on-launch

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create Route Table
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# Associate subnets
aws ec2 associate-route-table --subnet-id $SUBNET_1 --route-table-id $ROUTE_TABLE_ID
aws ec2 associate-route-table --subnet-id $SUBNET_2 --route-table-id $ROUTE_TABLE_ID

echo "✅ VPC and networking created!"
```

---

### STEP 5: Create ECR Repository & Push Image

```bash
# Create ECR repository
echo "Creating ECR repository..."
aws ecr create-repository \
  --repository-name $IMAGE_NAME \
  --region $AWS_REGION

# Wait a moment for repo to be ready
sleep 5

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Build Docker image
echo "Building Docker image..."
cd /workspaces/Brain-Tasks-App
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# Tag image for ECR
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REGISTRY/$IMAGE_NAME:latest

# Push to ECR
echo "Pushing image to ECR..."
docker push $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
docker push $ECR_REGISTRY/$IMAGE_NAME:latest

# Verify image is in ECR
aws ecr list-images --repository-name $IMAGE_NAME --region $AWS_REGION

echo "✅ Image pushed to ECR!"
echo "Image URI: $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
```

---

### STEP 6: Create EKS Cluster (⏱️ Takes 15-20 minutes)

```bash
echo "Creating EKS cluster... (This will take 15-20 minutes)"
echo "You can monitor progress in AWS Console: EKS > Clusters > brain-tasks-cluster"

aws eks create-cluster \
  --name brain-tasks-cluster \
  --version 1.28 \
  --role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-cluster-role \
  --resources-vpc-config subnetIds=$SUBNET_1,$SUBNET_2 \
  --region $AWS_REGION \
  --logging '{"clusterLogging":[{"enabled":true,"types":["api","audit","authenticator","controllerManager","scheduler"]}]}'

# Wait for cluster to be ACTIVE (this takes time)
echo "Waiting for cluster to be active..."
while true; do
  STATUS=$(aws eks describe-cluster \
    --name brain-tasks-cluster \
    --region $AWS_REGION \
    --query 'cluster.status' \
    --output text)
  
  if [ "$STATUS" = "ACTIVE" ]; then
    echo "✅ Cluster is ACTIVE!"
    break
  else
    echo "Cluster status: $STATUS... waiting..."
    sleep 30
  fi
done

# Configure kubectl
echo "Configuring kubectl..."
aws eks update-kubeconfig \
  --name brain-tasks-cluster \
  --region $AWS_REGION

# Verify connection
kubectl cluster-info
echo "✅ kubectl configured successfully!"
```

---

### STEP 7: Create Node Group (⏱️ Takes 10-15 minutes)

```bash
echo "Creating managed node group... (Takes 10-15 minutes)"

aws eks create-nodegroup \
  --cluster-name brain-tasks-cluster \
  --nodegroup-name brain-tasks-nodegroup \
  --scaling-config minSize=2,maxSize=4,desiredSize=3 \
  --subnets $SUBNET_1 $SUBNET_2 \
  --node-role arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-node-role \
  --instance-types t3.medium \
  --region $AWS_REGION

echo "Waiting for nodes to be ready..."
kubectl get nodes -w
# Press Ctrl+C when all nodes show STATUS "Ready"

echo "✅ Node group created and nodes are ready!"
kubectl get nodes -o wide
```

---

### STEP 8: Create ImagePullSecret

```bash
echo "Creating ImagePullSecret for ECR..."

kubectl create secret docker-registry ecr-secret \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region $AWS_REGION) \
  --docker-email=user@example.com \
  --namespace=default

# Verify
kubectl get secrets

echo "✅ ImagePullSecret created!"
```

---

### STEP 9: Deploy to Kubernetes

```bash
echo "Updating k8s manifests with your ECR image URI..."
cd /workspaces/Brain-Tasks-App

# Update deployment.yaml with your actual ECR URI
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app:latest|$ECR_REGISTRY/$IMAGE_NAME:latest|g" k8s-manifests/deployment.yaml

echo "Deploying to EKS..."
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

echo "Waiting for pods to become Ready..."
kubectl get pods -l app=brain-tasks-app -w
# Press Ctrl+C when all pods show "Running" and "3/3 Ready"

echo "✅ Deployment complete!"
```

---

### STEP 10: Get LoadBalancer URL

```bash
echo "Getting LoadBalancer information..."

# Wait for LoadBalancer to get external IP (takes a moment)
echo "Waiting for LoadBalancer to be provisioned..."
sleep 30

# Get LoadBalancer DNS/URL
LOAD_BALANCER_HOSTNAME=$(kubectl get svc brain-tasks-app-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$LOAD_BALANCER_HOSTNAME" ]; then
  echo "LoadBalancer DNS not yet assigned. Waiting..."
  kubectl get svc brain-tasks-app-service -w
else
  echo "✅ LoadBalancer URL: http://$LOAD_BALANCER_HOSTNAME"
  
  # Test the application
  echo "Testing application..."
  curl -I http://$LOAD_BALANCER_HOSTNAME
  
  echo ""
  echo "🎉 Application is accessible at: http://$LOAD_BALANCER_HOSTNAME"
fi
```

---

### STEP 11: Get LoadBalancer ARN

```bash
echo "Getting LoadBalancer ARN..."

# List all load balancers
aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s`)].{Name:LoadBalancerName, ARN:LoadBalancerArn, DNS:DNSName}' \
  --output table

# To get specific one:
LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query 'LoadBalancers[?contains(LoadBalancerName, `brain-tasks-app`)].LoadBalancerArn' \
  --output text | head -1)

echo "LoadBalancer ARN: $LOAD_BALANCER_ARN"

# Save for submission
echo "LoadBalancer ARN: $LOAD_BALANCER_ARN" >> deployment_info.txt
```

---

### STEP 12: Create CodeBuild Project

```bash
echo "Creating CodeBuild project..."

aws codebuild create-project \
  --name brain-tasks-build \
  --source type=GITHUB,location=https://github.com/Vennilavan12/Brain-Tasks-App.git,gitCloneDepth=1 \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_MEDIUM \
  --service-role arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-codebuild-role \
  --logs-config cloudWatchLogs={status=ENABLED,groupName=/aws/codebuild/brain-tasks-build} \
  --region $AWS_REGION

echo "✅ CodeBuild project created!"

# Test build
echo "Starting test build..."
BUILD_ID=$(aws codebuild start-build \
  --project-name brain-tasks-build \
  --region $AWS_REGION \
  --query 'build.id' \
  --output text)

echo "Build ID: $BUILD_ID"
echo "Monitor at: https://console.aws.amazon.com/codesuite/codebuild/projects/brain-tasks-build"
```

---

### STEP 13: Create CodeDeploy Application

```bash
echo "Creating CodeDeploy application..."

aws deploy create-app \
  --application-name brain-tasks-app \
  --region $AWS_REGION

# Create deployment group
aws deploy create-deployment-group \
  --application-name brain-tasks-app \
  --deployment-group-name brain-tasks-deployment-group \
  --service-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-codedeploy-role \
  --deployment-config-name CodeDeployDefault.OneAtATime \
  --region $AWS_REGION

echo "✅ CodeDeploy application created!"
```

---

### STEP 14: Create CodePipeline (Requires GitHub PAT)

```bash
echo "Creating CodePipeline..."
echo "⚠️  You need a GitHub Personal Access Token (PAT)"
echo "Get it from: https://github.com/settings/tokens/new"
echo "Required scopes: repo, admin:repo_hook"

# Create S3 bucket for artifacts
aws s3 mb s3://$ARTIFACT_BUCKET --region $AWS_REGION 2>/dev/null || true

# Create pipeline (simplified version)
# For production, use the detailed JSON from AWS_DEPLOYMENT_STEPS.md

echo "Create the pipeline in AWS Console:"
echo "1. Go to CodePipeline > Create pipeline"
echo "2. Name: brain-tasks-pipeline"
echo "3. Source: GitHub (Vennilavan12/Brain-Tasks-App, main)"
echo "4. Build: CodeBuild (brain-tasks-build)"
echo "5. Deploy: CodeDeploy (brain-tasks-app / brain-tasks-deployment-group)"
echo "6. Create!"

echo "✅ CodePipeline setup guide provided!"
```

---

### STEP 15: CloudWatch Logs

```bash
echo "Creating CloudWatch log groups..."

aws logs create-log-group --log-group-name /aws/eks/brain-tasks-app --region $AWS_REGION 2>/dev/null || true
aws logs create-log-group --log-group-name /aws/codebuild/brain-tasks-build --region $AWS_REGION 2>/dev/null || true
aws logs create-log-group --log-group-name /aws/codedeploy/brain-tasks-app --region $AWS_REGION 2>/dev/null || true

# Set retention to 30 days
aws logs put-retention-policy \
  --log-group-name /aws/eks/brain-tasks-app \
  --retention-in-days 30 \
  --region $AWS_REGION

echo "✅ CloudWatch log groups created!"
echo ""
echo "View logs:"
echo "  EKS: aws logs tail /aws/eks/brain-tasks-app --follow --region $AWS_REGION"
echo "  CodeBuild: aws logs tail /aws/codebuild/brain-tasks-build --follow --region $AWS_REGION"
```

---

## 📊 Verification Checklist

After completing all steps, verify:

```bash
# 1. Check cluster is running
aws eks describe-cluster --name brain-tasks-cluster --region $AWS_REGION --query 'cluster.status'

# 2. Check nodes are ready
kubectl get nodes -o wide
# All nodes should show STATUS "Ready"

# 3. Check deployment
kubectl get deployment brain-tasks-app
# Should show: DESIRED 3, CURRENT 3, READY 3, AVAILABLE 3

# 4. Check pods
kubectl get pods -l app=brain-tasks-app
# All pods should show STATUS "Running"

# 5. Check service
kubectl get svc brain-tasks-app-service
# Should show EXTERNAL-IP (LoadBalancer URL)

# 6. Test application
curl http://$(kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
# Should return HTML response

# 7. Check images in ECR
aws ecr list-images --repository-name brain-tasks-app --region $AWS_REGION

# 8. Check logs
kubectl logs -l app=brain-tasks-app --tail=50
```

---

## 📝 Summary of Resources Created

1. **IAM Roles** (5):
   - brain-tasks-eks-cluster-role
   - brain-tasks-eks-node-role
   - brain-tasks-codebuild-role
   - brain-tasks-codedeploy-role
   - brain-tasks-codepipeline-role

2. **Networking**:
   - VPC: 10.0.0.0/16
   - Subnets: 10.0.1.0/24, 10.0.2.0/24
   - Internet Gateway
   - Route Table

3. **Container Registry**:
   - ECR: brain-tasks-app

4. **Kubernetes**:
   - EKS Cluster: brain-tasks-cluster
   - Node Group: brain-tasks-nodegroup (3 nodes)
   - Deployment: brain-tasks-app
   - Service: brain-tasks-app-service (LoadBalancer)

5. **CI/CD**:
   - CodeBuild: brain-tasks-build
   - CodeDeploy: brain-tasks-app
   - CodePipeline: brain-tasks-pipeline
   - S3 Bucket: brain-tasks-artifacts-{ACCOUNT_ID}

6. **Monitoring**:
   - CloudWatch Log Groups (3)

---

## 🧹 Cleanup Commands (When Done)

```bash
# Delete all resources
kubectl delete svc brain-tasks-app-service
kubectl delete deployment brain-tasks-app
aws eks delete-nodegroup --cluster-name brain-tasks-cluster --nodegroup-name brain-tasks-nodegroup
aws eks delete-cluster --name brain-tasks-cluster
aws ecr delete-repository --repository-name brain-tasks-app --force
aws codepipeline delete-pipeline --name brain-tasks-pipeline
aws codebuild delete-project --name brain-tasks-build
aws deploy delete-app --application-name brain-tasks-app
aws s3 rb s3://$ARTIFACT_BUCKET --force

# Cleanup IAM roles (delete policies first, then roles)
aws iam delete-role-policy --role-name brain-tasks-eks-cluster-role --policy-name AmazonEKSClusterPolicy
aws iam delete-role --role-name brain-tasks-eks-cluster-role
# ... (repeat for other roles)
```

---

## 📞 Need Help?

- **AWS Documentation**: https://docs.aws.amazon.com/eks/
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Troubleshooting**: See AWS_DEPLOYMENT_STEPS.md Troubleshooting section

---

**Generated**: 2024
**Application**: Brain Tasks React App
**Deployment Target**: AWS EKS with CodePipeline CI/CD
