# Brain Tasks App - Deployment Documentation Index

This document explains all deployment-related files and how to use them.

## 📚 Documentation Files

### 1. **START_HERE.md**
   - Overview of the project and all documentation
   - Start with this file first

### 2. **DEPLOYMENT_EXECUTION_GUIDE.md** ⭐ **START HERE FOR ACTUAL DEPLOYMENT**
   - Step-by-step commands to deploy the application
   - Copy-paste ready commands with explanations
   - Expected time: 60-90 minutes for complete deployment
   - Includes verification checklist

### 3. **AWS_DEPLOYMENT_STEPS.md**
   - Detailed explanations of each deployment step
   - Why each step is needed
   - Troubleshooting guide for common issues
   - Reference documentation for all AWS services

### 4. **AWS_SETUP_GUIDE.md**
   - Initial AWS account setup
   - IAM configuration
   - Prerequisites for deployment

### 5. **DEPLOYMENT_QUICKSTART.md**
   - Quick reference guide
   - High-level overview
   - Links to detailed guides

### 6. **DEPLOYMENT_SUMMARY.md**
   - What has been configured
   - What still needs to be done manually
   - Resource checklist

### 7. **IMPLEMENTATION_GUIDE.md**
   - Technical implementation details
   - Architecture decisions
   - Code structure

### 8. **COMMANDS_REFERENCE.md**
   - Common commands used in deployment
   - One-line reference guide
   - Useful utilities

### 9. **WHICH_FILE_TO_READ.md**
   - Helps you choose which guide to read
   - Based on your situation

---

## 🚀 How to Deploy - Quick Reference

### For First-Time Deployment:

1. **Read**: `START_HERE.md` (5 minutes)
2. **Follow**: `DEPLOYMENT_EXECUTION_GUIDE.md` (60-90 minutes)
3. **Reference**: `AWS_DEPLOYMENT_STEPS.md` (as needed for details)

### For CI/CD Integration:

1. Read: `IMPLEMENTATION_GUIDE.md`
2. Configure: CodePipeline from AWS Console
3. Reference: `buildspec.yml` and `appspec.yml` in this repo

### For Troubleshooting:

1. Check: `AWS_DEPLOYMENT_STEPS.md` Troubleshooting section
2. Verify: Resources in AWS Console
3. Logs: CloudWatch Logs

---

## 📁 Configuration Files

### **Dockerfile**
```dockerfile
# Multi-stage build for React application
# Base: nginx:alpine
# Port: 80 (exposed, mapped to 3000 on host)
# Purpose: Containerize the React app for deployment
```

**To test locally:**
```bash
docker build -t brain-tasks-app:latest .
docker run -p 3000:80 brain-tasks-app:latest
# Open http://localhost:3000
```

---

### **buildspec.yml**
```yaml
# AWS CodeBuild configuration
# Stages:
#   1. pre_build: Login to ECR
#   2. build: Install deps, build app, build Docker image
#   3. post_build: Push to ECR
# 
# Output: imagedefinitions.json for CodeDeploy
```

**Purpose**: Automates building Docker image and pushing to AWS ECR

**Triggered by**: CodePipeline when code is pushed to GitHub

---

### **appspec.yml**
```yaml
# AWS CodeDeploy configuration for EKS
# Defines how to deploy to Kubernetes
# Hooks for pre/post deployment validation
```

**Purpose**: Tells CodeDeploy how to deploy to EKS cluster

**Updated**: Now includes EKS-specific configuration

---

### **k8s-manifests/deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: brain-tasks-app

# Configuration:
# - Replicas: 3 (for high availability)
# - Image: From ECR (needs AWS_ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app:latest)
# - Port: 80 (exposed by nginx)
# - Resources: Limits set for production
# - Health checks: Liveness & Readiness probes configured
# - Scheduling: Pod anti-affinity for spread across nodes
```

**To deploy:**
```bash
# First update the image URI with your AWS account info:
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|YOUR_ECR_REGISTRY|g" k8s-manifests/deployment.yaml

# Then apply:
kubectl apply -f k8s-manifests/deployment.yaml
```

---

### **k8s-manifests/service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: brain-tasks-app-service

# Configuration:
# - Type: LoadBalancer (exposes publicly)
# - Port: 80 (public)
# - TargetPort: 80 (pod port)
# - Selector: app=brain-tasks-app (routes to deployment pods)
```

**Provides**: Public URL to access the application

**Example**: `brain-tasks-app-service-1234567890.us-east-1.elb.amazonaws.com`

---

## 🔄 Deployment Architecture

```
GitHub Repository
    ↓
    ├─→ CodePipeline triggered on push
    │
    ├─→ Stage 1: Source
    │   └─→ Pull code from GitHub
    │
    ├─→ Stage 2: Build
    │   └─→ CodeBuild Project (buildspec.yml)
    │       ├─ Install dependencies
    │       ├─ Build React app (npm run build)
    │       ├─ Build Docker image
    │       └─ Push to ECR
    │
    └─→ Stage 3: Deploy
        └─→ CodeDeploy (appspec.yml)
            └─→ Deploy to EKS Cluster
                └─→ kubectl apply k8s-manifests
                    ├─ deployment.yaml (create/update pods)
                    └─ service.yaml (expose LoadBalancer)

EKS Cluster (Kubernetes)
    ├─ Deployment (brain-tasks-app)
    │   └─ 3 Pods (running nginx with your app)
    │
    └─ Service (LoadBalancer)
        └─ AWS Network Load Balancer
            └─ Public URL to access app
```

---

## 📊 Resource Costs (Approximate Monthly)

| Resource | Cost | Notes |
|----------|------|-------|
| EKS Cluster | $10 | Per cluster |
| EC2 t3.medium (3) | ~$30 | Per node/month (3 nodes) |
| Network Load Balancer | $16 | Per LB |
| Data Transfer | ~$5 | Outbound |
| ECR Storage | <$1 | Image storage |
| CloudWatch | ~$5 | Logs & monitoring |
| **Total** | **~$70/month** | Starting point |

---

## ✅ Deployment Checklist

### Before Starting:
- [ ] AWS Account with IAM permissions
- [ ] AWS CLI configured (`aws configure`)
- [ ] kubectl installed
- [ ] Docker installed
- [ ] Node.js 16+ installed
- [ ] GitHub account (for repository access)

### During Deployment:
- [ ] Follow DEPLOYMENT_EXECUTION_GUIDE.md step by step
- [ ] Note down all ARNs and IDs
- [ ] Test each step before moving to next

### After Deployment:
- [ ] Verify application is accessible via LoadBalancer URL
- [ ] Check all pods are Running
- [ ] Review CloudWatch logs for errors
- [ ] Test application functionality
- [ ] Save LoadBalancer ARN for submission

---

## 🆘 Common Issues & Solutions

### Issue: Docker image won't build
**Solution**: 
```bash
npm install
npm run build
# Verify dist/ folder exists
```

### Issue: Can't push to ECR
**Solution**:
```bash
# Re-login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

### Issue: Pods not starting
**Solution**:
```bash
# Check pod logs
kubectl logs <pod-name>

# Check events
kubectl describe pod <pod-name>

# Common cause: Image URI incorrect in deployment.yaml
```

### Issue: LoadBalancer URL not working
**Solution**:
```bash
# Wait 5 minutes for LB to be ready
# Check service status
kubectl get svc brain-tasks-app-service

# Check pod connectivity
kubectl port-forward <pod-name> 8080:80
curl localhost:8080
```

### Issue: CodeBuild failing
**Solution**:
```bash
# Check CodeBuild role has ECR permissions
# Review build logs in CloudWatch
aws logs tail /aws/codebuild/brain-tasks-build --follow
```

---

## 📋 Deployment Validation Script

Save this as `validate-deployment.sh` and run it to verify everything is working:

```bash
#!/bin/bash

echo "=== Deployment Validation Check ==="

# Check EKS Cluster
echo "1. EKS Cluster Status:"
aws eks describe-cluster --name brain-tasks-cluster --region $AWS_REGION --query 'cluster.status'

# Check Nodes
echo "2. Kubernetes Nodes:"
kubectl get nodes
READY_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
echo "Ready Nodes: $READY_NODES"

# Check Pods
echo "3. Application Pods:"
kubectl get pods -l app=brain-tasks-app
RUNNING_PODS=$(kubectl get pods -l app=brain-tasks-app -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
echo "Running Pods: $RUNNING_PODS"

# Check Service
echo "4. LoadBalancer Service:"
kubectl get svc brain-tasks-app-service
LB_URL=$(kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LoadBalancer URL: http://$LB_URL"

# Test Application
if [ ! -z "$LB_URL" ]; then
  echo "5. Application Test:"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$LB_URL)
  echo "HTTP Status: $HTTP_CODE"
  if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Application is accessible!"
  else
    echo "⚠️ Application returned $HTTP_CODE"
  fi
fi

# Check ECR
echo "6. ECR Images:"
aws ecr list-images --repository-name brain-tasks-app --region $AWS_REGION

# Summary
echo ""
echo "=== Summary ==="
if [ "$READY_NODES" -ge "2" ] && [ "$RUNNING_PODS" = "3" ] && [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Deployment appears successful!"
else
  echo "⚠️ Some issues detected - check above"
fi
```

---

## 📞 Getting Help

1. **For Setup Issues**: See AWS_SETUP_GUIDE.md
2. **For Deployment Issues**: See DEPLOYMENT_EXECUTION_GUIDE.md
3. **For Details**: See AWS_DEPLOYMENT_STEPS.md
4. **For Quick Reference**: See COMMANDS_REFERENCE.md
5. **For Code Issues**: Check buildspec.yml or Dockerfile

---

## 🎓 Learning Resources

- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [AWS CodePipeline](https://docs.aws.amazon.com/codepipeline/)
- [AWS CodeBuild](https://docs.aws.amazon.com/codebuild/)

---

## 📝 Submission Checklist

When you're ready to submit, ensure you have:

1. ✅ GitHub repository with code (URL: https://github.com/Vennilavan12/Brain-Tasks-App)
2. ✅ README.md with setup instructions (this file)
3. ✅ Dockerfile (for containerization)
4. ✅ buildspec.yml (for CodeBuild)
5. ✅ appspec.yml (for CodeDeploy)
6. ✅ k8s-manifests/ (deployment.yaml, service.yaml)
7. ✅ Application accessible via LoadBalancer URL
8. ✅ LoadBalancer ARN saved
9. ✅ CloudWatch logs configured
10. ✅ CodePipeline setup (automated CI/CD)
11. ✅ Screenshots of:
    - EKS Cluster running
    - Nodes in Ready state
    - Pods in Running state
    - LoadBalancer service with URL
    - Application accessible in browser
    - CodePipeline pipeline stages
    - CloudWatch logs

---

**Last Updated**: 2024
**Status**: Production Ready
**Application**: Brain Tasks React App
**Deployment Target**: AWS EKS with CI/CD Pipeline
