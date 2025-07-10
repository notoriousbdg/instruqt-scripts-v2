#!/bin/bash

# Script to dynamically trigger database outage in log-generator service

set -e

LOG_GENERATOR_SERVICE_NAME="log-generator-service"
ADMIN_PORT="9000"
ENDPOINT_PATH="/admin/database-outage/trigger"
NAMESPACE="default"
TIMEOUT=300  # 5 minutes timeout

echo "🔍 Looking for log-generator service..."

# Wait for service to exist
echo "⏳ Waiting for service $LOG_GENERATOR_SERVICE_NAME to be available..."
kubectl wait --for=condition=ready service/$LOG_GENERATOR_SERVICE_NAME --namespace=$NAMESPACE --timeout=${TIMEOUT}s

echo "✅ Service $LOG_GENERATOR_SERVICE_NAME is available"

# Get the external IP of the LoadBalancer service
echo "🔍 Getting external IP of $LOG_GENERATOR_SERVICE_NAME..."

# Function to get external IP - handles both EXTERNAL-IP and LoadBalancer ingress
get_external_ip() {
    local service_name=$1
    local namespace=$2
    
    # Try to get EXTERNAL-IP first
    local external_ip=$(kubectl get service $service_name -n $namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    # If no IP, try to get hostname (for cloud providers that use hostnames)
    if [ -z "$external_ip" ] || [ "$external_ip" = "null" ]; then
        external_ip=$(kubectl get service $service_name -n $namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    fi
    
    # If still no external access, try cluster IP as fallback
    if [ -z "$external_ip" ] || [ "$external_ip" = "null" ]; then
        external_ip=$(kubectl get service $service_name -n $namespace -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
        echo "⚠️  Using cluster IP as fallback: $external_ip"
    fi
    
    echo "$external_ip"
}

# Wait for external IP to be assigned (LoadBalancer provisioning can take time)
echo "⏳ Waiting for external IP to be assigned..."
for i in {1..30}; do
    EXTERNAL_IP=$(get_external_ip $LOG_GENERATOR_SERVICE_NAME $NAMESPACE)
    
    if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
        echo "✅ External IP found: $EXTERNAL_IP"
        break
    fi
    
    echo "⏳ Waiting for external IP... (attempt $i/30)"
    sleep 10
done

if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "null" ] || [ "$EXTERNAL_IP" = "<pending>" ]; then
    echo "❌ Failed to get external IP for $LOG_GENERATOR_SERVICE_NAME"
    echo "📋 Service details:"
    kubectl get service $LOG_GENERATOR_SERVICE_NAME -n $NAMESPACE -o wide
    exit 1
fi

# Construct the URL
LOG_GENERATOR_URL="http://${EXTERNAL_IP}:${ADMIN_PORT}${ENDPOINT_PATH}"

echo "🎯 Triggering database outage..."
echo "📡 URL: $LOG_GENERATOR_URL"

# Make the curl request with retry logic
MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "🔄 Attempt $attempt/$MAX_RETRIES..."
    
    if curl -X POST "$LOG_GENERATOR_URL" \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 2 \
        --retry-delay 2 \
        --retry-connrefused \
        --fail \
        --silent \
        --show-error; then
        
        echo ""
        echo "✅ Database outage triggered successfully!"
        echo "🎯 Service: $LOG_GENERATOR_SERVICE_NAME"
        echo "📡 IP: $EXTERNAL_IP"
        echo "🚨 Database outage is now active in the log generator"
        exit 0
    else
        echo "❌ Request failed (attempt $attempt/$MAX_RETRIES)"
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "⏳ Retrying in 5 seconds..."
            sleep 5
        fi
    fi
done

echo "❌ Failed to trigger database outage after $MAX_RETRIES attempts"
echo "🔍 Troubleshooting information:"
echo "   - Service: $LOG_GENERATOR_SERVICE_NAME"
echo "   - IP: $EXTERNAL_IP"
echo "   - URL: $LOG_GENERATOR_URL"
echo "   - Check if the service is running: kubectl get pods -l app=log-generator"
echo "   - Check service status: kubectl get service $LOG_GENERATOR_SERVICE_NAME -n $NAMESPACE"
exit 1 