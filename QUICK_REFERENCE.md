# Quick Reference Card - AWS Deployment

## 🚀 Start Here: 3-Minute Overview

### What You Need to Do
1. **Read**: DEPLOYMENT_EXECUTION_GUIDE.md
2. **Execute**: 15 deployment steps (60-90 minutes)
3. **Verify**: Test application is accessible
4. **Submit**: LoadBalancer ARN + Screenshots

---

## 📝 Essential Commands

### Set Environment Variables
```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1
export ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
export IMAGE_NAME=brain-tasks-app
export ARTIFACT_BUCKET="brain-tasks-artifacts-$AWS_ACCOUNT_ID"
```

### Verify Everything Works Locally
```bash
# Build and test
npm install
npm run build
docker build -t brain-tasks-app:latest .
docker run -p 3000:80 brain-tasks-app:latest
# Open: http://localhost:3000
```

### Create ECR Repository
```bash
aws ecr create-repository --repository-name $IMAGE_NAME --region $AWS_REGION
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker tag brain-tasks-app:latest $ECR_REGISTRY/$IMAGE_NAME:latest
docker push $ECR_REGISTRY/$IMAGE_NAME:latest
```

### Create & Connect to EKS Cluster
```bash
# Create cluster (15-20 minutes)
aws eks create-cluster \
  --name brain-tasks-cluster \
  --version 1.28 \
  --role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-cluster-role \
  --resources-vpc-config subnetIds=$SUBNET_1,$SUBNET_2 \
  --region $AWS_REGION

# Connect kubectl
aws eks update-kubeconfig --name brain-tasks-cluster --region $AWS_REGION
kubectl cluster-info
```

### Deploy to Kubernetes
```bash
# Update image URI
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|$ECR_REGISTRY|g" k8s-manifests/deployment.yaml

# Deploy
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

# Check status
kubectl get pods
kubectl get svc
```

### Get LoadBalancer URL
```bash
kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
curl http://<LoadBalancer-URL>
```

### Get LoadBalancer ARN
```bash
aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[*].[LoadBalancerArn,DNSName]' --output table
```

---

## 🔍 Monitoring Commands

### Pod Status
```bash
# All pods
kubectl get pods

# Specific app
kubectl get pods -l app=brain-tasks-app

# Pod details
kubectl describe pod <pod-name>

# Pod logs
kubectl logs <pod-name>
kubectl logs -l app=brain-tasks-app --tail=50 -f
```

### Deployment Status
```bash
kubectl get deployment brain-tasks-app
kubectl describe deployment brain-tasks-app
kubectl rollout status deployment brain-tasks-app
```

### Service Status
```bash
kubectl get svc brain-tasks-app-service
kubectl describe svc brain-tasks-app-service
```

### Cluster Health
```bash
kubectl cluster-info
kubectl get nodes
kubectl top nodes
kubectl get events
```

### CloudWatch Logs
```bash
aws logs tail /aws/eks/brain-tasks-app --follow
aws logs tail /aws/codebuild/brain-tasks-build --follow
aws logs tail /aws/codedeploy/brain-tasks-app --follow
```

---

## 🛠️ Troubleshooting Commands

### Why Isn't Pod Running?
```bash
# Check pod status
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Check image
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].image}'
```

### Why Can't I Push to ECR?
```bash
# Re-login
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Check repository
aws ecr list-repositories
aws ecr list-images --repository-name brain-tasks-app
```

### Why Is LoadBalancer Not Working?
```bash
# Check service
kubectl get svc brain-tasks-app-service

# Check pod connectivity
kubectl port-forward svc/brain-tasks-app-service 8080:80
curl localhost:8080

# Check load balancer
aws elbv2 describe-load-balancers
```

### Why Is Deployment Stuck?
```bash
# Check deployment
kubectl describe deployment brain-tasks-app

# Check recent events
kubectl get events --sort-by='.lastTimestamp'

# Check node space
kubectl describe nodes
```

---

## 📊 Resource Cleanup (When Done)

```bash
# Delete Kubernetes resources
kubectl delete svc brain-tasks-app-service
kubectl delete deployment brain-tasks-app

# Delete EKS cluster
aws eks delete-nodegroup --cluster-name brain-tasks-cluster --nodegroup-name brain-tasks-nodegroup
aws eks delete-cluster --name brain-tasks-cluster

# Delete ECR
aws ecr delete-repository --repository-name brain-tasks-app --force

# Delete other resources
aws codepipeline delete-pipeline --name brain-tasks-pipeline
aws codebuild delete-project --name brain-tasks-build
aws deploy delete-app --application-name brain-tasks-app
aws s3 rb s3://$ARTIFACT_BUCKET --force
```

---

## ⏱️ Timing Guide

| Step | Duration | Wait? |
|------|----------|-------|
| Local testing | 5 min | No |
| AWS setup (IAM, VPC) | 15 min | No |
| ECR & Docker | 10 min | No |
| EKS cluster creation | 15-20 min | **Yes** ⏳ |
| Node group creation | 10-15 min | **Yes** ⏳ |
| Kubernetes deployment | 5 min | No |
| CodeBuild/CodeDeploy setup | 10 min | No |
| CodePipeline setup | 5 min | No |
| **Total** | **60-90 min** | |

**Timeline: Most of the time is waiting for AWS to create resources**

---

## 💰 Cost Estimate

```
EKS Cluster:           $10/month
EC2 t3.medium (3):     ~$30/month
Network Load Balancer: ~$16/month
Data Transfer:         ~$5/month
CloudWatch Logs:       ~$5/month
ECR Storage:          <$1/month
Other:                 ~$4/month
───────────────────────────────
TOTAL:               ~$70/month
```

**Note**: Costs can be reduced by using smaller instances or fewer replicas

---

## 🎯 Success Checklist

- [ ] EKS cluster ACTIVE
- [ ] All 3 nodes Ready
- [ ] All 3 pods Running
- [ ] Service has LoadBalancer URL
- [ ] Can access application in browser
- [ ] LoadBalancer ARN saved
- [ ] CloudWatch logs flowing
- [ ] CodePipeline configured
- [ ] Code committed and pushed to GitHub

---

## 📚 Documentation Map

```
START HERE:
├─ DEPLOYMENT_READY.md ..................... Overview & quick start
│
EXECUTION:
├─ DEPLOYMENT_EXECUTION_GUIDE.md ......... Step-by-step commands
│
REFERENCE:
├─ AWS_DEPLOYMENT_STEPS.md ............... Detailed explanations
├─ DEPLOYMENT_ARCHITECTURE.md ............ System diagrams
├─ DEPLOYMENT_DOCUMENTATION_INDEX.md .... Guide to all docs
│
CONFIG FILES:
├─ Dockerfile ............................ Container build
├─ buildspec.yml ......................... CodeBuild config
├─ appspec.yml ........................... CodeDeploy config
├─ k8s-manifests/deployment.yaml ........ Kubernetes deployment
└─ k8s-manifests/service.yaml ........... Kubernetes service
```

---

## 🔗 Quick Links

| Resource | Link |
|----------|------|
| **Start Deployment** | `DEPLOYMENT_EXECUTION_GUIDE.md` |
| **Architecture** | `DEPLOYMENT_ARCHITECTURE.md` |
| **Troubleshooting** | `AWS_DEPLOYMENT_STEPS.md` (bottom) |
| **AWS EKS Docs** | https://docs.aws.amazon.com/eks/ |
| **Kubernetes Docs** | https://kubernetes.io/docs/ |
| **AWS Console** | https://console.aws.amazon.com |

---

## 🆘 Quick Troubleshoot

| Problem | Quick Fix |
|---------|-----------|
| Docker won't build | Run `npm install` first |
| Can't push to ECR | Re-login with `aws ecr get-login-password...` |
| Pod won't start | Check pod logs: `kubectl logs <pod-name>` |
| LoadBalancer not working | Wait 5 min, check service: `kubectl get svc` |
| CodeBuild failing | Check logs: `aws logs tail /aws/codebuild/...` |
| Cluster not creating | Check IAM role permissions |

---

## ✅ Done!

You have **all files, configs, and documentation** needed.

**Next Action**: Open and follow → **DEPLOYMENT_EXECUTION_GUIDE.md**

Good luck! 🚀

---

**Version**: 1.0
**Status**: Ready to Deploy
**Estimated Time**: 60-90 minutes
**Cost**: ~$70/month
