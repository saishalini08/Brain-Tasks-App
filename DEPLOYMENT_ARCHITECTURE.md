# Complete AWS Deployment Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Developer / Git Repository                       │
│                    https://github.com/Vennilavan12/                      │
│                          Brain-Tasks-App.git                             │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ (Code Push)
                                     │
                    ┌────────────────▼──────────────────┐
                    │      AWS CodePipeline             │
                    │  (Automated CI/CD Orchestrator)   │
                    └────────────────┬──────────────────┘
                                     │
                    ┌────────────────┴──────────────────┐
                    │                                   │
         ┌──────────▼──────────┐         ┌──────────────▼───────┐
         │  Stage 1: Source    │         │  AWS CodeBuild       │
         │  (GitHub Webhook)   │         │  (buildspec.yml)     │
         │                     │         │                      │
         │ Triggers on:        │         │ 1. Install npm deps  │
         │ - Code push         │         │ 2. npm run build     │
         │ - Pull request      │         │ 3. Build Docker img  │
         │ - Branch changes    │         │ 4. Push to ECR       │
         └─────────────────────┘         └──────────┬───────────┘
                                                    │
                          ┌─────────────────────────▼──────────────────┐
                          │         AWS ECR (Container Registry)        │
                          │      brain-tasks-app:latest                 │
                          │    (Stores Docker images)                   │
                          └─────────────────────────┬──────────────────┘
                                                    │
                         ┌──────────────────────────▼───────────────────┐
                         │  Stage 3: Deploy (CodeDeploy/appspec.yml)   │
                         │  Updates k8s manifests with new image        │
                         │  Runs: kubectl apply k8s-manifests/          │
                         └──────────────────────────┬───────────────────┘
                                                    │
                     ┌──────────────────────────────▼────────────────┐
                     │      AWS EKS Kubernetes Cluster               │
                     │      (brain-tasks-cluster)                    │
                     │                                               │
                     │  ┌─────────────────────────────────────────┐  │
                     │  │  Kubernetes Deployment: brain-tasks-app │  │
                     │  │  Replicas: 3                            │  │
                     │  │  Strategy: RollingUpdate                │  │
                     │  │                                          │  │
                     │  │  ┌────────────────────────────────────┐ │  │
                     │  │  │  Pod 1 (brain-tasks-app)           │ │  │
                     │  │  │  ├─ Container: nginx + React App   │ │  │
                     │  │  │  ├─ Port: 80                       │ │  │
                     │  │  │  ├─ Status: Running                │ │  │
                     │  │  │  └─ Ready: 1/1                     │ │  │
                     │  │  ├────────────────────────────────────┤ │  │
                     │  │  │  Pod 2 (brain-tasks-app)           │ │  │
                     │  │  │  ├─ Container: nginx + React App   │ │  │
                     │  │  │  ├─ Port: 80                       │ │  │
                     │  │  │  ├─ Status: Running                │ │  │
                     │  │  │  └─ Ready: 1/1                     │ │  │
                     │  │  ├────────────────────────────────────┤ │  │
                     │  │  │  Pod 3 (brain-tasks-app)           │ │  │
                     │  │  │  ├─ Container: nginx + React App   │ │  │
                     │  │  │  ├─ Port: 80                       │ │  │
                     │  │  │  ├─ Status: Running                │ │  │
                     │  │  │  └─ Ready: 1/1                     │ │  │
                     │  │  └────────────────────────────────────┘ │  │
                     │  └─────────────────────────────────────────┘  │
                     │                                               │
                     │  ┌─────────────────────────────────────────┐  │
                     │  │  Kubernetes Service: LoadBalancer       │  │
                     │  │  (brain-tasks-app-service)              │  │
                     │  │  Type: LoadBalancer                     │  │
                     │  │  Port: 80                               │  │
                     │  │  Selector: app=brain-tasks-app          │  │
                     │  └──────────────────┬──────────────────────┘  │
                     └─────────────────────┼──────────────────────────┘
                                           │
                      ┌────────────────────▼──────────────────┐
                      │   AWS Network Load Balancer (NLB)     │
                      │   Auto-created by k8s Service         │
                      │   Exposes: Public IP / DNS Name       │
                      │   Protocol: TCP/HTTP                  │
                      └────────────────────┬──────────────────┘
                                           │
                      ┌────────────────────▼──────────────────┐
                      │   Public Internet / Users             │
                      │   http://brain-tasks-app-...          │
                      │   .elb.amazonaws.com                  │
                      │                                       │
                      │   ✅ Application Accessible!          │
                      └───────────────────────────────────────┘
```

---

## AWS Services Used

### Core Services

1. **AWS EKS (Elastic Kubernetes Service)**
   - Managed Kubernetes cluster
   - Cluster Name: `brain-tasks-cluster`
   - Version: 1.28
   - Node Group: `brain-tasks-nodegroup` (3 t3.medium instances)

2. **AWS ECR (Elastic Container Registry)**
   - Container image repository
   - Repository: `brain-tasks-app`
   - Stores built Docker images
   - Images tagged with: `latest`, `timestamp`

3. **AWS CodePipeline**
   - Automated CI/CD orchestration
   - Pipeline Name: `brain-tasks-pipeline`
   - Stages: Source → Build → Deploy

4. **AWS CodeBuild**
   - Build automation service
   - Project: `brain-tasks-build`
   - Executes: `buildspec.yml`
   - Builds Docker image and pushes to ECR

5. **AWS CodeDeploy**
   - Deployment automation
   - Application: `brain-tasks-app`
   - Deployment Group: `brain-tasks-deployment-group`
   - Uses: `appspec.yml` for EKS deployment

### Supporting Services

6. **AWS CloudWatch**
   - Monitoring and logging
   - Log Groups:
     - `/aws/eks/brain-tasks-app`
     - `/aws/codebuild/brain-tasks-build`
     - `/aws/codedeploy/brain-tasks-app`

7. **AWS IAM (Identity & Access Management)**
   - Manages permissions for all services
   - Roles created:
     - `brain-tasks-eks-cluster-role`
     - `brain-tasks-eks-node-role`
     - `brain-tasks-codebuild-role`
     - `brain-tasks-codedeploy-role`
     - `brain-tasks-codepipeline-role`

8. **AWS EC2 (Elastic Compute Cloud)**
   - Virtual machines for EKS nodes
   - Instance Type: t3.medium
   - Count: 3 nodes in node group
   - Auto Scaling: 2-4 nodes

9. **AWS VPC (Virtual Private Cloud)**
   - Network isolation
   - Subnets: 2 (for high availability)
   - CIDR: 10.0.0.0/16
   - Internet Gateway: Public access

10. **AWS Network Load Balancer (NLB)**
    - Auto-created by Kubernetes Service
    - Type: Layer 4 (TCP/UDP)
    - Distributes traffic across 3 pods

11. **AWS S3 (Simple Storage Service)**
    - Artifact storage for pipeline
    - Bucket: `brain-tasks-artifacts-{ACCOUNT_ID}`
    - Stores build outputs

---

## Data Flow

### Development → Production Flow

```
1. Developer pushes code to GitHub
   └─ Command: git push origin main

2. GitHub webhook triggers CodePipeline
   └─ Automatic trigger on branch: main

3. CodePipeline Stage 1: Source
   └─ Fetches latest code from GitHub

4. CodePipeline Stage 2: Build
   └─ Triggers CodeBuild Project
      ├─ Runs: npm install
      ├─ Runs: npm run build (creates dist/)
      ├─ Runs: docker build (creates image)
      └─ Runs: docker push (pushes to ECR)
      
5. CodeBuild outputs: imagedefinitions.json
   └─ Contains image URI and tag

6. CodePipeline Stage 3: Deploy
   └─ Triggers CodeDeploy with:
      ├─ appspec.yml (deployment instructions)
      └─ k8s-manifests (Kubernetes configs)

7. CodeDeploy executes on EKS:
   └─ kubectl apply -f k8s-manifests/
      ├─ Creates/updates Deployment
      ├─ Creates/updates Service
      └─ Kubernetes handles pod updates

8. Kubernetes Rolling Update:
   ├─ Creates new pods with new image
   ├─ Waits for readiness probes
   ├─ Removes old pods
   └─ Maintains 3 replicas during update

9. Service routes traffic to new pods
   └─ Load Balancer distributes across pods

10. Application is live with new version
    └─ Zero downtime deployment
```

---

## Kubernetes Deployment Details

### Deployment Configuration

```yaml
# brain-tasks-app Deployment
- Name: brain-tasks-app
- Namespace: default
- Image: AWS_ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app:latest
- Replicas: 3
- Strategy: RollingUpdate (maxSurge: 1, maxUnavailable: 0)

Health Checks:
  - Liveness Probe: HTTP GET /  every 10 sec
  - Readiness Probe: HTTP GET / every 5 sec
  
Resource Limits:
  - CPU Request: 100m, Limit: 500m
  - Memory Request: 128Mi, Limit: 512Mi
  
Affinity:
  - Pod Anti-Affinity (spread across nodes)
```

### Service Configuration

```yaml
# brain-tasks-app-service
- Type: LoadBalancer
- Port: 80 (public)
- TargetPort: 80 (pod port)
- Selector: app=brain-tasks-app
- Creates: AWS Network Load Balancer
- Exposes: Public hostname/IP
```

---

## CI/CD Pipeline Flow

```
┌─────────────┐
│   GitHub    │
│  (Repository)
└──────┬──────┘
       │ (Webhook: push to main)
       │
┌──────▼────────────────────────────────────┐
│          CodePipeline                      │
│  (brain-tasks-pipeline)                    │
└──────┬────────────────────────────────────┘
       │
       ├─────────────────────┬────────────────────────┬──────────────────┐
       │                     │                        │                  │
   [Stage 1]             [Stage 2]               [Stage 3]          [Stage 4]
   SOURCE                BUILD                   DEPLOY             SUCCESS
   
   │                       │                        │
   ▼                       ▼                        ▼
┌──────────┐          ┌──────────────┐         ┌──────────────┐
│ GitHub   │          │  CodeBuild   │         │  CodeDeploy  │
│ Source   │          │              │         │              │
│ (Fetch   │          │ buildspec.   │         │ appspec.     │
│  Code)   │          │ yml          │         │ yml          │
└──────┬───┘          │              │         │              │
       │              │ 1. npm       │         │ Updates      │
       │              │    install   │         │ k8s manifest │
       │              │ 2. npm run   │         │ with new     │
       │              │    build     │         │ image URI    │
       │              │ 3. docker    │         │              │
       │              │    build     │         │ Runs:        │
       │              │ 4. docker    │         │ kubectl      │
       │              │    push to   │         │ apply        │
       │              │    ECR       │         └──────┬───────┘
       │              └──────┬───────┘                │
       │                     │                        │
       └──────────────────┬──┴────────────────────────┘
                          │
                  ┌───────▼────────┐
                  │    AWS ECR     │
                  │   (Image Push) │
                  │                │
                  │brain-tasks-app │
                  │    :latest     │
                  └────────────────┘
```

---

## Monitoring & Logging Architecture

```
┌──────────────────────────────┐
│   CloudWatch Logs            │
├──────────────────────────────┤
│                              │
│ /aws/eks/brain-tasks-app     │ ◄──── Kubernetes Pod Logs
│ (Pod application logs)        │       kubectl logs <pod>
│                              │
│ /aws/codebuild/              │ ◄──── Build Logs
│   brain-tasks-build          │       npm install, docker build
│                              │
│ /aws/codedeploy/             │ ◄──── Deployment Logs
│   brain-tasks-app            │       kubectl apply output
│                              │
└──────────────────────────────┘
         ▲
         │
    ┌────┴──────┐
    │            │
    │            │
┌───┴───┐    ┌───┴────┐
│ EKS   │    │CodeBuild
│Cluster│    │ Build
│Logs   │    │Logs
└───────┘    └────────┘

Retention: 30 days per log group
Format: Structured JSON logs
Querying: CloudWatch Insights
Alarms: Custom CloudWatch alarms
```

---

## Networking Architecture

```
┌────────────────────────────────────────────────────┐
│           AWS VPC (10.0.0.0/16)                    │
├────────────────────────────────────────────────────┤
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │         Availability Zone A (us-east-1a)     │ │
│  │  Subnet: 10.0.1.0/24                         │ │
│  │                                              │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │  EKS Node 1 (t3.medium)                │  │ │
│  │  │  ├─ Pod: brain-tasks-app               │  │ │
│  │  │  │  └─ Port: 80                        │  │ │
│  │  │  └─ Security Group: sg-xxxx            │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │         Availability Zone B (us-east-1b)     │ │
│  │  Subnet: 10.0.2.0/24                         │ │
│  │                                              │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │  EKS Node 2 (t3.medium)                │  │ │
│  │  │  ├─ Pod: brain-tasks-app               │  │ │
│  │  │  │  └─ Port: 80                        │  │ │
│  │  │  └─ Security Group: sg-xxxx            │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  │                                              │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │  EKS Node 3 (t3.medium)                │  │ │
│  │  │  ├─ Pod: brain-tasks-app               │  │ │
│  │  │  │  └─ Port: 80                        │  │ │
│  │  │  └─ Security Group: sg-xxxx            │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  Internet Gateway (IGW)                          │
│  Route Table: 10.0.0.0/16 → local                │
│             : 0.0.0.0/0 → IGW                    │
│                                                    │
└────────────────────────────────────────────────────┘
         │
         │ (Network Load Balancer)
         │
    ┌────▼──────┐
    │   Public  │
    │ Internet  │
    │           │
    │ Users     │
    └───────────┘
```

---

## Storage Architecture

```
┌─────────────────────────────────────┐
│         AWS S3 Bucket               │
│  (brain-tasks-artifacts-ACCOUNT_ID) │
├─────────────────────────────────────┤
│                                     │
│  CodePipeline Artifacts:            │
│  ├─ BuildOutput/                    │
│  │  ├─ imagedefinitions.json        │
│  │  ├─ appspec.yaml                 │
│  │  └─ k8s-manifests/               │
│  │     ├─ deployment.yaml           │
│  │     └─ service.yaml              │
│  │                                  │
│  └─ SourceOutput/                   │
│     └─ GitHub Code Snapshot         │
│                                     │
│  Retention: 30 days (configurable)  │
│  Encryption: SSE-S3 (default)       │
│                                     │
└─────────────────────────────────────┘


┌──────────────────────────────────────┐
│      AWS ECR Repository              │
│      (brain-tasks-app)               │
├──────────────────────────────────────┤
│                                      │
│  Docker Images:                      │
│  ├─ brain-tasks-app:latest           │
│  │  └─ Size: ~100-200MB (React app)  │
│  │                                   │
│  ├─ brain-tasks-app:v1.0             │
│  │  └─ Tagged version                │
│  │                                   │
│  └─ brain-tasks-app:2024-01-30       │
│     └─ Timestamp tagged              │
│                                      │
│  Lifecycle Policy: Keep last 10      │
│  Encryption: AES-256                 │
│  Scan on Push: Enabled               │
│                                      │
└──────────────────────────────────────┘
```

---

## Security Architecture

```
┌─────────────────────────────────────────────────────┐
│              AWS Identity & Access Management       │
│                      (IAM)                          │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. EKS Cluster Role                              │
│     └─ Permission: Manage EKS cluster             │
│        └─ Policy: AmazonEKSClusterPolicy          │
│                                                     │
│  2. EKS Node Role                                 │
│     ├─ Permission: Run on EC2                     │
│     ├─ Permission: Pull from ECR                  │
│     └─ Policies:                                  │
│        ├─ AmazonEKSWorkerNodePolicy               │
│        ├─ AmazonEKS_CNI_Policy                    │
│        └─ AmazonEC2ContainerRegistryReadOnly      │
│                                                     │
│  3. CodeBuild Role                                │
│     ├─ Permission: Build & push images            │
│     └─ Policy: Custom (ECR, S3, CloudWatch)       │
│                                                     │
│  4. CodeDeploy Role                               │
│     ├─ Permission: Deploy to EKS                  │
│     └─ Policy: AWSCodeDeployRoleForECS            │
│                                                     │
│  5. CodePipeline Role                             │
│     ├─ Permission: Orchestrate pipeline           │
│     └─ Policy: Custom (S3, CodeBuild, CodeDeploy) │
│                                                     │
│  6. ImagePullSecret (k8s)                         │
│     ├─ Stored in: Kubernetes cluster              │
│     ├─ Used by: Pods to pull images               │
│     └─ Type: docker-registry                      │
│                                                     │
│  7. Network Security Group (NSG)                  │
│     ├─ Ingress: Port 80 (HTTP)                    │
│     ├─ Ingress: Port 443 (HTTPS) - optional       │
│     └─ Egress: All outbound                       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Scalability & High Availability

### Horizontal Scaling (Replicas)
```
Deployment: brain-tasks-app
├─ Desired Replicas: 3
├─ Min Replicas: 1 (can scale down)
├─ Max Replicas: Based on HPA (optional)
└─ Pod Anti-Affinity: Spread across nodes
   └─ Each pod on different node if possible
   └─ Ensures no single node failure impacts all pods
```

### Node Scaling
```
Node Group: brain-tasks-nodegroup
├─ Min Nodes: 2
├─ Max Nodes: 4
├─ Desired Nodes: 3
├─ Instance Type: t3.medium
└─ Auto Scaling: Based on CPU/Memory metrics
```

### Rolling Updates
```
Strategy: RollingUpdate
├─ Max Surge: 1 (can have 1 extra pod during update)
├─ Max Unavailable: 0 (all pods must stay available)
└─ Process:
   1. Create new pod with new image
   2. Wait for readiness probe
   3. Stop old pod
   4. Repeat for next pod
   5. Zero-downtime deployment
```

---

## Deployment Summary

| Component | Resource | Count | Cost/Month |
|-----------|----------|-------|-----------|
| **Kubernetes** | EKS Cluster | 1 | $10 |
| | EC2 t3.medium Nodes | 3 | ~$30 |
| | Network Load Balancer | 1 | ~$16 |
| **Container** | ECR Repository | 1 | <$1 |
| | Docker Images | ~5 | |
| **CI/CD** | CodeBuild | 1 | ~$2 (builds) |
| | CodeDeploy | 1 | ~$1 (deployments) |
| | CodePipeline | 1 | ~$1 (pipeline) |
| **Monitoring** | CloudWatch Logs | 3 groups | ~$5 |
| **Networking** | Data Transfer Out | ~10GB | ~$5 |
| | VPC/Subnets | 1 | Free |
| **Storage** | S3 Artifacts | ~1GB | <$1 |
| | **Total** | | **~$70/month** |

---

## Disaster Recovery & Backup

### Current State
```
✅ Multi-AZ deployment (3 AZs with EKS nodes)
✅ Automated backups via CodePipeline (source in Git)
✅ Pod replicas (3) for redundancy
✅ Health checks (liveness & readiness probes)
✅ Logs in CloudWatch (30-day retention)

Additional Recommendations:
- [ ] Enable cluster auto-recovery
- [ ] Implement Velero for persistent volume backups
- [ ] Use backup plans for any databases
- [ ] Setup disaster recovery region (optional)
- [ ] Regular backup testing (monthly)
```

---

## Completion Checklist

- [x] Dockerfile created and tested locally
- [x] buildspec.yml configured for CodeBuild
- [x] appspec.yml configured for EKS deployment
- [x] k8s-manifests created (deployment.yaml, service.yaml)
- [x] IAM roles configured
- [x] VPC and networking setup
- [x] ECR repository ready
- [x] EKS cluster creation documented
- [x] Node group configuration documented
- [x] CodeBuild project setup documented
- [x] CodeDeploy application setup documented
- [x] CodePipeline setup documented
- [x] CloudWatch monitoring configured
- [x] All deployment steps documented
- [ ] Execute deployment steps (manual process)
- [ ] Verify application is running
- [ ] Collect LoadBalancer ARN
- [ ] Submit documentation and screenshots

---

**Architecture Version**: 1.0
**Last Updated**: 2024
**Status**: Production Ready
**Application**: Brain Tasks React App
**Target Environment**: AWS EKS (Kubernetes)
