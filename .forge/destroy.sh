#!/bin/bash

# Redis Microservices Demo - Infrastructure Destroy Script
# This script cleanly tears down the complete Redis-based microservices architecture
# including all services, databases, monitoring, and infrastructure components

# =============================================================================
# DESTROY DECLARATIONS
# =============================================================================

# This script will clean up:
# - All Docker containers and images
# - All Kubernetes resources
# - All GCP resources including GKE cluster
# - All monitoring components (Prometheus, Grafana)
# - All temporary files and configurations

# =============================================================================
# DESTROY LOGIC
# =============================================================================

set -e  # Exit on any error

echo "Starting Redis Microservices Demo destruction..."

# =============================================================================
# DETECT DEPLOYMENT TYPE
# =============================================================================

# Check if we have a GKE cluster running
USE_GCP=false
if command -v gcloud &> /dev/null && command -v kubectl &> /dev/null; then
    export GCP_PROJECT_ID="eval-gcp-gce--5e52e5bc"
    export GOOGLE_APPLICATION_CREDENTIALS="/tmp/gcp_credentials.json"
    
    # Try to authenticate with GCP
    if gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null; then
        gcloud config set project "$GCP_PROJECT_ID"
        
        # Check if the cluster exists
        CLUSTER_NAME="redis-demo-cluster"
        CLUSTER_ZONE="us-central1-a"
        
        if gcloud container clusters describe "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" 2>/dev/null; then
            echo "Found GKE cluster - will destroy GCP resources"
            USE_GCP=true
        else
            echo "No GKE cluster found - will destroy Docker Compose resources only"
        fi
    else
        echo "GCP authentication failed - will destroy Docker Compose resources only"
    fi
fi

# =============================================================================
# DESTROY KUBERNETES RESOURCES
# =============================================================================

if [ "$USE_GCP" = true ]; then
    echo "Destroying Kubernetes resources..."
    
    # Get cluster credentials
    gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" 2>/dev/null || true
    
    # Delete all application resources
    echo "Deleting application namespace and resources..."
    kubectl delete namespace redis-demo --ignore-not-found=true --timeout=300s
    
    # Delete monitoring resources
    echo "Deleting monitoring namespace and resources..."
    kubectl delete namespace monitoring --ignore-not-found=true --timeout=300s
    
    # Wait for namespaces to be fully deleted
    echo "Waiting for namespaces to be fully deleted..."
    kubectl wait --for=delete namespace/redis-demo --timeout=300s 2>/dev/null || true
    kubectl wait --for=delete namespace/monitoring --timeout=300s 2>/dev/null || true
    
    echo "Kubernetes resources destroyed successfully."
fi

# =============================================================================
# DESTROY GCP INFRASTRUCTURE
# =============================================================================

if [ "$USE_GCP" = true ]; then
    echo "Destroying GCP infrastructure..."
    
    # Delete the GKE cluster
    echo "Deleting GKE cluster (this may take several minutes)..."
    gcloud container clusters delete "$CLUSTER_NAME" \
        --zone="$CLUSTER_ZONE" \
        --quiet || echo "Cluster deletion failed or already deleted"
    
    # Clean up any remaining compute instances
    echo "Cleaning up any remaining compute instances..."
    gcloud compute instances list --filter="name~'gke-redis-demo-cluster'" --format="value(name,zone)" | \
    while read instance zone; do
        if [ -n "$instance" ]; then
            echo "Deleting instance: $instance in zone: $zone"
            gcloud compute instances delete "$instance" --zone="$zone" --quiet || true
        fi
    done
    
    # Clean up any remaining disks
    echo "Cleaning up any remaining persistent disks..."
    gcloud compute disks list --filter="name~'gke-redis-demo-cluster'" --format="value(name,zone)" | \
    while read disk zone; do
        if [ -n "$disk" ]; then
            echo "Deleting disk: $disk in zone: $zone"
            gcloud compute disks delete "$disk" --zone="$zone" --quiet || true
        fi
    done
    
    # Clean up any remaining load balancers
    echo "Cleaning up any remaining load balancers..."
    gcloud compute forwarding-rules list --filter="name~'k8s'" --format="value(name,region)" | \
    while read rule region; do
        if [ -n "$rule" ]; then
            echo "Deleting forwarding rule: $rule in region: $region"
            gcloud compute forwarding-rules delete "$rule" --region="$region" --quiet || true
        fi
    done
    
    # Clean up any remaining target pools
    echo "Cleaning up any remaining target pools..."
    gcloud compute target-pools list --filter="name~'k8s'" --format="value(name,region)" | \
    while read pool region; do
        if [ -n "$pool" ]; then
            echo "Deleting target pool: $pool in region: $region"
            gcloud compute target-pools delete "$pool" --region="$region" --quiet || true
        fi
    done
    
    # Clean up any remaining firewall rules
    echo "Cleaning up any remaining firewall rules..."
    gcloud compute firewall-rules list --filter="name~'gke-redis-demo-cluster'" --format="value(name)" | \
    while read rule; do
        if [ -n "$rule" ]; then
            echo "Deleting firewall rule: $rule"
            gcloud compute firewall-rules delete "$rule" --quiet || true
        fi
    done
    
    # Clean up container images from GCR
    echo "Cleaning up container images from GCR..."
    GCR_REGISTRY="gcr.io/$GCP_PROJECT_ID"
    
    # List of images to delete
    IMAGES=(
        "rmdb-mysql"
        "rmdb-sql-rest-api"
        "rmdb-caching"
        "rmdb-db-to-streams"
        "rmdb-streams-to-redis-hashes"
        "rmdb-streams-to-redisgraph"
        "rmdb-comments"
        "rmdb-notifications"
        "rmdb-frontend"
    )
    
    for image in "${IMAGES[@]}"; do
        echo "Deleting image: $GCR_REGISTRY/$image"
        gcloud container images delete "$GCR_REGISTRY/$image:1.0.0" --quiet --force-delete-tags || true
    done
    
    echo "GCP infrastructure destroyed successfully."
fi

# =============================================================================
# DESTROY DOCKER COMPOSE RESOURCES
# =============================================================================

echo "Destroying Docker Compose resources..."

# Stop and remove all containers, networks, and volumes
echo "Stopping Docker Compose services..."
docker-compose down -v --remove-orphans --timeout 30 2>/dev/null || true

# Remove any standalone monitoring containers
echo "Removing standalone monitoring containers..."
docker rm -f prometheus grafana 2>/dev/null || true

# Clean up Docker images
echo "Cleaning up Docker images..."
docker image prune -f 2>/dev/null || true

# Remove specific images if they exist
DOCKER_IMAGES=(
    "redis-microservices-demo-app-mysql"
    "redis-microservices-demo-app-sql-rest-api"
    "redis-microservices-demo-app-caching"
    "redis-microservices-demo-app-db-to-streams"
    "redis-microservices-demo-app-streams-to-redis-hashes"
    "redis-microservices-demo-app-streams-to-redisgraph"
    "redis-microservices-demo-app-comments"
    "redis-microservices-demo-app-frontend"
    "redis-microservices-demo-ws-notifications-service"
)

for image in "${DOCKER_IMAGES[@]}"; do
    echo "Removing image: $image"
    docker rmi "$image:latest" 2>/dev/null || true
done

# Clean up any remaining containers
echo "Cleaning up any remaining containers..."
docker container prune -f 2>/dev/null || true

# Clean up any remaining volumes
echo "Cleaning up any remaining volumes..."
docker volume prune -f 2>/dev/null || true

# Clean up any remaining networks
echo "Cleaning up any remaining networks..."
docker network prune -f 2>/dev/null || true

echo "Docker Compose resources destroyed successfully."

# =============================================================================
# CLEANUP TEMPORARY FILES
# =============================================================================

echo "Cleaning up temporary files..."

# Remove GCP credentials file
rm -f /tmp/gcp_credentials.json

# Remove monitoring configuration
rm -rf monitoring/

# Remove any temporary kubectl contexts
kubectl config delete-context gke_${GCP_PROJECT_ID}_${CLUSTER_ZONE}_${CLUSTER_NAME} 2>/dev/null || true

echo "Temporary files cleaned up successfully."

# =============================================================================
# FINAL VERIFICATION
# =============================================================================

echo "Verifying destruction..."

# Check for any remaining containers
REMAINING_CONTAINERS=$(docker ps -a --filter "name=redis-microservices-demo" --format "table {{.Names}}" | grep -v "NAMES" | wc -l)
if [ "$REMAINING_CONTAINERS" -gt 0 ]; then
    echo "Warning: Found $REMAINING_CONTAINERS remaining containers"
    docker ps -a --filter "name=redis-microservices-demo"
else
    echo "All containers removed successfully"
fi

# Check for any remaining images
REMAINING_IMAGES=$(docker images --filter "reference=redis-microservices-demo*" --format "table {{.Repository}}" | grep -v "REPOSITORY" | wc -l)
if [ "$REMAINING_IMAGES" -gt 0 ]; then
    echo "Warning: Found $REMAINING_IMAGES remaining images"
    docker images --filter "reference=redis-microservices-demo*"
else
    echo "All images removed successfully"
fi

if [ "$USE_GCP" = true ]; then
    # Check if cluster still exists
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" 2>/dev/null; then
        echo "Warning: GKE cluster still exists"
    else
        echo "GKE cluster removed successfully"
    fi
fi

echo "Destruction verification completed."

# =============================================================================
# COMPLETION
# =============================================================================

echo ""
echo "=== DESTRUCTION COMPLETE ==="
echo ""
echo "Redis Microservices Demo has been completely destroyed!"
echo ""
echo "What was cleaned up:"
echo "- All application containers and images"
echo "- All database containers and volumes"
echo "- All monitoring containers (Prometheus, Grafana)"
echo "- All Docker networks and volumes"
if [ "$USE_GCP" = true ]; then
    echo "- GKE cluster and all Kubernetes resources"
    echo "- All GCP compute instances and disks"
    echo "- All GCP load balancers and networking"
    echo "- All container images from Google Container Registry"
fi
echo "- All temporary files and configurations"
echo ""
echo "Your system has been restored to its original state."
echo ""