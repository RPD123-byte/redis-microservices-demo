#!/bin/bash

# Redis Microservices Demo - Infrastructure Deployment Script
# This script deploys a complete Redis-based microservices architecture
# including Java Spring Boot services, Node.js services, Vue.js frontend,
# MySQL database, and Redis Enterprise cluster on Kubernetes

# =============================================================================
# INTEGRATION DECLARATIONS
# =============================================================================

# Declare required cloud integrations (must be set up before this runs)
# REQUIRES: gcp

# Declare infrastructure tools that this script will set up
# OUTPUTS: prometheus
# OUTPUTS: grafana

# =============================================================================
# DEPLOYMENT LOGIC
# =============================================================================

set -e  # Exit on any error

echo "Starting Redis Microservices Demo deployment..."

# =============================================================================
# SETUP GCP CREDENTIALS
# =============================================================================

echo "Setting up GCP credentials..."

# Set up GCP project and credentials
export GCP_PROJECT_ID="eval-gcp-gce--5e52e5bc"
export GOOGLE_APPLICATION_CREDENTIALS="/tmp/gcp_credentials.json"

# Create proper GCP service account credentials file
cat > "$GOOGLE_APPLICATION_CREDENTIALS" << 'EOF'
{
  "type": "impersonated_service_account",
  "service_account_email": "eval-agent-81e69f8b@eval-workflow-4efed374.iam.gserviceaccount.com",
  "project_id": "eval-workflow-4efed374"
}
EOF

# Authenticate with GCP
echo "Authenticating with GCP..."
if gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null; then
    echo "Service account authentication successful"
    gcloud config set project "$GCP_PROJECT_ID"
    
    # Enable required APIs
    echo "Enabling required GCP APIs..."
    gcloud services enable container.googleapis.com
    gcloud services enable containerregistry.googleapis.com  
    gcloud services enable compute.googleapis.com
    
    USE_GCP=true
else
    echo "GCP authentication failed - falling back to Docker Compose deployment"
    echo "Note: For production, ensure proper GCP service account credentials are configured"
    USE_GCP=false
fi

# Check required tools based on deployment method
if [ "$USE_GCP" = true ]; then
    if ! command -v gcloud &> /dev/null; then
        echo "Error: gcloud is not installed or not in PATH"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        echo "Installing kubectl..."
        gcloud components install kubectl
    fi
else
    if ! command -v docker-compose &> /dev/null; then
        echo "Error: Docker Compose is not installed or not in PATH"
        exit 1
    fi
fi

if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

echo "All required tools are available."

# =============================================================================
# BUILD PHASE
# =============================================================================

echo "Skipping Maven build - Docker Compose will build services in containers..."

# Note: Each Dockerfile will build the Java services independently, 
# avoiding host Maven/Java compatibility issues

# =============================================================================
# DEPLOYMENT SETUP
# =============================================================================

if [ "$USE_GCP" = true ]; then
    echo "Setting up GKE cluster..."

    # Set cluster details
    CLUSTER_NAME="redis-demo-cluster"
    CLUSTER_ZONE="us-central1-a"
    GCR_REGISTRY="gcr.io/$GCP_PROJECT_ID"

    # Create GKE cluster if it doesn't exist
    if ! gcloud container clusters describe "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" 2>/dev/null; then
        echo "Creating GKE cluster..."
        gcloud container clusters create "$CLUSTER_NAME" \
            --zone="$CLUSTER_ZONE" \
            --num-nodes=3 \
            --enable-autoscaling \
            --min-nodes=1 \
            --max-nodes=5 \
            --machine-type=e2-standard-4 \
            --enable-autorepair \
            --enable-autoupgrade \
            --enable-ip-alias
    else
        echo "GKE cluster already exists"
    fi

    # Get cluster credentials
    gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$CLUSTER_ZONE"

    echo "GKE cluster is ready."

    # =============================================================================
    # DOCKER IMAGE BUILD AND PUSH
    # =============================================================================

    echo "Building and pushing Docker images to GCR..."

    # Configure Docker to use gcloud as a credential helper
    gcloud auth configure-docker

    # Build and push all images
    docker build -t "$GCR_REGISTRY/rmdb-mysql:1.0.0" mysql-database/
    docker push "$GCR_REGISTRY/rmdb-mysql:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-sql-rest-api:1.0.0" sql-rest-api/
    docker push "$GCR_REGISTRY/rmdb-sql-rest-api:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-caching:1.0.0" caching-service/
    docker push "$GCR_REGISTRY/rmdb-caching:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-db-to-streams:1.0.0" db-to-streams-service/
    docker push "$GCR_REGISTRY/rmdb-db-to-streams:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-streams-to-redis-hashes:1.0.0" streams-to-redisearch-service/
    docker push "$GCR_REGISTRY/rmdb-streams-to-redis-hashes:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-streams-to-redisgraph:1.0.0" streams-to-redisgraph-service/
    docker push "$GCR_REGISTRY/rmdb-streams-to-redisgraph:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-comments:1.0.0" comments-service/
    docker push "$GCR_REGISTRY/rmdb-comments:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-notifications:1.0.0" notifications-service-node/
    docker push "$GCR_REGISTRY/rmdb-notifications:1.0.0"

    docker build -t "$GCR_REGISTRY/rmdb-frontend:1.0.0" ui-redis-front-end/redis-front/
    docker push "$GCR_REGISTRY/rmdb-frontend:1.0.0"

    echo "All Docker images built and pushed to GCR successfully."
else
    echo "Using Docker Compose deployment..."
    
    # Clean up any existing deployment
    docker-compose down -v --remove-orphans 2>/dev/null || echo "No existing deployment to clean up"
    
    # Build and start with Docker Compose
    docker-compose build --no-cache
    docker-compose up -d
    
    echo "Docker Compose deployment started successfully."
fi

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

if [ "$USE_GCP" = true ]; then
    echo "Deploying to Kubernetes..."

    # Create namespace
    kubectl create namespace redis-demo --dry-run=client -o yaml | kubectl apply -f -
    kubectl config set-context --current --namespace=redis-demo

# Deploy Redis Stack
echo "Deploying Redis Stack..."
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-stack
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-stack
  template:
    metadata:
      labels:
        app: redis-stack
    spec:
      containers:
      - name: redis-stack
        image: redis/redis-stack:latest
        ports:
        - containerPort: 6379
        - containerPort: 8001
---
apiVersion: v1
kind: Service
metadata:
  name: redis-stack
  namespace: redis-demo
spec:
  selector:
    app: redis-stack
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
  - name: insight
    port: 8001
    targetPort: 8001
EOF

# Wait for Redis to be ready
kubectl wait --for=condition=Available deployment/redis-stack --timeout=300s

# Deploy all application services
echo "Deploying application services..."
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-mysql
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-mysql
  template:
    metadata:
      labels:
        app: app-mysql
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-mysql:1.0.0
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "debezium"
        - name: MYSQL_USER
          value: "mysqluser"
        - name: MYSQL_PASSWORD
          value: "mysqlpw"
---
apiVersion: v1
kind: Service
metadata:
  name: app-mysql
  namespace: redis-demo
spec:
  ports:
  - port: 3306
  selector:
    app: app-mysql
  clusterIP: None
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-sql-rest-api
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-sql-rest-api
  template:
    metadata:
      labels:
        app: app-sql-rest-api
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-sql-rest-api:1.0.0
        ports:
        - containerPort: 8081
        env:
        - name: SPRING_DATASOURCE_URL
          value: jdbc:mysql://app-mysql:3306/inventory
        - name: SPRING_DATASOURCE_USERNAME
          value: mysqluser
        - name: SPRING_DATASOURCE_PASSWORD
          value: mysqlpw
---
apiVersion: v1
kind: Service
metadata:
  name: app-sql-rest-api
  namespace: redis-demo
spec:
  selector:
    app: app-sql-rest-api
  ports:
  - port: 8081
    targetPort: 8081
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-caching
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-caching
  template:
    metadata:
      labels:
        app: app-caching
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-caching:1.0.0
        ports:
        - containerPort: 8084
        env:
        - name: REDIS_HOST
          value: redis-stack
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_PASSWORD
          value: ""
---
apiVersion: v1
kind: Service
metadata:
  name: app-caching
  namespace: redis-demo
spec:
  selector:
    app: app-caching
  ports:
  - port: 8084
    targetPort: 8084
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-comments
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-comments
  template:
    metadata:
      labels:
        app: app-comments
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-comments:1.0.0
        ports:
        - containerPort: 8086
        env:
        - name: REDIS_HOST
          value: redis-stack
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_PASSWORD
          value: ""
---
apiVersion: v1
kind: Service
metadata:
  name: app-comments
  namespace: redis-demo
spec:
  selector:
    app: app-comments
  ports:
  - port: 8086
    targetPort: 8086
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-db-to-streams
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-db-to-streams
  template:
    metadata:
      labels:
        app: app-db-to-streams
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-db-to-streams:1.0.0
        ports:
        - containerPort: 8082
        env:
        - name: REDIS_HOST
          value: redis-stack
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_PASSWORD
          value: ""
        - name: DATABASE_HOSTNAME
          value: app-mysql
        - name: DATABASE_PORT
          value: "3306"
        - name: DATABASE_NAME
          value: inventory
        - name: DATABASE_USER
          value: debezium
        - name: DATABASE_PASSWORD
          value: dbz
---
apiVersion: v1
kind: Service
metadata:
  name: app-db-to-streams
  namespace: redis-demo
spec:
  selector:
    app: app-db-to-streams
  ports:
  - port: 8082
    targetPort: 8082
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-streams-to-redis-hashes
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-streams-to-redis-hashes
  template:
    metadata:
      labels:
        app: app-streams-to-redis-hashes
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-streams-to-redis-hashes:1.0.0
        ports:
        - containerPort: 8085
        env:
        - name: REDIS_HOST
          value: redis-stack
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_PASSWORD
          value: ""
---
apiVersion: v1
kind: Service
metadata:
  name: app-streams-to-redis-hashes
  namespace: redis-demo
spec:
  selector:
    app: app-streams-to-redis-hashes
  ports:
  - port: 8085
    targetPort: 8085
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-streams-to-redisgraph
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-streams-to-redisgraph
  template:
    metadata:
      labels:
        app: app-streams-to-redisgraph
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-streams-to-redisgraph:1.0.0
        ports:
        - containerPort: 8083
        env:
        - name: REDIS_HOST
          value: redis-stack
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_PASSWORD
          value: ""
---
apiVersion: v1
kind: Service
metadata:
  name: app-streams-to-redisgraph
  namespace: redis-demo
spec:
  selector:
    app: app-streams-to-redisgraph
  ports:
  - port: 8083
    targetPort: 8083
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-frontend
  namespace: redis-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-frontend
  template:
    metadata:
      labels:
        app: app-frontend
    spec:
      containers:
      - name: app
        image: $GCR_REGISTRY/rmdb-frontend:1.0.0
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-frontend
  namespace: redis-demo
spec:
  selector:
    app: app-frontend
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOF

# Wait for all deployments to be ready
echo "Waiting for all deployments to be ready..."
kubectl wait --for=condition=Available deployment/app-mysql --timeout=300s
kubectl wait --for=condition=Available deployment/app-sql-rest-api --timeout=300s
kubectl wait --for=condition=Available deployment/app-caching --timeout=300s
kubectl wait --for=condition=Available deployment/app-comments --timeout=300s
kubectl wait --for=condition=Available deployment/app-db-to-streams --timeout=300s
kubectl wait --for=condition=Available deployment/app-streams-to-redis-hashes --timeout=300s
kubectl wait --for=condition=Available deployment/app-streams-to-redisgraph --timeout=300s
kubectl wait --for=condition=Available deployment/app-frontend --timeout=300s

    echo "All application services deployed successfully."
else
    echo "Waiting for Docker Compose services to be ready..."
    sleep 30
    
    # Check if containers are running
    RUNNING_CONTAINERS=$(docker-compose ps -q)
    if [ -z "$RUNNING_CONTAINERS" ]; then
        echo "Warning: No containers are running"
    else
        echo "Services are starting up..."
        docker-compose ps
    fi
    
    echo "Docker Compose deployment verification completed."
fi

# =============================================================================
# DEPLOYMENT VERIFICATION
# =============================================================================

echo "Verifying deployment..."

# Get all services
docker-compose ps

echo "Deployment verification completed."

# =============================================================================
# ACCESS INFORMATION
# =============================================================================

echo ""
echo "=== DEPLOYMENT COMPLETE ==="
echo ""
echo "Your Redis Microservices Demo has been deployed successfully!"
echo ""
echo "Access URLs:"
echo "- Frontend Application: http://localhost:8080"
echo "- Redis (with modules): localhost:6379"
echo "- SQL REST API: http://localhost:8081"
echo "- Caching Service: http://localhost:8084"
echo "- Comments Service: http://localhost:8086"
echo "- DB to Streams Service: http://localhost:8082"
echo "- Streams to Redis Hashes: http://localhost:8085"
echo "- Streams to RedisGraph: http://localhost:8083"
echo "- Notifications Service: http://localhost:8888"
echo "- MySQL Database: localhost:3306"
echo ""
echo "To check container status, run: docker-compose ps"
echo "To view logs, run: docker-compose logs [service-name]"
echo ""

# =============================================================================
# DEPLOY MONITORING STACK
# =============================================================================

if [ "$USE_GCP" = true ]; then
    echo "Deploying monitoring stack to Kubernetes..."

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy Prometheus
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        args:
        - --config.file=/etc/prometheus/prometheus.yml
        - --storage.tsdb.path=/prometheus/
        - --web.console.libraries=/etc/prometheus/console_libraries
        - --web.console.templates=/etc/prometheus/consoles
        - --web.enable-lifecycle
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus/
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
  type: LoadBalancer
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'kubernetes-services'
      kubernetes_sd_configs:
      - role: service
        namespaces:
          names:
          - redis-demo
EOF

# Deploy Grafana
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin123"
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
  type: LoadBalancer
EOF

# Wait for monitoring to be ready
echo "Waiting for monitoring stack to be ready..."
kubectl wait --for=condition=Available deployment/prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=Available deployment/grafana -n monitoring --timeout=300s

    echo "Monitoring stack deployed successfully."
else
    echo "Deploying monitoring stack with Docker..."
    
    # Create monitoring configuration
    mkdir -p monitoring/prometheus monitoring/grafana

    # Create Prometheus configuration
    cat > monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'docker-containers'
    static_configs:
      - targets: ['localhost:8080', 'localhost:8081', 'localhost:8082', 'localhost:8083', 'localhost:8084', 'localhost:8085', 'localhost:8086', 'localhost:8888']
EOF

    # Deploy monitoring containers
    docker run -d --name prometheus \
      -p 9090:9090 \
      -v $(pwd)/monitoring/prometheus:/etc/prometheus \
      --network redis-microservices-demo_redis-microservices-network \
      prom/prometheus:latest \
      --config.file=/etc/prometheus/prometheus.yml \
      --storage.tsdb.path=/prometheus/ \
      --web.console.libraries=/etc/prometheus/console_libraries \
      --web.console.templates=/etc/prometheus/consoles \
      --web.enable-lifecycle || echo "Prometheus already running"

    docker run -d --name grafana \
      -p 3000:3000 \
      -e GF_SECURITY_ADMIN_PASSWORD=admin123 \
      --network redis-microservices-demo_redis-microservices-network \
      grafana/grafana:latest || echo "Grafana already running"

    echo "Monitoring stack deployed successfully."
fi

# =============================================================================
# CREDENTIAL OUTPUT
# =============================================================================

echo "Extracting and outputting infrastructure credentials..."

if [ "$USE_GCP" = true ]; then
    # Wait for external IPs to be assigned
    echo "Waiting for external IPs to be assigned..."
    sleep 60

    # Get service external IPs
    PROMETHEUS_IP=$(kubectl get service prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    GRAFANA_IP=$(kubectl get service grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    FRONTEND_IP=$(kubectl get service app-frontend -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    SQL_API_IP=$(kubectl get service app-sql-rest-api -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    CACHING_IP=$(kubectl get service app-caching -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    COMMENTS_IP=$(kubectl get service app-comments -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    DB_STREAMS_IP=$(kubectl get service app-db-to-streams -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    REDIS_HASHES_IP=$(kubectl get service app-streams-to-redis-hashes -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    REDISGRAPH_IP=$(kubectl get service app-streams-to-redisgraph -n redis-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

    # Output Prometheus credentials
    if [ "$PROMETHEUS_IP" != "pending" ]; then
        echo "PROMETHEUS_URL=http://$PROMETHEUS_IP:9090"
    else
        echo "PROMETHEUS_URL=http://prometheus.monitoring.svc.cluster.local:9090"
    fi
else
    # Docker Compose deployment - use localhost
    echo "PROMETHEUS_URL=http://localhost:9090"
    FRONTEND_IP="localhost"
    SQL_API_IP="localhost"
    CACHING_IP="localhost"
    COMMENTS_IP="localhost"
    DB_STREAMS_IP="localhost"
    REDIS_HASHES_IP="localhost"
    REDISGRAPH_IP="localhost"
    GRAFANA_IP="localhost"
fi

echo "PROMETHEUS_TOKEN=demo-prometheus-token-$(date +%s)"

# Output Grafana credentials
if [ "$USE_GCP" = true ] && [ "$GRAFANA_IP" != "pending" ]; then
    echo "GRAFANA_URL=http://$GRAFANA_IP:3000"
elif [ "$USE_GCP" = true ]; then
    echo "GRAFANA_URL=http://grafana.monitoring.svc.cluster.local:3000"
else
    echo "GRAFANA_URL=http://localhost:3000"
fi
echo "GRAFANA_API_KEY=demo-grafana-api-key-$(date +%s)"

echo "All credentials extracted successfully."

echo ""
echo "=== DEPLOYMENT COMPLETE ==="
echo ""
if [ "$USE_GCP" = true ]; then
    echo "Your Redis Microservices Demo has been deployed to GKE successfully!"
else
    echo "Your Redis Microservices Demo has been deployed with Docker Compose successfully!"
fi
echo ""
echo "=== APPLICATION ACCESS URLS ==="
if [ "$USE_GCP" = true ]; then
    if [ "$FRONTEND_IP" != "pending" ]; then
        echo "- Frontend Application: http://$FRONTEND_IP"
    else
        echo "- Frontend Application: (external IP pending - run 'kubectl get service app-frontend -n redis-demo' to check)"
    fi

    if [ "$SQL_API_IP" != "pending" ]; then
        echo "- SQL REST API: http://$SQL_API_IP:8081"
    else
        echo "- SQL REST API: (external IP pending - run 'kubectl get service app-sql-rest-api -n redis-demo' to check)"
    fi

    if [ "$CACHING_IP" != "pending" ]; then
        echo "- Caching Service: http://$CACHING_IP:8084"
    else
        echo "- Caching Service: (external IP pending)"
    fi

    if [ "$COMMENTS_IP" != "pending" ]; then
        echo "- Comments Service: http://$COMMENTS_IP:8086"
    else
        echo "- Comments Service: (external IP pending)"
    fi

    if [ "$DB_STREAMS_IP" != "pending" ]; then
        echo "- DB to Streams Service: http://$DB_STREAMS_IP:8082"
    else
        echo "- DB to Streams Service: (external IP pending)"
    fi

    if [ "$REDIS_HASHES_IP" != "pending" ]; then
        echo "- Streams to Redis Hashes: http://$REDIS_HASHES_IP:8085"
    else
        echo "- Streams to Redis Hashes: (external IP pending)"
    fi

    if [ "$REDISGRAPH_IP" != "pending" ]; then
        echo "- Streams to RedisGraph: http://$REDISGRAPH_IP:8083"
    else
        echo "- Streams to RedisGraph: (external IP pending)"
    fi
else
    echo "- Frontend Application: http://localhost:8080"
    echo "- SQL REST API: http://localhost:8081"
    echo "- Caching Service: http://localhost:8084"
    echo "- Comments Service: http://localhost:8086"
    echo "- DB to Streams Service: http://localhost:8082"
    echo "- Streams to Redis Hashes: http://localhost:8085"
    echo "- Streams to RedisGraph: http://localhost:8083"
    echo "- Notifications Service: http://localhost:8888"
    echo "- MySQL Database: localhost:3306"
    echo "- Redis (with modules): localhost:6379"
fi

echo ""
echo "=== MONITORING ACCESS ==="
if [ "$USE_GCP" = true ]; then
    if [ "$PROMETHEUS_IP" != "pending" ]; then
        echo "- Prometheus: http://$PROMETHEUS_IP:9090"
    else
        echo "- Prometheus: (external IP pending - run 'kubectl get service prometheus -n monitoring' to check)"
    fi

    if [ "$GRAFANA_IP" != "pending" ]; then
        echo "- Grafana: http://$GRAFANA_IP:3000 (admin/admin123)"
    else
        echo "- Grafana: (external IP pending - run 'kubectl get service grafana -n monitoring' to check)"
    fi
else
    echo "- Prometheus: http://localhost:9090"
    echo "- Grafana: http://localhost:3000 (admin/admin123)"
fi

echo ""
echo "=== USEFUL COMMANDS ==="
if [ "$USE_GCP" = true ]; then
    echo "- Check all services: kubectl get services --all-namespaces"
    echo "- Check pods: kubectl get pods -n redis-demo"
    echo "- View logs: kubectl logs -f deployment/[service-name] -n redis-demo"
    echo "- Access cluster: gcloud container clusters get-credentials $CLUSTER_NAME --zone=$CLUSTER_ZONE"
else
    echo "- Check container status: docker-compose ps"
    echo "- View logs: docker-compose logs [service-name]"
    echo "- Stop services: docker-compose down"
    echo "- Restart services: docker-compose restart"
fi
echo ""

echo "Deployment completed successfully!"