#!/bin/bash
# Install Open Horizon Exchange on hub VM
# This script is executed by the Makefile after cloud-init completes
# and the hub IP has been discovered.

set -e

# Configuration
EXCHANGE_TIMEOUT=${EXCHANGE_TIMEOUT:-30}
SERVICE_TIMEOUT=${SERVICE_TIMEOUT:-60}
DEPLOY_OUTPUT="/tmp/deploy-output.txt"
ROLLBACK_MARKER="/tmp/hub-deployment-started"

# Pinned versions for reproducibility
export CSS_IMAGE_TAG="${CSS_IMAGE_TAG:-testing}"
export MONGO_IMAGE_TAG="${MONGO_IMAGE_TAG:-4.0.6}"
export EXCHANGE_IMAGE_NAME="${EXCHANGE_IMAGE_NAME:-quay.io/open-horizon/exchange-ubi}"
export EXCHANGE_IMAGE_TAG="${EXCHANGE_IMAGE_TAG:-testing}"

# Logging functions
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_debug() {
    echo "[DEBUG] $*"
}

# Rollback function
rollback_deployment() {
    log_error "Rolling back deployment..."
    
    # Stop and remove containers
    if command -v docker &>/dev/null; then
        log_info "Stopping Open Horizon containers..."
        docker ps -a --filter "name=exchange-api" --filter "name=css-api" \
                     --filter "name=agbot" --filter "name=mongo" \
                     --format "{{.Names}}" | xargs -r docker stop 2>/dev/null || true
        docker ps -a --filter "name=exchange-api" --filter "name=css-api" \
                     --filter "name=agbot" --filter "name=mongo" \
                     --format "{{.Names}}" | xargs -r docker rm 2>/dev/null || true
    fi
    
    # Clean up credential files
    rm -f /root/mycreds.env /root/root-*.env /root/ibm-admin.env \
          /root/myorg-*.env "$DEPLOY_OUTPUT" "$ROLLBACK_MARKER"
    
    log_info "Rollback complete"
}

# Trap errors and perform rollback
trap 'if [ -f "$ROLLBACK_MARKER" ]; then rollback_deployment; fi' ERR

# Discover hub IP
log_info "Discovering hub IP address..."
HUB_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
if [ -z "$HUB_IP" ]; then
    log_error "Could not discover hub IP address"
    exit 1
fi

log_info "Discovered HUB_IP=${HUB_IP}"
export HUB_IP
export HZN_LISTEN_IP="$HUB_IP"

# Clean up any existing docker-compose installations
log_info "Cleaning up existing docker-compose installations..."
rm -f /usr/bin/docker-compose /usr/local/bin/docker-compose

# Mark deployment as started (for rollback)
touch "$ROLLBACK_MARKER"

# Deploy Open Horizon management hub
log_info "Deploying Open Horizon management hub..."
log_info "Using image versions: CSS=${CSS_IMAGE_TAG}, MongoDB=${MONGO_IMAGE_TAG}, Exchange=${EXCHANGE_IMAGE_TAG}"

if ! curl -sSL https://raw.githubusercontent.com/open-horizon/devops/master/mgmt-hub/deploy-mgmt-hub.sh | bash -s -- 2>&1 | tee "$DEPLOY_OUTPUT"; then
    log_error "deploy-mgmt-hub.sh failed"
    exit 1
fi

# Validate deploy output exists and is not empty
if [ ! -s "$DEPLOY_OUTPUT" ]; then
    log_error "Deploy output file is missing or empty"
    exit 1
fi

log_info "Extracting credentials from deployment output..."

# Helper function to extract and validate credentials
extract_credential() {
    local pattern="$1"
    local var_name="$2"
    local credential_file="$3"
    
    log_debug "Extracting $var_name using pattern: $pattern"
    
    local org_id=$(grep -A 1 "$pattern" "$DEPLOY_OUTPUT" | grep "export HZN_ORG_ID=" | head -1 | cut -d'=' -f2 | tr -d '"')
    local auth=$(grep -A 2 "$pattern" "$DEPLOY_OUTPUT" | grep "export HZN_EXCHANGE_USER_AUTH=" | head -1 | cut -d'=' -f2 | tr -d '"')
    
    if [ -z "$org_id" ] || [ -z "$auth" ]; then
        log_error "Failed to extract $var_name credentials (pattern: $pattern)"
        log_debug "ORG_ID='$org_id', AUTH='$auth'"
        return 1
    fi
    
    cat > "$credential_file" <<EOF
export HZN_ORG_ID="$org_id"
export HZN_EXCHANGE_USER_AUTH="$auth"
EOF
    
    log_debug "✓ $var_name credentials written to $credential_file"
    return 0
}

# Extract primary credentials (required)
log_info "Extracting primary credentials..."
HZN_ORG_ID=$(grep "export HZN_ORG_ID=" "$DEPLOY_OUTPUT" | tail -1 | cut -d'=' -f2 | tr -d '"')
HZN_EXCHANGE_USER_AUTH=$(grep "export HZN_EXCHANGE_USER_AUTH=" "$DEPLOY_OUTPUT" | tail -1 | cut -d'=' -f2 | tr -d '"')

if [ -z "$HZN_ORG_ID" ] || [ -z "$HZN_EXCHANGE_USER_AUTH" ]; then
    log_error "Failed to extract primary credentials from deploy-mgmt-hub.sh output"
    log_error "Deploy output preview:"
    tail -50 "$DEPLOY_OUTPUT" >&2
    exit 1
fi

cat > /root/mycreds.env <<EOF
export HZN_ORG_ID="$HZN_ORG_ID"
export HZN_EXCHANGE_USER_AUTH="$HZN_EXCHANGE_USER_AUTH"
EOF
log_info "✓ Primary credentials written to /root/mycreds.env"

# Extract additional credential sets (best effort, warn on failure)
log_info "Extracting additional credential sets..."
CRED_ERRORS=0

extract_credential "EXCHANGE_ROOT_PW=" "root/root" "/root/root-root.env" || ((CRED_ERRORS++))
extract_credential "EXCHANGE_HUB_ADMIN_PW=" "root/hubadmin" "/root/root-hubadmin.env" || ((CRED_ERRORS++))
extract_credential "EXCHANGE_SYSTEM_ADMIN_PW=" "IBM/admin" "/root/ibm-admin.env" || ((CRED_ERRORS++))
extract_credential "EXCHANGE_USER_ADMIN_PW=" "myorg/admin" "/root/myorg-admin.env" || ((CRED_ERRORS++))
extract_credential "HZN_DEVICE_TOKEN=" "myorg/node1" "/root/myorg-node1.env" || ((CRED_ERRORS++))

if [ "$CRED_ERRORS" -gt 0 ]; then
    log_error "Warning: Failed to extract $CRED_ERRORS additional credential set(s)"
    log_error "This may indicate upstream script output format changes"
else
    log_info "✓ All additional credential files written"
fi

# Exchange is already available if deployment completed and credentials were extracted.
# Continue with dependent service health checks.
# Wait for CSS to be healthy
log_info "Waiting for CSS to be ready (timeout: ${SERVICE_TIMEOUT}0s)..."
for i in $(seq 1 "$SERVICE_TIMEOUT"); do
    if docker ps --filter "name=css-api" --filter "health=healthy" | grep -q css-api; then
        log_info "✓ CSS is ready"
        break
    fi
    if [ "$i" -eq "$SERVICE_TIMEOUT" ]; then
        log_error "CSS failed to become healthy after $((SERVICE_TIMEOUT * 10))s"
        log_error "Container status:"
        docker ps -a --filter "name=css-api" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >&2
        log_error "Recent logs:"
        docker logs css-api 2>&1 | tail -50 >&2
        log_error "Health check logs:"
        docker inspect css-api --format='{{json .State.Health}}' 2>&1 >&2
        exit 1
    fi
    sleep 10
done

# Wait for AgBot to be healthy
log_info "Waiting for AgBot to be ready (timeout: ${SERVICE_TIMEOUT}0s)..."
for i in $(seq 1 "$SERVICE_TIMEOUT"); do
    if docker ps --filter "name=agbot" --filter "health=healthy" | grep -q agbot; then
        log_info "✓ AgBot is ready"
        break
    fi
    if [ "$i" -eq "$SERVICE_TIMEOUT" ]; then
        log_error "AgBot failed to become healthy after $((SERVICE_TIMEOUT * 10))s"
        log_error "Container status:"
        docker ps -a --filter "name=agbot" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >&2
        log_error "Recent logs:"
        docker logs agbot 2>&1 | tail -50 >&2
        log_error "Health check logs:"
        docker inspect agbot --format='{{json .State.Health}}' 2>&1 >&2
        exit 1
    fi
    sleep 10
done

# Deployment successful - remove rollback marker
rm -f "$ROLLBACK_MARKER"

log_info "✓ All hub services running and healthy"
log_info "Deployment complete"