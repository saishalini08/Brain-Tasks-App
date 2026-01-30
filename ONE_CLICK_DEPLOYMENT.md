# 🚀 ONE-CLICK DEPLOYMENT GUIDE

Complete automation scripts to deploy your Brain Tasks React app to AWS with a single command!

---

## ⚡ Quick Start (Choose Your OS)

### **Windows (PowerShell)**

```powershell
# 1. Open PowerShell as Administrator
# 2. Navigate to your project folder
cd C:\Path\To\Brain-Tasks-App

# 3. Run the deployment script
powershell -ExecutionPolicy Bypass -File deploy.ps1
```

### **Mac/Linux (Bash)**

```bash
# 1. Navigate to your project folder
cd /path/to/Brain-Tasks-App

# 2. Make the script executable
chmod +x deploy.sh

# 3. Run the deployment script
./deploy.sh
```

---

## 📋 Pre-Deployment Checklist

Before running the script, ensure you have:

- [ ] **AWS Account** with credentials
- [ ] **AWS CLI** installed (`aws --version`)
- [ ] **Docker** installed and running (`docker --version`)
- [ ] **Git** installed (`git --version`)
- [ ] **kubectl** installed (`kubectl version --client`)
- [ ] **Node.js 16+** installed (`node --version`)
- [ ] **npm** installed (`npm --version`)

**Installation Links:**
- AWS CLI: https://aws.amazon.com/cli/
- Docker: https://www.docker.com/products/docker-desktop
- Git: https://git-scm.com/
- kubectl: https://kubernetes.io/docs/tasks/tools/
- Node.js: https://nodejs.org/

---

## 🔐 Security Setup (One-Time)

### Step 1: Configure AWS Credentials

```bash
aws configure
```

When prompted, enter:
```
AWS Access Key ID [None]: YOUR_ACCESS_KEY_ID
AWS Secret Access Key [None]: YOUR_SECRET_ACCESS_KEY
Default region name [None]: ap-south-1
Default output format [None]: json
```

**Where to get credentials:**
1. Go to: https://console.aws.amazon.com/iam/
2. Click: Users → Your User → Security Credentials
3. Create Access Key
4. Copy the Access Key ID and Secret Access Key

### Step 2: Configure Git

```bash
git config --global user.email "your-email@example.com"
git config --global user.name "Your Name"
```

### Step 3: Create GitHub SSH Key

The script will create this automatically, but you need to:
1. Copy the SSH key from the script output
2. Go to: https://github.com/settings/keys
3. Click: New SSH key
4. Paste the key and save

---

## 🚀 What the Script Does

### Automatically (In Order):

1. ✅ **Verify Prerequisites** - Checks AWS CLI, Docker, Git, kubectl
2. ✅ **GitHub SSH Setup** - Creates SSH key and configures GitHub
3. ✅ **Git Configuration** - Sets up user name and email
4. ✅ **Commit & Push** - Commits all files and pushes to GitHub
5. ✅ **AWS Configuration** - Verifies AWS credentials
6. ✅ **Create IAM Roles** - Sets up service roles (5 roles)
7. ✅ **Create VPC** - Sets up networking (VPC + Subnets)
8. ✅ **Create ECR** - Creates container registry
9. ✅ **Build Docker Image** - Builds and pushes to ECR
10. ✅ **Create EKS Cluster** - Creates Kubernetes cluster (15-20 min)
11. ✅ **Create Node Group** - Adds 3 compute nodes (10-15 min)
12. ✅ **Create Secrets** - ImagePullSecret for ECR
13. ✅ **Deploy App** - Deploys to Kubernetes
14. ✅ **Get LoadBalancer URL** - Gets your application URL
15. ✅ **Verify Deployment** - Tests that everything works

---

## ⏱️ Timeline

```
Total Time: ~90 minutes

Breakdown:
  • Setup & verification:     5 min
  • Git & GitHub:            10 min
  • AWS setup:               15 min
  • Docker build & push:     10 min
  • EKS cluster creation:    15-20 min ⏳ (waiting)
  • Node group creation:     10-15 min ⏳ (waiting)
  • Kubernetes deployment:    5 min
  • LoadBalancer setup:      5-10 min ⏳ (waiting)
  • Verification:            5 min

Most time is spent waiting for AWS to create resources.
You can monitor progress in the AWS Console.
```

---

## 📊 Expected Output

When the script completes, you'll see:

```
========================================
🎉 DEPLOYMENT COMPLETE!
========================================

Your application is now live!

📊 DEPLOYMENT INFORMATION:
AWS Account ID:     123456789012
AWS Region:         ap-south-1
EKS Cluster:        brain-tasks-cluster

🌐 APPLICATION URL:
http://brain-tasks-app-service-123456789.ap-south-1.elb.amazonaws.com

📋 USEFUL COMMANDS:
View pods:          kubectl get pods
View logs:          kubectl logs -l app=brain-tasks-app -f
View service:       kubectl get svc brain-tasks-app-service
View nodes:         kubectl get nodes
Scale replicas:     kubectl scale deployment brain-tasks-app --replicas=5

✅ Deployment info saved to: DEPLOYMENT_INFO.txt
✅ All deployment steps completed successfully!
```

---

## 🌐 Access Your Application

After deployment, your application is accessible at:

**Example URL:**
```
http://brain-tasks-app-service-abc123def456.ap-south-1.elb.amazonaws.com
```

The exact URL will be shown at the end of the script output and saved in `DEPLOYMENT_INFO.txt`.

**Note:** It takes 5-10 minutes for the LoadBalancer to become fully functional after creation.

---

## 🛠️ Troubleshooting

### Script Fails at "Prerequisites"

**Solution:**
```bash
# Check if tools are installed
git --version
aws --version
docker --version
kubectl version --client
node --version
npm --version

# Install missing tools from links above
```

### "AWS credentials not configured"

**Solution:**
```bash
aws configure
# Enter your credentials when prompted
```

### "SSH connection failed"

**Solution:**
1. Generate SSH key:
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
   ```
2. Add to GitHub:
   - Go to: https://github.com/settings/keys
   - Click: New SSH key
   - Paste your public key from: `cat ~/.ssh/id_rsa.pub`

### "Docker build failed"

**Solution:**
```bash
# Make sure Docker is running
docker ps

# If that fails, restart Docker Desktop and try again
```

### "EKS cluster creation timeout"

**Solution:**
1. Wait longer (it can take 20-30 minutes)
2. Check AWS Console: https://console.aws.amazon.com/eks/
3. View logs for specific errors

### "LoadBalancer URL not appearing"

**Solution:**
1. Wait 5-10 minutes after deployment
2. Check service status:
   ```bash
   kubectl get svc brain-tasks-app-service
   ```
3. If still no URL, check pod logs:
   ```bash
   kubectl logs -l app=brain-tasks-app
   ```

---

## 📁 Files Created

After running the script, you'll have:

```
Brain-Tasks-App/
├── deploy.sh                    (This script - Mac/Linux)
├── deploy.ps1                   (This script - Windows)
├── DEPLOYMENT_INFO.txt          (Your deployment info)
├── k8s-manifests/
│   ├── deployment.yaml          (Updated with ECR image)
│   └── service.yaml
├── Dockerfile
├── buildspec.yml
├── appspec.yml
└── ... (other files)
```

---

## 💰 Cost Information

```
EKS Cluster          $10/month
EC2 Nodes (3)        ~$30/month
Load Balancer        ~$16/month
Data Transfer        ~$5/month
CloudWatch/Logs      ~$5/month
Other                ~$4/month
───────────────────────────────
TOTAL               ~$70/month

Ways to reduce:
• Use t3.small instead of t3.medium (-$10/month)
• Use 2 replicas instead of 3 (-$10/month)
• Delete after testing (saves all costs)
```

---

## 🧹 Cleanup (Delete Resources)

When you're done testing and want to remove all resources:

```bash
# Delete Kubernetes resources
kubectl delete svc brain-tasks-app-service
kubectl delete deployment brain-tasks-app

# Delete EKS cluster
aws eks delete-nodegroup --cluster-name brain-tasks-cluster --nodegroup-name brain-tasks-nodegroup --region ap-south-1
aws eks delete-cluster --name brain-tasks-cluster --region ap-south-1

# Delete ECR repository
aws ecr delete-repository --repository-name brain-tasks-app --force --region ap-south-1

# Delete VPC (if created by script)
# Note: This is more complex, use AWS Console

# Delete IAM roles
# Note: Delete from AWS Console
```

---

## 📞 Support

### If Something Goes Wrong:

1. **Check the output** - Scripts show detailed error messages
2. **Check AWS Console** - https://console.aws.amazon.com
3. **Check logs**:
   ```bash
   kubectl logs -l app=brain-tasks-app -f
   aws logs tail /aws/eks/brain-tasks-app --follow
   ```
4. **Read the detailed guides**:
   - DEPLOYMENT_EXECUTION_GUIDE.md
   - AWS_DEPLOYMENT_STEPS.md

---

## 📋 Customization

### Change AWS Region

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -AwsRegion "us-east-1"
```

**Mac/Linux (Bash):**
```bash
export AWS_REGION="us-east-1"
./deploy.sh
```

### Change Git Email/Name

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -GitEmail "your@email.com" -GitName "Your Name"
```

---

## ✅ Success Criteria

Your deployment is successful when:

- [x] Script completes without errors
- [x] Application URL is displayed
- [x] Can access application in browser
- [x] `DEPLOYMENT_INFO.txt` is created
- [x] `kubectl get pods` shows 3 running pods
- [x] CloudWatch logs are flowing

---

## 🎉 Next Steps

After successful deployment:

1. ✅ Access your application at the provided URL
2. ✅ Test that it works correctly
3. ✅ Save the LoadBalancer URL (you'll need it)
4. ✅ Review CloudWatch logs
5. ✅ Monitor costs in AWS Console
6. ✅ Set up alarms (optional)
7. ✅ Plan cleanup when done testing

---

## 📚 Additional Resources

- **AWS EKS Docs**: https://docs.aws.amazon.com/eks/
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **AWS CLI Docs**: https://docs.aws.amazon.com/cli/
- **Docker Docs**: https://docs.docker.com/

---

## 🔒 Security Notes

1. **Never commit AWS credentials** - Use `aws configure` locally
2. **Rotate SSH keys periodically** - GitHub settings
3. **Use IAM roles for production** - Don't use root account
4. **Monitor costs** - Set up AWS budget alerts
5. **Delete test resources** - Don't leave running if not using

---

## 💡 Pro Tips

1. **Keep terminal open** - You can monitor progress
2. **Bookmark your URLs** - Save for easy access
3. **Take screenshots** - Useful for documentation
4. **Check AWS Console** - See real-time progress
5. **Scale easily** - Adjust replicas with one command:
   ```bash
   kubectl scale deployment brain-tasks-app --replicas=5
   ```

---

**Ready to deploy?**

Choose your OS and run the script:
- **Windows**: `powershell -ExecutionPolicy Bypass -File deploy.ps1`
- **Mac/Linux**: `chmod +x deploy.sh && ./deploy.sh`

Your application will be live in ~90 minutes! 🚀

---

**Generated**: 2024
**Version**: 1.0
**Status**: Production Ready
