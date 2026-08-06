#!/bin/bash
# Install and register Open Horizon agent on agent VM
# This script is executed by the Makefile after cloud-init completes
# and credentials have been copied from the hub VM.
#
# Usage: install-agent.sh <agent_number> <hub_ip>

set -e

AGENT_NUM=${1:-1}
HUB_IP=${2}

if [ -z "$HUB_IP" ]; then
    echo "ERROR: HUB_IP not provided"
    echo "Usage: $0 <agent_number> <hub_ip>"
    exit 1
fi

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

log_info "Installing Open Horizon agent on agent${AGENT_NUM}..."
log_info "Hub IP: ${HUB_IP}"

# Verify credential files exist
log_info "Verifying credential files..."
if [ ! -f /root/mycreds.env ]; then
    log_error "mycreds.env not found in /root/"
    log_error "Credentials must be copied before running this script"
    exit 1
fi

# Source credentials
source /root/mycreds.env

if [ -z "$HZN_ORG_ID" ] || [ -z "$HZN_EXCHANGE_USER_AUTH" ]; then
    log_error "HZN_ORG_ID or HZN_EXCHANGE_USER_AUTH not set in mycreds.env"
    exit 1
fi

log_info "Using credentials: HZN_ORG_ID=${HZN_ORG_ID}"

# Write agent install config
log_info "Writing agent install configuration..."
touch /root/agent-install.crt
cat > /root/agent-install.cfg <<EOF
HZN_ORG_ID=${HZN_ORG_ID}
HZN_EXCHANGE_USER_AUTH=${HZN_EXCHANGE_USER_AUTH}
HZN_EXCHANGE_URL=http://${HUB_IP}:3090/v1
HZN_FSS_CSSURL=http://${HUB_IP}:9443/
HZN_AGBOT_URL=http://${HUB_IP}:3111
HZN_FDO_SVC_URL=http://${HUB_IP}:9008/api
EOF

# Export environment variables for agent installation
export HZN_ORG_ID
export HZN_EXCHANGE_USER_AUTH
export HZN_EXCHANGE_URL="http://${HUB_IP}:3090/v1"
export HZN_FSS_CSSURL="http://${HUB_IP}:9443/"
export HZN_AGBOT_URL="http://${HUB_IP}:3111"
export HZN_FDO_SVC_URL="http://${HUB_IP}:9008/api"

# Install Open Horizon agent
log_info "Installing Open Horizon agent (this takes ~5-10 minutes)..."
if ! curl -sSL https://raw.githubusercontent.com/open-horizon/anax/refs/heads/master/agent-install/agent-install.sh \
    | bash -s -- -i anax: -k /root/agent-install.cfg -c css: \
        -p IBM/pattern-ibm.helloworld -w '*' -T 120; then
    log_error "Agent installation failed"
    exit 1
fi

# Wait for agent to be running
log_info "Waiting for agent to start..."
for i in $(seq 1 30); do
    if hzn node list >/dev/null 2>&1; then
        log_info "✓ Agent is running"
        break
    fi
    if [ "$i" -eq 30 ]; then
        log_error "Agent failed to start after 2.5 minutes"
        exit 1
    fi
    sleep 5
done

# Verify Exchange connectivity
log_info "Verifying Exchange connectivity..."
if ! hzn exchange status >/dev/null 2>&1; then
    log_error "Cannot connect to Exchange at ${HUB_IP}"
    exit 1
fi

log_info "✓ Agent installation complete and healthy (agent${AGENT_NUM})"
log_info "Agent registered with Exchange at ${HUB_IP}:3090"
