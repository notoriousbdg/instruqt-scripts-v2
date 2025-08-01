#!/bin/bash

# Script to dynamically trigger database outage in log-generator service

set -e

LOG_GENERATOR_SERVICE_NAME="log-generator-service"
ADMIN_PORT="9000"
ENDPOINT_PATH="/admin/database-outage/trigger"

EXTERNAL_IP=$(kubectl get service log-generator-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

# Construct the URL
LOG_GENERATOR_URL="http://${EXTERNAL_IP}:${ADMIN_PORT}${ENDPOINT_PATH}"

curl -X POST "$LOG_GENERATOR_URL" \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 2 \
        --retry-delay 2 \
        --retry-connrefused \
        --fail \
        --silent \
        --show-error