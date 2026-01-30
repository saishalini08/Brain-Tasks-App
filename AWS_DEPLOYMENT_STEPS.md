# AWS Deployment Steps - Brain Tasks React Application

This guide provides step-by-step instructions to deploy the React application to AWS using EKS, CodeBuild, CodeDeploy, and CodePipeline.

## Prerequisites

Ensure you have the following installed and configured:

```bash
# Check all prerequisites
aws --version          # AWS CLI v2
kubectl version --client
docker --version
git --version
node --version        # Node.js 16+
npm --version
```

## PART 1: LOCAL SETUP & DOCKER TESTING

### Step 1.1: Local Application Setup

```bash
# Navigate to project directory
cd /workspaces/Brain-Tasks-App

# Install dependencies
npm install

# Build the application
npm run build

# Verify build output
ls -la dist/
```

### Step 1.2: Test Docker Image Locally

```bash
# Build the Docker image
docker build -t brain-tasks-app:latest .

# Run the container (port 3000 on host -> port 80 in container)
docker run -d -p 3000:80 --name brain-tasks-app-test brain-tasks-app:latest

# Check if container is running
docker ps

# Test the application
curl http://localhost:3000
# OR open browser: http://localhost:3000

# View logs
docker logs brain-tasks-app-test

# Stop and remove container
docker stop brain-tasks-app-test
docker rm brain-tasks-app-test
```

---

## PART 2: AWS ACCOUNT SETUP

### Step 2.1: Set Environment Variables

```bash
# Export these for all subsequent commands
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1  # Change to your preferred region
export ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
export IMAGE_NAME=brain-tasks-app
export IMAGE_TAG=latest

# Verify variables
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "ECR Registry: $ECR_REGISTRY"
```

### Step 2.2: Create IAM Role for EKS

```bash
# Create trust policy document
cat > eks-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role for EKS cluster
aws iam create-role \
  --role-name brain-tasks-eks-cluster-role \
  --assume-role-policy-document file://eks-trust-policy.json

# Attach necessary policies
aws iam attach-role-policy \
  --role-name brain-tasks-eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Create trust policy for Node Group
cat > node-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role for Node Group
aws iam create-role \
  --role-name brain-tasks-eks-node-role \
  --assume-role-policy-document file://node-trust-policy.json

# Attach policies to Node role
aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name brain-tasks-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### Step 2.3: Create VPC and Subnets (if not exists)

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
echo "VPC ID: $VPC_ID"

# Create subnets
SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${AWS_REGION}a --query 'Subnet.SubnetId' --output text)
SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${AWS_REGION}b --query 'Subnet.SubnetId' --output text)

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

# Associate subnets with route table
aws ec2 associate-route-table --subnet-id $SUBNET_1 --route-table-id $ROUTE_TABLE_ID
aws ec2 associate-route-table --subnet-id $SUBNET_2 --route-table-id $ROUTE_TABLE_ID
```

---

## PART 3: ECR SETUP (Create Container Registry)

### Step 3.1: Create ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name $IMAGE_NAME \
  --region $AWS_REGION

# Output:
# {
#     "repository": {
#         "repositoryUri": "ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app"
#     }
# }
```

### Step 3.2: Login and Push Docker Image

```bash
# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Build and tag the image
docker build -t $IMAGE_NAME:$IMAGE_TAG .
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REGISTRY/$IMAGE_NAME:latest

# Push to ECR
docker push $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
docker push $ECR_REGISTRY/$IMAGE_NAME:latest

# Verify image in ECR
aws ecr list-images --repository-name $IMAGE_NAME --region $AWS_REGION
```

---

## PART 4: AWS EKS SETUP (Kubernetes Cluster)

### Step 4.1: Create EKS Cluster

```bash
# Create the EKS cluster (this takes 10-15 minutes)
aws eks create-cluster \
  --name brain-tasks-cluster \
  --version 1.28 \
  --role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-cluster-role \
  --resources-vpc-config subnetIds=$SUBNET_1,$SUBNET_2 \
  --region $AWS_REGION \
  --logging '{"clusterLogging":[{"enabled":true,"types":["api","audit","authenticator","controllerManager","scheduler"]}]}'

# Check cluster status
aws eks describe-cluster \
  --name brain-tasks-cluster \
  --region $AWS_REGION \
  --query 'cluster.status'
```

### Step 4.2: Configure kubectl

```bash
# Update kubeconfig to connect to the cluster
aws eks update-kubeconfig \
  --name brain-tasks-cluster \
  --region $AWS_REGION

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### Step 4.3: Create Node Group

```bash
# Create managed node group
aws eks create-nodegroup \
  --cluster-name brain-tasks-cluster \
  --nodegroup-name brain-tasks-nodegroup \
  --scaling-config minSize=2,maxSize=4,desiredSize=3 \
  --subnets $SUBNET_1 $SUBNET_2 \
  --node-role arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-eks-node-role \
  --instance-types t3.medium \
  --region $AWS_REGION

# Check node group status
aws eks describe-nodegroup \
  --cluster-name brain-tasks-cluster \
  --nodegroup-name brain-tasks-nodegroup \
  --region $AWS_REGION \
  --query 'nodegroup.status'

# Wait for nodes to be ready (5-10 minutes)
kubectl get nodes -w
```

### Step 4.4: Create ImagePullSecret for ECR

```bash
# Create secret for ECR authentication
kubectl create secret docker-registry ecr-secret \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region $AWS_REGION) \
  --docker-email=user@example.com \
  --namespace=default

# Verify secret
kubectl get secrets
```

---

## PART 5: KUBERNETES DEPLOYMENT

### Step 5.1: Update Kubernetes Manifests

Update [k8s-manifests/deployment.yaml](k8s-manifests/deployment.yaml) and [k8s-manifests/service.yaml](k8s-manifests/service.yaml) with your actual values.

**For deployment.yaml:**
- Replace `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/brain-tasks-app:latest` with your actual ECR URI
- Example: `123456789.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app:latest`

### Step 5.2: Deploy to EKS

```bash
# Apply the Kubernetes manifests
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

# Check deployment status
kubectl get deployments
kubectl get pods
kubectl get svc

# View deployment logs
kubectl logs -l app=brain-tasks-app -f

# Get LoadBalancer URL
kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 5.3: Verify Application

```bash
# Get the external IP/hostname
LOAD_BALANCER_URL=$(kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Application URL: http://$LOAD_BALANCER_URL"

# Test the application
curl http://$LOAD_BALANCER_URL
```

---

## PART 6: AWS CODEBUILD SETUP

### Step 6.1: Create IAM Role for CodeBuild

```bash
# Create trust policy for CodeBuild
cat > codebuild-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name brain-tasks-codebuild-role \
  --assume-role-policy-document file://codebuild-trust-policy.json

# Create and attach inline policy for ECR and CloudWatch
cat > codebuild-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name brain-tasks-codebuild-role \
  --policy-name brain-tasks-codebuild-policy \
  --policy-document file://codebuild-policy.json
```

### Step 6.2: Create CodeBuild Project

```bash
# Create CodeBuild project
aws codebuild create-project \
  --name brain-tasks-build \
  --source type=GITHUB,location=https://github.com/Vennilavan12/Brain-Tasks-App.git \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_MEDIUM,environmentVariables='[{"name":"AWS_ACCOUNT_ID","value":"'$AWS_ACCOUNT_ID'"},{"name":"AWS_DEFAULT_REGION","value":"'$AWS_REGION'"},{"name":"IMAGE_REPO_NAME","value":"brain-tasks-app"},{"name":"IMAGE_TAG","value":"latest"}]' \
  --service-role arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-codebuild-role \
  --logs-config cloudWatchLogs={status=ENABLED,groupName=/aws/codebuild/brain-tasks-build}

# Or use the existing buildspec.yml (already in repo)
# The buildspec.yml will be auto-detected from the repository root
```

### Step 6.3: Test CodeBuild

```bash
# Start a build
aws codebuild start-build \
  --project-name brain-tasks-build

# Monitor the build (wait for build ID from previous command)
# Example: build-id-here
aws codebuild batch-get-builds \
  --ids <BUILD_ID>

# Check build logs
aws logs tail /aws/codebuild/brain-tasks-build --follow
```

---

## PART 7: AWS CODEDEPLOY SETUP

### Step 7.1: Create CodeDeploy Application

```bash
# Create CodeDeploy application
aws deploy create-app \
  --application-name brain-tasks-app \
  --region $AWS_REGION

# Verify
aws deploy list-applications --region $AWS_REGION
```

### Step 7.2: Create CodeDeploy Deployment Group

```bash
# Create IAM role for CodeDeploy
cat > codedeploy-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name brain-tasks-codedeploy-role \
  --assume-role-policy-document file://codedeploy-trust-policy.json

# Attach policy
aws iam attach-role-policy \
  --role-name brain-tasks-codedeploy-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS

# Create deployment group
aws deploy create-deployment-group \
  --application-name brain-tasks-app \
  --deployment-group-name brain-tasks-deployment-group \
  --service-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-codedeploy-role \
  --deployment-config-name CodeDeployDefault.OneAtATime \
  --region $AWS_REGION
```

### Step 7.3: Verify appspec.yml

The `appspec.yml` file is already in your repository. For EKS deployment, use `appspec.yaml` structure.

---

## PART 8: AWS CODEPIPELINE SETUP

### Step 8.1: Create CodePipeline

```bash
# Create S3 bucket for pipeline artifacts
ARTIFACT_BUCKET="brain-tasks-pipeline-artifacts-$AWS_ACCOUNT_ID"
aws s3 mb s3://$ARTIFACT_BUCKET --region $AWS_REGION

# Create IAM role for CodePipeline
cat > codepipeline-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name brain-tasks-codepipeline-role \
  --assume-role-policy-document file://codepipeline-trust-policy.json

# Create policy for pipeline
cat > codepipeline-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild",
        "codedeploy:CreateDeployment",
        "codedeploy:GetApplication",
        "codedeploy:GetApplicationRevision",
        "codedeploy:GetDeployment",
        "codedeploy:GetDeploymentConfig",
        "codedeploy:RegisterApplicationRevision"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name brain-tasks-codepipeline-role \
  --policy-name brain-tasks-codepipeline-policy \
  --policy-document file://codepipeline-policy.json
```

### Step 8.2: Create GitHub Connection

```bash
# Create a CodeStar connection to GitHub
aws codestarconnections create-connection \
  --provider-type GitHub \
  --connection-name brain-tasks-github-connection

# This will return a connectionArn - save it
# You'll need to authorize the connection in the AWS Console
# Go to: Developer Tools > Connections > Pending connections
```

### Step 8.3: Create the Pipeline

```bash
# Create pipeline definition
cat > pipeline.json << EOF
{
  "pipeline": {
    "name": "brain-tasks-pipeline",
    "roleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/brain-tasks-codepipeline-role",
    "artifactStore": {
      "type": "S3",
      "location": "$ARTIFACT_BUCKET"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "SourceAction",
            "actionTypeId": {
              "category": "Source",
              "owner": "ThirdParty",
              "provider": "GitHub",
              "version": "1"
            },
            "configuration": {
              "Owner": "Vennilavan12",
              "Repo": "Brain-Tasks-App",
              "Branch": "main",
              "OAuthToken": "YOUR_GITHUB_PAT"
            },
            "outputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "BuildAction",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": {
              "ProjectName": "brain-tasks-build"
            },
            "inputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ],
            "outputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "DeployAction",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CodeDeploy",
              "version": "1"
            },
            "configuration": {
              "ApplicationName": "brain-tasks-app",
              "DeploymentGroupName": "brain-tasks-deployment-group"
            },
            "inputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      }
    ]
  }
}
EOF

# Create the pipeline
aws codepipeline create-pipeline --cli-input-json file://pipeline.json --region $AWS_REGION
```

---

## PART 9: CLOUDWATCH MONITORING

### Step 9.1: Create CloudWatch Log Groups

```bash
# Create log groups
aws logs create-log-group --log-group-name /aws/eks/brain-tasks-app
aws logs create-log-group --log-group-name /aws/codebuild/brain-tasks-build
aws logs create-log-group --log-group-name /aws/codedeploy/brain-tasks-app

# Set retention policy (30 days)
aws logs put-retention-policy \
  --log-group-name /aws/eks/brain-tasks-app \
  --retention-in-days 30

aws logs put-retention-policy \
  --log-group-name /aws/codebuild/brain-tasks-build \
  --retention-in-days 30

aws logs put-retention-policy \
  --log-group-name /aws/codedeploy/brain-tasks-app \
  --retention-in-days 30
```

### Step 9.2: View Logs

```bash
# View EKS pod logs
kubectl logs -l app=brain-tasks-app -f

# View CodeBuild logs
aws logs tail /aws/codebuild/brain-tasks-build --follow

# View CodeDeploy logs
aws logs tail /aws/codedeploy/brain-tasks-app --follow

# View CloudWatch Insights
# Go to: CloudWatch > Logs > Log Insights
# Create queries to analyze logs
```

### Step 9.3: Create CloudWatch Alarms

```bash
# Create alarm for pod restarts
aws cloudwatch put-metric-alarm \
  --alarm-name brain-tasks-pod-restarts \
  --alarm-description "Alert when pods are restarting" \
  --metric-name RestartCount \
  --namespace ECS \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold

# Create alarm for deployment failures
aws cloudwatch put-metric-alarm \
  --alarm-name brain-tasks-deployment-failures \
  --alarm-description "Alert on deployment failures" \
  --metric-name FailedDeployments \
  --namespace CodeDeploy \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold
```

---

## PART 10: GET LOADBALANCER ARN & FINAL VERIFICATION

### Step 10.1: Get LoadBalancer Information

```bash
# Get LoadBalancer DNS/URL
LOAD_BALANCER_HOSTNAME=$(kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LoadBalancer URL: http://$LOAD_BALANCER_HOSTNAME"

# Get LoadBalancer ARN
LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`k8s-default-brainte-*`].LoadBalancerArn' \
  --region $AWS_REGION \
  --output text)
echo "LoadBalancer ARN: $LOAD_BALANCER_ARN"

# OR get from EKS service annotation
kubectl get svc brain-tasks-app-service -o jsonpath='{.metadata.annotations}'

# Get all LoadBalancers
aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName,DNSName]' --output table
```

### Step 10.2: Final Verification

```bash
# Verify all components
echo "=== Checking EKS Cluster ==="
aws eks describe-cluster --name brain-tasks-cluster --region $AWS_REGION --query 'cluster.[name,status]'

echo "\n=== Checking Nodes ==="
kubectl get nodes

echo "\n=== Checking Pods ==="
kubectl get pods -l app=brain-tasks-app

echo "\n=== Checking Services ==="
kubectl get svc brain-tasks-app-service

echo "\n=== Checking Deployments ==="
kubectl get deployment brain-tasks-app

echo "\n=== Testing Application ==="
curl -I http://$LOAD_BALANCER_HOSTNAME

echo "\n=== Checking CodePipeline ==="
aws codepipeline get-pipeline-state --name brain-tasks-pipeline --region $AWS_REGION

echo "\n=== Application URL ==="
echo "Access your application at: http://$LOAD_BALANCER_HOSTNAME"
```

---

## PART 11: CLEANUP (When done testing)

```bash
# Delete the pipeline
aws codepipeline delete-pipeline --name brain-tasks-pipeline --region $AWS_REGION

# Delete CodeBuild project
aws codebuild delete-project --name brain-tasks-build --region $AWS_REGION

# Delete CodeDeploy application
aws deploy delete-app --application-name brain-tasks-app --region $AWS_REGION

# Delete Kubernetes services and deployments
kubectl delete svc brain-tasks-app-service
kubectl delete deployment brain-tasks-app

# Delete EKS cluster and node group
aws eks delete-nodegroup --cluster-name brain-tasks-cluster --nodegroup-name brain-tasks-nodegroup --region $AWS_REGION
aws eks delete-cluster --name brain-tasks-cluster --region $AWS_REGION

# Delete ECR repository
aws ecr delete-repository --repository-name brain-tasks-app --region $AWS_REGION --force

# Delete S3 bucket
aws s3 rb s3://$ARTIFACT_BUCKET --force

# Delete IAM roles and policies (after other resources are deleted)
aws iam delete-role-policy --role-name brain-tasks-eks-cluster-role --policy-name inline-policy
aws iam delete-role --role-name brain-tasks-eks-cluster-role
# ... (repeat for other roles)
```

---

## TROUBLESHOOTING

### Check Pod Status
```bash
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Check Deployment Status
```bash
kubectl get deployment brain-tasks-app -o yaml
kubectl describe deployment brain-tasks-app
```

### Check Service Status
```bash
kubectl get svc brain-tasks-app-service -o yaml
kubectl describe svc brain-tasks-app-service
```

### Check if Image is Pulled
```bash
kubectl get events --sort-by='.lastTimestamp'
```

### Check Node Status
```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

### View CodeBuild Logs
```bash
aws codebuild batch-get-builds --ids <BUILD_ID> --region $AWS_REGION
aws logs tail /aws/codebuild/brain-tasks-build --follow
```

### Check ECR Image
```bash
aws ecr describe-images --repository-name brain-tasks-app --region $AWS_REGION
aws ecr batch-get-image --repository-name brain-tasks-app --image-ids imageTag=latest --region $AWS_REGION
```

---

## Important Notes

1. **Port Configuration**: The application runs on port 80 inside the container (nginx), and the LoadBalancer exposes it publicly.

2. **GitHub Token**: For CodePipeline, you need a GitHub PAT (Personal Access Token) with `repo` and `admin:repo_hook` permissions.

3. **Costs**: Be aware of AWS costs:
   - EKS: $0.10 per cluster per hour
   - EC2 instances: depends on instance type
   - Load Balancer: ~$0.006 per hour
   - NAT Gateway: ~$0.045 per hour

4. **Auto-scaling**: The Node Group is configured to scale from 2 to 4 nodes based on CPU/memory usage.

5. **High Availability**: The deployment has 3 replicas configured for redundancy.

---

## Next Steps

1. Test the pipeline end-to-end
2. Monitor CloudWatch logs
3. Set up alerts for production
4. Plan backup and disaster recovery strategy
5. Document any customizations made

---

**For more information, see:**
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [AWS CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [AWS CodeDeploy Documentation](https://docs.aws.amazon.com/codedeploy/)
- [AWS CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
