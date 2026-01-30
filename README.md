# Brain Tasks App - Production Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying the Brain Tasks React application to production using AWS EKS, CodeBuild, CodeDeploy, and CodePipeline.

## Prerequisites
- AWS Account with appropriate IAM permissions
- Docker installed locally
- kubectl CLI installed
- AWS CLI v2 installed and configured
- Git installed
- Node.js 16+ and npm installed

---

## STEP 1: Local Setup & Testing

### 1.1 Clone and Run Locally
```bash
# Navigate to your workspace
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Install dependencies
npm install

# Build the application
npm run build

# Test locally (optional, if dev server available)
npm start  # Should run on port 3000
```

### 1.2 Verify Build Output
```bash
# Check if dist folder exists
ls -la dist/
```

---

## STEP 2: Docker Setup

### 2.1 Current Dockerfile Overview
Your Dockerfile is configured to:
- Use nginx:alpine as base image
- Copy built dist files to nginx html folder
- Expose port 80

### 2.2 Build Docker Image Locally
```bash
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Build the image
docker build -t brain-tasks-app:latest .

# Test the image
docker run -d -p 3000:80 brain-tasks-app:latest

# Verify it's running
docker ps

# Test in browser
# Navigate to http://localhost:3000
```

### 2.3 Stop and Clean Up
```bash
docker stop <container-id>
docker rm <container-id>
```

---

## STEP 3: AWS ECR Setup (Create Container Registry)

### 3.1 Create ECR Repository
```bash
# Set your AWS region
$AWS_REGION = "us-east-1"  # Change as needed
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

# Create ECR repository
aws ecr create-repository `
  --repository-name brain-tasks-app `
  --region $AWS_REGION

# Output will show:
# {
#     "repository": {
#         "repositoryUri": "ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app",
#         ...
#     }
# }
# Save this URI - you'll need it later
```

### 3.2 Login and Push Image to ECR
```bash
# Login to ECR
$ECR_REGISTRY = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

aws ecr get-login-password --region $AWS_REGION | `
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Tag local image for ECR
docker tag brain-tasks-app:latest `
  $ECR_REGISTRY/brain-tasks-app:latest

# Push to ECR
docker push $ECR_REGISTRY/brain-tasks-app:latest

# Verify push
aws ecr describe-images --repository-name brain-tasks-app --region $AWS_REGION
```

---

## STEP 4: AWS EKS Setup (Kubernetes Cluster)

### 4.1 Create EKS Cluster
```bash
# Install eksctl (if not already installed)
# PowerShell
choco install eksctl  # or download from https://eksctl.io

# Create cluster (this takes 15-20 minutes)
$CLUSTER_NAME = "brain-tasks-cluster"
$AWS_REGION = "us-east-1"
$NODE_COUNT = 3

eksctl create cluster `
  --name $CLUSTER_NAME `
  --region $AWS_REGION `
  --nodegroup-name ng-default `
  --node-type t3.medium `
  --nodes $NODE_COUNT `
  --managed

# Output: Cluster created successfully with ARN shown
# Example: arn:aws:eks:us-east-1:123456789012:cluster/brain-tasks-cluster
```

### 4.2 Verify Cluster is Running
```bash
# Update kubeconfig
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Verify nodes are running
kubectl get nodes

# You should see 3 nodes in Ready state
# NAME                                           STATUS   ROLES    AGE
# ip-192-168-xx-xx.ec2.internal                 Ready    <none>   10m
# ip-192-168-xx-xx.ec2.internal                 Ready    <none>   10m
# ip-192-168-xx-xx.ec2.internal                 Ready    <none>   10m
```

### 4.3 Create IAM Role for CodeBuild to Push to ECR
```bash
# Create policy document
$POLICY = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    }
  ]
}
"@

# Save and create policy
$POLICY | Out-File -FilePath policy.json
aws iam create-role --role-name CodeBuildEKSRole `
  --assume-role-policy-document file://trust-policy.json
```

---

## STEP 5: AWS CodeBuild Setup

### 5.1 Create CodeBuild Project
```bash
# In AWS Console:
# 1. Go to CodeBuild > Create build project
# 2. Name: brain-tasks-build
# 3. Source provider: GitHub
# 4. Repository: Your GitHub URL
# 5. Webhook: Check "Rebuild every time a code change is pushed to this repository"
# 6. Environment:
#    - OS: Amazon Linux 2
#    - Runtime: Standard
#    - Image: aws/codebuild/standard:5.0
# 7. Service role: Create new role
# 8. Buildspec: Use buildspec.yml from repository
```

### 5.2 Update buildspec.yml
The buildspec.yml file is already included in the repository with:
- Phase 1: Login to ECR
- Phase 2: Build Docker image
- Phase 3: Push to ECR
- Artifacts: imagedefinitions.json

---

## STEP 6: AWS CodeDeploy Setup

### 6.1 Create CodeDeploy Application
```bash
# In AWS Console:
# 1. Go to CodeDeploy > Applications > Create application
# 2. Application name: brain-tasks-app
# 3. Compute platform: ECS
# (Alternative: Use Lambda + custom script for EKS deployment)
```

### 6.2 Create Deployment Group
```bash
# 1. Go to Deployment groups > Create deployment group
# 2. Deployment group name: brain-tasks-dg
# 3. Service role: Create/select appropriate role
# 4. Deployment type: Blue/green
# 5. Environment configuration: Select your ECS/EC2 instances
```

### 6.3 Update appspec.yml
The appspec.yml is included with ECS deployment configuration. For EKS, you can create a Lambda function that runs:
```bash
kubectl apply -f k8s-manifests/
kubectl rollout status deployment/brain-tasks-app
```

---

## STEP 7: Kubernetes Deployment Files

### 7.1 Update deployment.yaml
Edit [k8s-manifests/deployment.yaml](k8s-manifests/deployment.yaml):
- Replace `ACCOUNT_ID` with your AWS account ID
- Replace `REGION` with your AWS region (e.g., us-east-1)

Example:
```bash
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$REGION = "us-east-1"

(Get-Content k8s-manifests/deployment.yaml) -replace 'ACCOUNT_ID', $ACCOUNT_ID | Set-Content k8s-manifests/deployment.yaml
(Get-Content k8s-manifests/deployment.yaml) -replace 'REGION', $REGION | Set-Content k8s-manifests/deployment.yaml
```

### 7.2 Deploy Kubernetes Manifests
```bash
# Update kubeconfig first
aws eks update-kubeconfig --name brain-tasks-cluster --region us-east-1

# Apply manifests
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

# Verify deployment
kubectl get deployments
kubectl get services

# Example output:
# NAME               READY   UP-TO-DATE   AVAILABLE
# brain-tasks-app    3/3     3            3
#
# NAME                        TYPE           CLUSTER-IP    EXTERNAL-IP
# brain-tasks-app-service     LoadBalancer   10.100.x.x    a1b2c3d4...elb.amazonaws.com
```

### 7.3 Get LoadBalancer URL
```bash
# Get the external IP/hostname
kubectl get svc brain-tasks-app-service

# Copy the EXTERNAL-IP value and test in browser
# http://a1b2c3d4...elb.amazonaws.com

# Monitor deployment
kubectl logs -f deployment/brain-tasks-app
```

---

## STEP 8: AWS CodePipeline Setup

### 8.1 Create Pipeline
```bash
# In AWS Console:
# 1. Go to CodePipeline > Create pipeline
# 2. Pipeline name: brain-tasks-pipeline
# 3. Service role: Create new or use existing
```

### 8.2 Pipeline Stages

**Stage 1: Source**
- Provider: GitHub (v2)
- Repository: Your GitHub URL
- Branch: main
- Trigger: On code change

**Stage 2: Build**
- Provider: AWS CodeBuild
- Project name: brain-tasks-build
- Output artifacts: BuildArtifact

**Stage 3: Deploy**
Option A - CodeDeploy:
- Provider: AWS CodeDeploy
- Application name: brain-tasks-app
- Deployment group: brain-tasks-dg

Option B - EKS with Lambda:
- Provider: AWS Lambda
- Function: Deploy to EKS function (with kubectl commands)

---

## STEP 9: Push Code to GitHub

### 9.1 Create GitHub Repository
```bash
# In GitHub web UI:
# 1. Create new repository: Brain-Tasks-App
# 2. Do NOT initialize with README (you already have one)
```

### 9.2 Push Local Code
```bash
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Add GitHub remote
git remote set-url origin https://github.com/YOUR_USERNAME/Brain-Tasks-App.git

# Add all files
git add .

# Commit
git commit -m "Initial deployment setup with Docker, K8s, CodeBuild, CodeDeploy, and CodePipeline"

# Push to GitHub
git push -u origin main

# Verify
git log --oneline -5
```

---

## STEP 10: CloudWatch Monitoring

### 10.1 View CodeBuild Logs
```bash
# In AWS Console:
# CodeBuild > Your Project > Latest Build > Logs
```

### 10.2 View CodeDeploy Logs
```bash
# In AWS Console:
# CodeDeploy > Applications > brain-tasks-app > Deployments
```

### 10.3 View EKS Logs
```bash
# Pod logs
kubectl logs -f pod/<pod-name>

# Deployment logs
kubectl logs -f deployment/brain-tasks-app

# Events
kubectl describe deployment brain-tasks-app

# All resources
kubectl get all
```

### 10.4 Create CloudWatch Dashboard
```bash
# In AWS Console > CloudWatch > Dashboards > Create dashboard
# Add widgets:
# - CodeBuild success/failure rate
# - EKS node CPU/Memory
# - Pod restart count
# - LoadBalancer request count
```

---

## STEP 11: Complete Execution Summary

### Manual Testing Checklist:
- [ ] Application builds locally: `npm run build`
- [ ] Docker image builds: `docker build -t brain-tasks-app:latest .`
- [ ] Docker container runs: `docker run -d -p 3000:80 brain-tasks-app:latest`
- [ ] Accessible at http://localhost:3000
- [ ] Image pushed to ECR
- [ ] EKS cluster running (3 nodes)
- [ ] Kubernetes manifests deployed
- [ ] LoadBalancer service has external IP
- [ ] Application accessible via LoadBalancer URL
- [ ] CodeBuild project created and tested
- [ ] CodePipeline created and triggers on commit
- [ ] CloudWatch logs showing deployment progress

### Submission Details:
- **GitHub Repository URL**: https://github.com/YOUR_USERNAME/Brain-Tasks-App
- **LoadBalancer ARN**: Run below command to get it
  ```bash
  kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
  # or for ALB
  kubectl describe svc brain-tasks-app-service | grep "LoadBalancer Ingress"
  ```
- **Application URL**: http://<LoadBalancer-URL>
- **EKS Cluster ARN**: `arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/brain-tasks-cluster`

---

## Troubleshooting

### Pod not starting?
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Image not found in ECR?
```bash
aws ecr describe-images --repository-name brain-tasks-app
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app:latest
```

### LoadBalancer stuck in pending?
```bash
kubectl describe svc brain-tasks-app-service
# May take 5-10 minutes for AWS to provision load balancer
```

### CodeBuild failing?
- Check IAM role has ECR and EKS permissions
- Check buildspec.yml syntax
- Review CodeBuild logs in console

### Pipeline not triggering?
- Verify GitHub webhook in CodePipeline settings
- Check branch matches pipeline configuration
- Review IAM service role permissions

---

## Important Variables to Update
Replace these throughout the setup:
- `ACCOUNT_ID`: Your AWS Account ID (12 digits)
- `REGION`: Your AWS Region (us-east-1, us-west-2, etc.)
- `YOUR_USERNAME`: Your GitHub username
- `CLUSTER_NAME`: Your EKS cluster name

---

## Cost Optimization Tips
1. Use spot instances for EKS nodes (save ~70%)
2. Enable cluster autoscaling
3. Set resource limits in deployment.yaml
4. Use AWS Savings Plans for predictable workloads
5. Implement pod autoscaling (HPA)

---

## Next Steps
1. Complete all manual steps above
2. Document any custom configurations
3. Take screenshots of:
   - CodeBuild successful build
   - CodePipeline execution
   - EKS cluster with running pods
   - LoadBalancer with external IP
   - Application running in browser
4. Share GitHub repository link
5. Provide LoadBalancer URL/ARN

---

**Last Updated**: January 30, 2026
**Status**: Ready for production deployment
