#!/bin/bash

# Final AWS Deployment Steps

echo "=========================================="
echo "COMPLETING AWS EKS DEPLOYMENT"
echo "=========================================="
echo ""

CLUSTER_NAME="brain-tasks-app-cluster"
REGION="ap-south-1"
ACCOUNT_ID="524140443370"
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/brain-tasks-app:latest"

# Wait for cluster to be ACTIVE
echo "Waiting for cluster to be ACTIVE (15-20 min)..."
MAX_WAIT=50
COUNTER=0

while [ $COUNTER -lt $MAX_WAIT ]; do
    STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.status' --output text 2>&1)
    if [ "$STATUS" = "ACTIVE" ]; then
        echo "Cluster is ACTIVE!"
        break
    fi
    echo "Status: $STATUS (attempt $((COUNTER+1))/$MAX_WAIT)"
    COUNTER=$((COUNTER+1))
    sleep 30
done

echo ""
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

echo ""
echo "Creating node group..."
SUBNET_IDS="subnet-0225fca16fc51c6b4,subnet-0014884f33f99111f"
aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name brain-tasks-ng \
    --scaling-config minSize=2,maxSize=4,desiredSize=3 \
    --subnets subnet-0225fca16fc51c6b4 subnet-0014884f33f99111f \
    --node-role arn:aws:iam::$ACCOUNT_ID:role/brain-tasks-eks-node-role \
    --instance-types t3.medium \
    --region $REGION 2>&1 || echo "Node group may already exist"

echo ""
echo "Waiting for nodes to be ready (10-15 min)..."
COUNTER=0
while [ $COUNTER -lt 40 ]; do
    READY=$(kubectl get nodes --no-headers 2>&1 | grep -c "Ready" || echo 0)
    if [ "$READY" -ge 3 ]; then
        echo "All 3 nodes are Ready!"
        break
    fi
    echo "Ready nodes: $READY/3 (attempt $((COUNTER+1))/40)"
    COUNTER=$((COUNTER+1))
    sleep 30
done

echo ""
echo "Creating image pull secret..."
ECR_PASSWORD=$(aws ecr get-login-password --region $REGION)
kubectl create secret docker-registry ecr-secret \
    --docker-server="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com" \
    --docker-username=AWS \
    --docker-password="$ECR_PASSWORD" \
    --docker-email=user@example.com \
    --namespace=default 2>&1 || echo "Secret may already exist"

echo ""
echo "Deploying application..."
kubectl apply -f k8s-manifests/deployment.yaml
kubectl apply -f k8s-manifests/service.yaml

echo ""
echo "Waiting for pods to be running..."
COUNTER=0
while [ $COUNTER -lt 30 ]; do
    RUNNING=$(kubectl get pods -l app=brain-tasks-app --field-selector=status.phase=Running --no-headers 2>&1 | wc -l)
    if [ "$RUNNING" -ge 3 ]; then
        echo "All 3 pods are running!"
        break
    fi
    echo "Running pods: $RUNNING/3 (attempt $((COUNTER+1))/30)"
    COUNTER=$((COUNTER+1))
    sleep 10
done

echo ""
echo "Waiting for LoadBalancer URL (5-10 min)..."
COUNTER=0
while [ $COUNTER -lt 40 ]; do
    LB_URL=$(kubectl get svc brain-tasks-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>&1)
    if [ ! -z "$LB_URL" ] && [[ ! "$LB_URL" =~ "items" ]]; then
        echo ""
        echo "=========================================="
        echo "DEPLOYMENT COMPLETE!"
        echo "=========================================="
        echo ""
        echo "APP URL: http://$LB_URL"
        echo ""
        echo "Useful commands:"
        echo "  kubectl get pods"
        echo "  kubectl logs -l app=brain-tasks-app -f"
        echo "  kubectl get svc brain-tasks-app-service"
        break
    fi
    echo "Waiting for LoadBalancer URL (attempt $((COUNTER+1))/40)"
    COUNTER=$((COUNTER+1))
    sleep 30
done
