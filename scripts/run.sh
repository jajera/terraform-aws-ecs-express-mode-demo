#!/bin/bash
set -e

echo "=== ECS Express Mode Demo - Full Lifecycle ==="

# Step 1: Initialize Terraform
echo "Initializing Terraform..."
if ! terraform init; then
    echo "ERROR: Terraform init failed" >&2
    exit 1
fi

# Step 2: Apply Terraform configuration
echo "Applying Terraform configuration..."
if ! terraform apply -auto-approve; then
    echo "ERROR: Terraform apply failed" >&2
    exit 1
fi

# Step 3: Verify deployment
echo "Verifying deployment..."
SERVICE_URL=$(terraform output -raw service_url)
HEALTH_URL=$(terraform output -raw health_check_url)
MAX_RETRIES=30
RETRY_INTERVAL=10

echo "Polling health endpoint: ${HEALTH_URL}"
for i in $(seq 1 $MAX_RETRIES); do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "Health check passed (HTTP 200) on attempt ${i}"
        WEB_UI_URL=$(terraform output -raw web_ui_url)
        DOCS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${WEB_UI_URL}" 2>/dev/null || echo "000")
        echo "Service URL:    ${SERVICE_URL}"
        echo "Web UI (docs):  ${WEB_UI_URL} (HTTP ${DOCS_STATUS})"
        echo "Note: opening the service URL root path returns 404; use the Web UI URL above."
        break
    fi
    if [ "$i" = "$MAX_RETRIES" ]; then
        echo "ERROR: Health check failed after ${MAX_RETRIES} attempts" >&2
        exit 1
    fi
    echo "Attempt ${i}/${MAX_RETRIES}: HTTP ${HTTP_STATUS} - retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

# Step 4: Destroy resources
echo "Destroying resources..."
if ! terraform destroy -auto-approve; then
    echo "ERROR: Terraform destroy failed" >&2
    exit 1
fi

echo "=== Lifecycle complete ==="
