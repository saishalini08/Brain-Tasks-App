# 🚀 DEPLOY IN ONE CLICK

**Your application can now be deployed with a single command!**

---

## Quick Start (30 seconds)

### **Windows Users:**
```powershell
# Open PowerShell as Administrator and run:
powershell -ExecutionPolicy Bypass -File deploy.ps1
```

### **Mac/Linux Users:**
```bash
# In terminal, run:
chmod +x deploy.sh && ./deploy.sh
```

**That's it! Your app will be deployed in ~90 minutes.**

---

## What Happens Automatically

✅ GitHub SSH setup & commit
✅ AWS IAM roles creation
✅ VPC & networking setup
✅ Docker image build & push to ECR
✅ EKS cluster creation
✅ Kubernetes deployment
✅ LoadBalancer setup
✅ Application URL provided

---

## Prerequisites (One-Time Setup)

Before running the script, install these tools:

| Tool | Command |
|------|---------|
| **AWS CLI** | [Download](https://aws.amazon.com/cli/) |
| **Docker** | [Download](https://www.docker.com/products/docker-desktop) |
| **Git** | [Download](https://git-scm.com/) |
| **kubectl** | [Install](https://kubernetes.io/docs/tasks/tools/) |
| **Node.js** | [Download](https://nodejs.org/) |

Verify installation:
```bash
aws --version
docker --version
git --version
kubectl version --client
node --version
```

---

## Configure AWS (One-Time)

```bash
aws configure
```

Enter your AWS credentials:
- **Access Key ID**: From AWS Console
- **Secret Access Key**: From AWS Console
- **Region**: `ap-south-1`
- **Output Format**: `json`

**Get credentials from:** https://console.aws.amazon.com/iam/

---

## Run the Deployment

### **Windows:**
```powershell
cd C:\Path\To\Brain-Tasks-App
powershell -ExecutionPolicy Bypass -File deploy.ps1
```

### **Mac/Linux:**
```bash
cd /path/to/Brain-Tasks-App
chmod +x deploy.sh
./deploy.sh
```

### **What to expect:**
```
✅ Checking prerequisites...
✅ Setting up GitHub SSH...
✅ Committing files...
✅ Creating AWS resources...
✅ Building Docker image...
✅ Creating EKS cluster... (⏳ 15-20 minutes)
✅ Deploying to Kubernetes...
✅ Getting application URL...

🎉 DEPLOYMENT COMPLETE!
Your application is at: http://your-load-balancer-url
```

---

## Your Application URL

The script will display something like:

```
🌐 APPLICATION URL:
http://brain-tasks-app-service-abc123.ap-south-1.elb.amazonaws.com
```

**Copy this URL and open it in your browser!**

---

## Timeline

| Step | Time |
|------|------|
| Prerequisites check | 1 min |
| Git & GitHub setup | 10 min |
| AWS setup | 10 min |
| Docker build & push | 10 min |
| EKS cluster creation | 15-20 min ⏳ |
| Node group creation | 10-15 min ⏳ |
| Kubernetes deployment | 5 min |
| LoadBalancer setup | 5-10 min ⏳ |
| **TOTAL** | **~90 min** |

Most of the time is waiting for AWS to create resources (shown as ⏳).

---

## Troubleshooting

### Script fails at start
```bash
# Verify all tools are installed
aws --version && docker --version && git --version && kubectl version --client
```

### "AWS credentials not found"
```bash
aws configure
# Then run the script again
```

### "Docker not running"
- Start Docker Desktop
- Wait for it to fully load
- Run the script again

### "Script takes too long"
- This is normal! EKS cluster creation takes 15-20 minutes
- Monitor progress in [AWS Console](https://console.aws.amazon.com)
- Don't close the terminal

---

## After Deployment

1. **Open your application URL** in a browser
2. **Verify it's working** - You should see your React app
3. **Save the URL** - You'll need it later
4. **Check the logs**:
   ```bash
   kubectl logs -l app=brain-tasks-app -f
   ```
5. **Get deployment info**:
   ```bash
   cat DEPLOYMENT_INFO.txt
   ```

---

## Useful Commands

```bash
# View your running pods
kubectl get pods

# View application logs
kubectl logs -l app=brain-tasks-app -f

# View service details
kubectl get svc brain-tasks-app-service

# View all nodes
kubectl get nodes

# Scale to 5 replicas
kubectl scale deployment brain-tasks-app --replicas=5

# Access pod directly
kubectl port-forward svc/brain-tasks-app-service 8080:80
# Then open: http://localhost:8080
```

---

## Cost

```
🔻 Per Month:
EKS Cluster              $10
EC2 Nodes (3)            ~$30
Load Balancer            ~$16
Data Transfer            ~$5
CloudWatch Logs          ~$5
Other Services           ~$4
───────────────────────────────
TOTAL                   ~$70
```

This is for testing/demo. You can reduce costs by:
- Using smaller instances (save ~$10)
- Using fewer replicas (save ~$10)
- Deleting resources when not in use

---

## Need Help?

| Problem | Solution |
|---------|----------|
| Script won't start | Install prerequisites |
| AWS errors | Run `aws configure` |
| Docker errors | Restart Docker Desktop |
| Long wait times | This is normal - EKS takes time |
| URL not accessible | Wait 5 more minutes |

**Read the detailed guides:**
- `ONE_CLICK_DEPLOYMENT.md` - Full guide
- `DEPLOYMENT_EXECUTION_GUIDE.md` - Step-by-step
- `AWS_DEPLOYMENT_STEPS.md` - Troubleshooting

---

## Security Reminder

⚠️ **IMPORTANT:**
- ✅ Never share your AWS credentials
- ✅ Use `aws configure` only on your computer
- ✅ Don't commit credentials to Git
- ✅ Rotate keys periodically
- ✅ Delete resources when done testing

---

**Ready?**

👉 Run the script now and come back in ~90 minutes for your live application URL!

```bash
# Windows
powershell -ExecutionPolicy Bypass -File deploy.ps1

# Mac/Linux
./deploy.sh
```

🚀 Let's go!

---

**Questions?** Check `ONE_CLICK_DEPLOYMENT.md` for detailed instructions.
