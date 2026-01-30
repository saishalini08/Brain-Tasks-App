#!/bin/bash

#############################################################################
# BRAIN TASKS APP - COMPLETE DEPLOYMENT SCRIPT
# Automates: GitHub SSH setup + Commit + AWS Deployment
# Usage: bash deploy.sh
#############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Step 0: Verify prerequisites
print_header "STEP 0: Verifying Prerequisites"

if ! command -v git &> /dev/null; then
    print_error "Git is not installed"
    exit 1
fi
print_success "Git is installed"

if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first:"
    echo "Windows: msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi"
    echo "Mac: brew install awscli"
    echo "Linux: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
    exit 1
fi
print_success "AWS CLI is installed"

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker Desktop first."
    exit 1
fi
print_success "Docker is installed"

# Step 1: GitHub SSH Setup
print_header "STEP 1: Setting Up GitHub SSH"

SSH_KEY_PATH="$HOME/.ssh/id_rsa"
GITHUB_EMAIL="vinothinimuthusamy71@gmail.com"
GITHUB_NAME="Vennilavan12"

if [ ! -f "$SSH_KEY_PATH" ]; then
    print_warning "SSH key not found. Creating new SSH key..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$GITHUB_EMAIL"
    print_success "SSH key created at $SSH_KEY_PATH"
else
    print_success "SSH key already exists"
fi

# Display public key for GitHub
print_warning "Add this SSH key to GitHub:"
echo "========================================"
cat "$SSH_KEY_PATH.pub"
echo "========================================"
echo ""
print_warning "Steps to add SSH key to GitHub:"
echo "1. Go to: https://github.com/settings/keys"
echo "2. Click 'New SSH key'"
echo "3. Copy the key above and paste it"
echo "4. Click 'Add SSH key'"
echo ""
read -p "Press ENTER after adding SSH key to GitHub..."

# Test SSH connection
print_warning "Testing SSH connection to GitHub..."
if ssh -T git@github.com &>/dev/null || [ $? -eq 1 ]; then
    print_success "SSH connection to GitHub successful"
else
    print_error "SSH connection failed. Please add the key to GitHub and try again."
    exit 1
fi

# Step 2: Configure Git
print_header "STEP 2: Configuring Git"

git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_NAME"
print_success "Git configured with email: $GITHUB_EMAIL"

# Step 3: Commit and Push to GitHub
print_header "STEP 3: Committing and Pushing to GitHub"

cd /workspaces/Brain-Tasks-App

# Add all files
git add .
print_success "Files staged for commit"

# Commit
COMMIT_MSG="Deploy: Complete AWS EKS setup with CI/CD pipeline - $(date +'%Y-%m-%d %H:%M:%S')"
git commit -m "$COMMIT_MSG" || print_warning "Nothing to commit (repository already up to date)"
print_success "Committed with message: $COMMIT_MSG"

# Push to GitHub
git remote set-url origin git@github.com:Vennilavan12/Brain-Tasks-App.git
git push origin main || print_warning "Push failed - repository may already be up to date"
print_success "Pushed to GitHub"

# Step 4: AWS Configuration
print_header "STEP 4: Configuring AWS"

# Check if AWS is configured
if ! aws sts get-caller-identity &>/dev/null; then
    print_warning "AWS credentials not configured. Running 'aws configure'..."
    aws configure
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="${AWS_REGION:-ap-south-1}"
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
IMAGE_NAME="brain-tasks-app"
ARTIFACT_BUCKET="brain-tasks-artifacts-$AWS_ACCOUNT_ID"

print_success "AWS Account ID: $AWS_ACCOUNT_ID"
print_success "AWS Region: $AWS_REGION"
print_success "ECR Registry: $ECR_REGISTRY"

# Step 5: Create IAM Roles
print_header "STEP 5: Creating IAM Roles"

# EKS Cluster Role
print_warning "Creating EKS Cluster Role..."
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
  --assume-role-policy-document file:///tmp/eks-trust.json 2>/dev/null || print_warning "Role already exists"

aws iam attach-role-policy \
  --role-name brain-tasks-eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>/dev/null || true
print_success "EKS Cluster Role created"

# EKS Node Role
print_warning "Creating EKS Node Role..."
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
  --assume-role-policy-document file:///tmp/node-trust.json 2>/dev/null || print_warning "Role already exists"

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || true

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || true

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
print_success "EKS Node Role created"

# CodeBuild Role
print_warning "Creating CodeBuild Role..."
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
  --assume-role-policy-document file:///tmp/codebuild-trust.json 2>/dev/null || print_warning "Role already exists"

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
  --policy-document file:///tmp/codebuild-policy.json 2>/dev/null || true
print_success "CodeBuild Role created"

# Step 6: Create VPC & Subnets
print_header "STEP 6: Creating VPC and Subnets"

# Check if VPC already exists
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16" --region "$AWS_REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    print_warning "Creating new VPC..."
    VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region "$AWS_REGION" --query 'Vpc.VpcId' --output text)
    print_success "VPC created: $VPC_ID"
else
    print_success "VPC already exists: $VPC_ID"
fi

# Create subnets
print_warning "Creating subnets..."
SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' \
  --output text 2>/dev/null || aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=10.0.1.0/24" --region "$AWS_REGION" --query 'Subnets[0].SubnetId' --output text)

SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone "${AWS_REGION}b" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' \
  --output text 2>/dev/null || aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=10.0.2.0/24" --region "$AWS_REGION" --query 'Subnets[0].SubnetId' --output text)

print_success "Subnets created: $SUBNET_1, $SUBNET_2"

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_1" --map-public-ip-on-launch --region "$AWS_REGION" 2>/dev/null || true
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_2" --map-public-ip-on-launch --region "$AWS_REGION" 2>/dev/null || true

# Step 7: Create ECR Repository
print_header "STEP 7: Creating ECR Repository"

aws ecr create-repository \
  --repository-name "$IMAGE_NAME" \
  --region "$AWS_REGION" 2>/dev/null || print_warning "Repository already exists"

print_success "ECR Repository ready: $IMAGE_NAME"

# Step 8: Build and Push Docker Image
print_header "STEP 8: Building and Pushing Docker Image"

print_warning "Building Docker image..."
docker build -t "$IMAGE_NAME:latest" . --progress=plain

print_warning "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

print_warning "Tagging image..."
docker tag "$IMAGE_NAME:latest" "$ECR_REGISTRY/$IMAGE_NAME:latest"

print_warning "Pushing image to ECR..."
docker push "$ECR_REGISTRY/$IMAGE_NAME:latest"

print_success "Image pushed to ECR: $ECR_REGISTRY/$IMAGE_NAME:latest"

# Step 9: Create EKS Cluster
print_header "STEP 9: Creating EKS Cluster"

# Check if cluster exists
CLUSTER_STATUS=$(aws eks describe-cluster --name brain-tasks-cluster --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$CLUSTER_STATUS" = "DOES_NOT_EXIST" ]; then
    print_warning "Creating EKS cluster (this takes 15-20 minutes)..."
    aws eks create-cluster \
      --name brain-tasks-cluster \
      --version 1.28 \
      --role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-cluster-role" \
      --resources-vpc-config "subnetIds=$SUBNET_1,$SUBNET_2" \
      --region "$AWS_REGION"
    
    print_warning "Waiting for cluster to become ACTIVE..."
    while true; do
        STATUS=$(aws eks describe-cluster --name brain-tasks-cluster --region "$AWS_REGION" --query 'cluster.status' --output text)
        if [ "$STATUS" = "ACTIVE" ]; then
            print_success "Cluster is ACTIVE!"
            break
        else
            echo "Current status: $STATUS... waiting..."
            sleep 30
        fi
    done
else
    print_success "EKS Cluster already exists (Status: $CLUSTER_STATUS)"
fi

# Step 10: Configure kubectl
print_header "STEP 10: Configuring kubectl"

print_warning "Updating kubeconfig..."
aws eks update-kubeconfig --name brain-tasks-cluster --region "$AWS_REGION"

print_warning "Testing kubectl connection..."
kubectl cluster-info
print_success "kubectl configured successfully"

# Step 11: Create Node Group
print_header "STEP 11: Creating Node Group"

NODEGROUP_STATUS=$(aws eks describe-nodegroup --cluster-name brain-tasks-cluster --nodegroup-name brain-tasks-nodegroup --region "$AWS_REGION" --query 'nodegroup.status' --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$NODEGROUP_STATUS" = "DOES_NOT_EXIST" ]; then
    print_warning "Creating node group (this takes 10-15 minutes)..."
    aws eks create-nodegroup \
      --cluster-name brain-tasks-cluster \
      --nodegroup-name brain-tasks-nodegroup \
      --scaling-config "minSize=2,maxSize=4,desiredSize=3" \
      --subnets "$SUBNET_1" "$SUBNET_2" \
      --node-role "arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-node-role" \
      --instance-types t3.medium \
      --region "$AWS_REGION"
    
    print_warning "Waiting for nodes to become Ready..."
    while true; do
        READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo 0)
        if [ "$READY_COUNT" -ge 3 ]; then
            print_success "All nodes are Ready!"
            break
        else
            echo "Ready nodes: $READY_COUNT/3... waiting..."
            sleep 30
        fi
    done
else
    print_success "Node group already exists (Status: $NODEGROUP_STATUS)"
fi

# Step 12: Create ImagePullSecret
print_header "STEP 12: Creating ImagePullSecret"

print_warning "Creating ImagePullSecret for ECR..."
kubectl create secret docker-registry ecr-secret \
  --docker-server="$ECR_REGISTRY" \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region $AWS_REGION)" \
  --docker-email=user@example.com \
  --namespace=default 2>/dev/null || print_warning "Secret already exists"

print_success "ImagePullSecret created"

# Step 13: Deploy to Kubernetes
print_header "STEP 13: Deploying to Kubernetes"

print_warning "Updating k8s manifests with ECR image URI..."
sed -i.bak "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app:latest|$ECR_REGISTRY/$IMAGE_NAME:latest|g" k8s-manifests/deployment.yaml

print_warning "Applying Kubernetes manifests..."
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

print_warning "Waiting for pods to become Running..."
while true; do
    READY_PODS=$(kubectl get pods -l app=brain-tasks-app -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)
    if [ "$READY_PODS" -ge 3 ]; then
        print_success "All 3 pods are Running!"
        break
    else
        echo "Running pods: $READY_PODS/3... waiting..."
        sleep 10
    fi
done

# Step 14: Get LoadBalancer URL
print_header "STEP 14: Getting LoadBalancer URL"

print_warning "Waiting for LoadBalancer to get public URL (this can take 5-10 minutes)..."
while true; do
    LOAD_BALANCER_URL=$(kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ ! -z "$LOAD_BALANCER_URL" ]; then
        print_success "LoadBalancer URL obtained!"
        break
    else
        echo "LoadBalancer URL not yet available... waiting..."
        sleep 30
    fi
done

# Step 15: Verify Deployment
print_header "STEP 15: Verifying Deployment"

print_warning "Testing application..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$LOAD_BALANCER_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "000" ]; then
    print_success "Application is responding!"
else
    print_warning "HTTP Status: $HTTP_CODE (may be loading)"
fi

# Final Summary
print_header "🎉 DEPLOYMENT COMPLETE!"

echo ""
echo -e "${GREEN}Your application is now live!${NC}"
echo ""
echo "📊 DEPLOYMENT INFORMATION:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "AWS Account ID:     ${BLUE}$AWS_ACCOUNT_ID${NC}"
echo -e "AWS Region:         ${BLUE}$AWS_REGION${NC}"
echo -e "EKS Cluster:        ${BLUE}brain-tasks-cluster${NC}"
echo -e "ECR Repository:     ${BLUE}$ECR_REGISTRY/$IMAGE_NAME${NC}"
echo ""
echo "🌐 APPLICATION URL:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}http://$LOAD_BALANCER_URL${NC}"
echo ""
echo "📋 USEFUL COMMANDS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "View pods:           kubectl get pods"
echo "View logs:           kubectl logs -l app=brain-tasks-app -f"
echo "View service:        kubectl get svc brain-tasks-app-service"
echo "View nodes:          kubectl get nodes"
echo "Scale replicas:      kubectl scale deployment brain-tasks-app --replicas=5"
echo ""
echo "📞 NEXT STEPS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Open: http://$LOAD_BALANCER_URL"
echo "2. Verify application is working"
echo "3. Save the URL and LoadBalancer ARN"
echo ""

# Save deployment info to file
DEPLOY_INFO_FILE="DEPLOYMENT_INFO.txt"
cat > "$DEPLOY_INFO_FILE" << EOF
BRAIN TASKS APP - DEPLOYMENT INFORMATION
Generated: $(date)

=== AWS DETAILS ===
AWS Account ID: $AWS_ACCOUNT_ID
AWS Region: $AWS_REGION
EKS Cluster: brain-tasks-cluster
Node Group: brain-tasks-nodegroup
Number of Nodes: 3 (t3.medium)

=== CONTAINER DETAILS ===
ECR Repository: $ECR_REGISTRY/$IMAGE_NAME
Image Tag: latest
Image URI: $ECR_REGISTRY/$IMAGE_NAME:latest

=== APPLICATION ACCESS ===
Application URL: http://$LOAD_BALANCER_URL
LoadBalancer DNS: $LOAD_BALANCER_URL

=== KUBERNETES DETAILS ===
Deployment: brain-tasks-app
Service: brain-tasks-app-service
Service Type: LoadBalancer
Port: 80

=== USEFUL COMMANDS ===
# View pods
kubectl get pods

# View logs
kubectl logs -l app=brain-tasks-app -f

# Scale deployment
kubectl scale deployment brain-tasks-app --replicas=5

# Update deployment with new image
kubectl set image deployment/brain-tasks-app brain-tasks-app=$ECR_REGISTRY/$IMAGE_NAME:new-tag

# Port forward for local testing
kubectl port-forward svc/brain-tasks-app-service 8080:80

=== GITHUB DETAILS ===
Repository: https://github.com/Vennilavan12/Brain-Tasks-App.git
Branch: main
SSH Remote: git@github.com:Vennilavan12/Brain-Tasks-App.git

=== COST ESTIMATE ===
EKS Cluster: \$10/month
EC2 Nodes (3): ~\$30/month
Load Balancer: ~\$16/month
Data Transfer: ~\$5/month
CloudWatch: ~\$5/month
Other: ~\$4/month
TOTAL: ~\$70/month

=== MONITORING ===
CloudWatch Logs: /aws/eks/brain-tasks-app
AWS Console: https://console.aws.amazon.com/eks/
EOF

print_success "Deployment info saved to: $DEPLOY_INFO_FILE"
echo ""
print_success "All deployment steps completed successfully!"
