# Quick Start Guide - Brain Tasks App Deployment

## 📋 Files Created for Deployment

| File | Purpose |
|------|---------|
| `Dockerfile` | Docker image configuration (nginx + React build) |
| `buildspec.yml` | AWS CodeBuild build steps |
| `appspec.yml` | AWS CodeDeploy deployment configuration |
| `k8s-manifests/deployment.yaml` | Kubernetes deployment (3 replicas, rolling update) |
| `k8s-manifests/service.yaml` | Kubernetes LoadBalancer service |
| `.github/workflows/deploy.yml` | GitHub Actions CI/CD workflow |
| `README.md` | Complete deployment guide |

---

## 🚀 Quick Execution Steps

### Phase 1: Local Testing (5 minutes)
```powershell
# 1. Build React app
npm install
npm run build

# 2. Build Docker image
docker build -t brain-tasks-app:latest .

# 3. Run container
docker run -d -p 3000:80 brain-tasks-app:latest

# 4. Test at http://localhost:3000
# 5. Stop container
docker stop <container-id>
```

### Phase 2: AWS Setup (30 minutes)

#### A. Create ECR Repository
```powershell
$AWS_REGION = "us-east-1"
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

aws ecr create-repository `
  --repository-name brain-tasks-app `
  --region $AWS_REGION

# Save the repository URI shown in output
```

#### B. Push Image to ECR
```powershell
$ECR_REGISTRY = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Login
aws ecr get-login-password --region $AWS_REGION | `
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Tag & push
docker tag brain-tasks-app:latest $ECR_REGISTRY/brain-tasks-app:latest
docker push $ECR_REGISTRY/brain-tasks-app:latest
```

#### C. Create EKS Cluster (Takes 15-20 minutes)
```powershell
# Install eksctl if needed
choco install eksctl

# Create cluster
eksctl create cluster `
  --name brain-tasks-cluster `
  --region us-east-1 `
  --nodegroup-name ng-default `
  --node-type t3.medium `
  --nodes 3 `
  --managed

# When complete, update kubeconfig
aws eks update-kubeconfig --name brain-tasks-cluster --region us-east-1

# Verify
kubectl get nodes  # Should show 3 nodes
```

### Phase 3: Deploy to Kubernetes (5 minutes)

```powershell
# Update image URI in deployment.yaml
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$REGION = "us-east-1"

# Edit k8s-manifests/deployment.yaml and replace:
# - ACCOUNT_ID with your actual account ID
# - REGION with your region

# Deploy
kubectl apply -f k8s-manifests/

# Wait for LoadBalancer IP (5-10 minutes)
kubectl get svc brain-tasks-app-service

# Test application
# Visit: http://<EXTERNAL-IP>
```

### Phase 4: Push to GitHub (2 minutes)

```powershell
cd c:\Users\OW_USER\Desktop\Deployments\Brain-Tasks-App

# Configure GitHub (first time only)
git config user.email "your-email@example.com"
git config user.name "Your Name"

# Set origin to your GitHub repo
git remote set-url origin https://github.com/YOUR_USERNAME/Brain-Tasks-App.git

# Commit and push
git commit -m "Add deployment configuration: Docker, K8s, CodeBuild, CodeDeploy"
git push -u origin main

# Verify on GitHub
# https://github.com/YOUR_USERNAME/Brain-Tasks-App
```

### Phase 5: Setup AWS CodePipeline (15 minutes)

**In AWS Console:**

1. **CodeBuild Project**
   - Go to CodeBuild → Create project
   - Name: `brain-tasks-build`
   - Source: GitHub → Your repo URL
   - Environment: Standard:5.0 image
   - Buildspec: Use buildspec.yml from repo
   - Create

2. **CodeDeploy Application**
   - Go to CodeDeploy → Create application
   - Name: `brain-tasks-app`
   - Compute platform: ECS (or use Lambda for EKS)

3. **CodePipeline**
   - Go to CodePipeline → Create pipeline
   - Name: `brain-tasks-pipeline`
   - Source: GitHub (v2) → Select your repo
   - Build: CodeBuild → brain-tasks-build
   - Deploy: CodeDeploy → brain-tasks-app
   - Create pipeline

4. **Test Pipeline**
   - Make a commit to GitHub
   - Pipeline automatically triggers
   - Monitor in CodePipeline console

---

## 📊 Final Verification Checklist

- [ ] Docker image builds and runs locally on port 3000
- [ ] Image pushed to ECR successfully
- [ ] EKS cluster running with 3 nodes
- [ ] Kubernetes deployment shows 3 running pods: `kubectl get pods`
- [ ] LoadBalancer service has external IP: `kubectl get svc`
- [ ] Application accessible via LoadBalancer URL
- [ ] Code pushed to GitHub
- [ ] CodeBuild project created
- [ ] CodePipeline created and auto-triggers on commit
- [ ] CloudWatch logs showing deployment progress

---

## 🔗 Important URLs/ARNs to Collect

```powershell
# Get your values:
echo "AWS Account ID:"
aws sts get-caller-identity --query Account --output text

echo "EKS Cluster ARN:"
aws eks describe-cluster --name brain-tasks-cluster --region us-east-1 --query 'cluster.arn'

echo "LoadBalancer URL:"
kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

echo "ECR Repository URI:"
aws ecr describe-repositories --repository-names brain-tasks-app --region us-east-1 --query 'repositories[0].repositoryUri'
```

---

## 🐛 Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| Pod stuck in pending | Check resource limits in deployment.yaml |
| Image not found | Ensure image is in ECR: `aws ecr describe-images --repository-name brain-tasks-app` |
| LoadBalancer pending | Wait 5-10 min, AWS needs time to provision |
| CodeBuild failing | Check IAM role has ECR permissions |
| kubectl connection error | Update config: `aws eks update-kubeconfig --name brain-tasks-cluster --region us-east-1` |
| Port 3000 already in use | Change docker port: `docker run -d -p 3001:80 brain-tasks-app:latest` |

---

## 📝 Required GitHub Submission Details

**Submit these 3 things:**

1. **GitHub Repository Link**
   ```
   https://github.com/YOUR_USERNAME/Brain-Tasks-App
   ```

2. **Application Deployed LoadBalancer URL/ARN**
   ```
   kubectl get svc brain-tasks-app-service
   # Copy the EXTERNAL-IP value
   # URL: http://<EXTERNAL-IP>
   # or get ARN:
   aws elbv2 describe-load-balancers | grep LoadBalancerArn
   ```

3. **Screenshots**
   - ✅ EKS cluster running (kubectl get nodes)
   - ✅ Pods deployed (kubectl get pods)
   - ✅ LoadBalancer service with external IP (kubectl get svc)
   - ✅ Application running in browser
   - ✅ CodeBuild successful build
   - ✅ CodePipeline execution history
   - ✅ CloudWatch logs

---

## 📞 Support Resources

- **Dockerfile Documentation**: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
- **Kubernetes Manifests**: https://kubernetes.io/docs/concepts/configuration/overview/
- **AWS CodeBuild**: https://docs.aws.amazon.com/codebuild/
- **AWS CodeDeploy**: https://docs.aws.amazon.com/codedeploy/
- **AWS EKS**: https://docs.aws.amazon.com/eks/

---

**Estimated Total Time**: ~1.5 hours (mostly waiting for AWS services to provision)

**Status**: ✅ Ready to Deploy
