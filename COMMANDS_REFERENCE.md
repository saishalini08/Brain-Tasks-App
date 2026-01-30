# 🎯 Quick Command Reference - Copy & Paste Ready

## Credentials & Info
```powershell
# Get AWS Account ID (needed for multiple steps)
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
Write-Host "AWS Account ID: $ACCOUNT_ID"

# Set region
$REGION = "us-east-1"

# Set cluster name
$CLUSTER_NAME = "brain-tasks-cluster"
```

## Step 1: Local Docker Testing
```powershell
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Build React app
npm install
npm run build

# Build Docker image
docker build -t brain-tasks-app:latest .

# Run and test
docker run -d -p 3000:80 brain-tasks-app:latest

# Check running
docker ps

# Stop when done
docker stop <container-id>
```

## Step 2: AWS ECR Setup
```powershell
# Create ECR repository
aws ecr create-repository `
  --repository-name brain-tasks-app `
  --region us-east-1

# Login to ECR
$ECR_REGISTRY = "$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com"

aws ecr get-login-password --region us-east-1 | `
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Tag and push image
docker tag brain-tasks-app:latest $ECR_REGISTRY/brain-tasks-app:latest
docker push $ECR_REGISTRY/brain-tasks-app:latest

# Verify
aws ecr describe-images --repository-name brain-tasks-app --region us-east-1
```

## Step 3: Create EKS Cluster
```powershell
# Create cluster (takes 15-20 minutes)
eksctl create cluster `
  --name brain-tasks-cluster `
  --region us-east-1 `
  --nodegroup-name default `
  --node-type t3.medium `
  --nodes 3 `
  --managed

# Verify cluster running
aws eks describe-cluster `
  --name brain-tasks-cluster `
  --region us-east-1 `
  --query 'cluster.status'

# Update kubeconfig
aws eks update-kubeconfig `
  --name brain-tasks-cluster `
  --region us-east-1
```

## Step 4: Verify Kubernetes Cluster
```powershell
# Check cluster
kubectl cluster-info

# Check nodes (should be 3 in Ready state)
kubectl get nodes

# Detailed node info
kubectl describe nodes

# Get cluster version
kubectl version
```

## Step 5: Update & Deploy Kubernetes Manifests
```powershell
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Update deployment.yaml with your account ID
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$REGION = "us-east-1"

$file = "k8s-manifests/deployment.yaml"
$content = Get-Content $file
$content = $content -replace 'ACCOUNT_ID', $ACCOUNT_ID
$content = $content -replace 'REGION', $REGION
Set-Content $file $content

# Deploy to Kubernetes
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

# Check deployment
kubectl get deployment brain-tasks-app

# Check pods
kubectl get pods

# Check service (EXTERNAL-IP may take 5-10 min)
kubectl get svc brain-tasks-app-service
```

## Step 6: Monitor Deployment
```powershell
# Watch deployment status
kubectl rollout status deployment/brain-tasks-app

# Watch service for LoadBalancer IP
kubectl get svc brain-tasks-app-service --watch

# Get pod details
kubectl describe pod <pod-name>

# View pod logs
kubectl logs -f deployment/brain-tasks-app

# Get all resources
kubectl get all

# Detailed service info
kubectl describe svc brain-tasks-app-service
```

## Step 7: Test Application
```powershell
# Get LoadBalancer URL
kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test with curl (PowerShell)
$LB_URL = kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Invoke-WebRequest -Uri "http://$LB_URL" -UseBasicParsing

# Or open in browser:
# http://<EXTERNAL-IP>
```

## Step 8: Setup AWS CodeBuild
```powershell
# Create CodeBuild project
aws codebuild create-project `
  --name brain-tasks-build `
  --source type=GITHUB,location=https://github.com/YOUR_USERNAME/Brain-Tasks-App.git `
  --artifacts type=NO_ARTIFACTS `
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_SMALL `
  --service-role arn:aws:iam::$ACCOUNT_ID:role/CodeBuildECRRole

# List projects
aws codebuild batch-get-projects --names brain-tasks-build

# View build history
aws codebuild list-builds-for-project --project-name brain-tasks-build
```

## Step 9: Git Setup & Push
```powershell
# Configure git (one-time)
git config --global user.email "your-email@example.com"
git config --global user.name "Your Name"

cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Check current remote
git remote -v

# Update remote to your repository
git remote set-url origin https://github.com/YOUR_USERNAME/Brain-Tasks-App.git

# Push code
git push -u origin main

# Verify
git log --oneline -5
```

## Step 10: Create AWS CodePipeline (Use Console)
```
AWS Console > CodePipeline > Create Pipeline

Pipeline name: brain-tasks-pipeline
Service role: Create new

Source Stage:
  Provider: GitHub (v2)
  Repository: YOUR_USERNAME/Brain-Tasks-App
  Branch: main
  Webhook: Enable

Build Stage:
  Provider: AWS CodeBuild
  Project: brain-tasks-build

Deploy Stage:
  Provider: Manual Approval (or configure CodeDeploy)
  (Can use Lambda to deploy to EKS)

Create pipeline
```

## Monitoring & Logs
```powershell
# Kubernetes pod logs
kubectl logs -f deployment/brain-tasks-app

# Specific pod logs
kubectl logs -f pod/<pod-name>

# View pod events
kubectl describe pod <pod-name>

# Get node logs (if available)
kubectl describe nodes

# AWS CodeBuild logs
aws codebuild batch-get-builds --ids <build-id>

# CloudWatch logs
aws logs describe-log-groups
aws logs tail /aws/eks/brain-tasks-app --follow
```

## Cleanup Commands
```powershell
# Delete Kubernetes resources
kubectl delete deployment brain-tasks-app
kubectl delete svc brain-tasks-app-service
# Or
kubectl delete -f k8s-manifests/

# Delete EKS cluster (TAKES 10 MINUTES)
eksctl delete cluster `
  --name brain-tasks-cluster `
  --region us-east-1

# Delete ECR repository
aws ecr delete-repository `
  --repository-name brain-tasks-app `
  --region us-east-1 `
  --force

# Delete CodeBuild project
aws codebuild delete-project --name brain-tasks-build

# Delete CodePipeline
aws codepipeline delete-pipeline --name brain-tasks-pipeline
```

## Troubleshooting Commands
```powershell
# Check deployment status
kubectl get deployment -o wide
kubectl describe deployment brain-tasks-app
kubectl get replicaset

# Check pod status
kubectl get pods -o wide
kubectl get pods --all-namespaces

# Check service
kubectl get svc
kubectl describe svc brain-tasks-app-service

# Get detailed pod info
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# Check resource usage
kubectl top nodes
kubectl top pods

# Get all events
kubectl get events --sort-by='.lastTimestamp'

# Check image in ECR
aws ecr describe-images --repository-name brain-tasks-app

# Check cluster status
aws eks describe-cluster --name brain-tasks-cluster --query 'cluster.status'

# Get cluster kubeconfig
aws eks describe-cluster --name brain-tasks-cluster --query 'cluster.endpoint'

# Port forward to pod (for testing)
kubectl port-forward pod/<pod-name> 8080:80

# Exec into pod (for debugging)
kubectl exec -it <pod-name> -- /bin/sh

# Get pod YAML
kubectl get pod <pod-name> -o yaml

# Get all pod details
kubectl get pods -A -o wide
```

## Useful one-liners
```powershell
# Get LoadBalancer URL directly
kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | Write-Host

# Get all pod IPs
kubectl get pods -o jsonpath='{.items[*].status.podIP}'

# Get node IPs
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}'

# Get all service endpoints
kubectl get endpoints

# Scale deployment
kubectl scale deployment brain-tasks-app --replicas=5

# Update image
kubectl set image deployment/brain-tasks-app brain-tasks-app=$REGISTRY/brain-tasks-app:latest

# Rollback deployment
kubectl rollout undo deployment/brain-tasks-app

# View rollout history
kubectl rollout history deployment/brain-tasks-app

# Watch deployment
kubectl get deployment -w

# Get cluster info
aws eks describe-cluster --name brain-tasks-cluster --region us-east-1 | ConvertFrom-Json | Select -ExpandProperty cluster | Select arn, endpoint, status, version
```

## Useful Aliases (Add to Profile)
```powershell
# Add to PowerShell profile
# $PROFILE path: $PROFILE

# Useful aliases
Set-Alias -Name k -Value kubectl
Set-Alias -Name kgp -Value { kubectl get pods }
Set-Alias -Name kgs -Value { kubectl get svc }
Set-Alias -Name kgd -Value { kubectl get deployment }
Set-Alias -Name kga -Value { kubectl get all }
Set-Alias -Name kl -Value { kubectl logs -f }
```

---

**Copy & paste any command directly into PowerShell terminal**
