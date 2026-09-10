#!/bin/bash
# Install and register Open Horizon agent on agent VM
# This script is executed by the Makefile after cloud-init completes
# and credentials have been copied to /root/mycreds.env.
#
# Usage: install-agent.sh <agent_number> [hub_ip]
#
# Service URLs (HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_AGBOT_URL,
# HZN_FDO_SVC_URL) are taken from /root/mycreds.env when HZN_EXCHANGE_URL is
# set there ('make up-agent', external Exchange). Otherwise they are built
# from <hub_ip> using the standard hub ports ('make up').
#
# Optional settings in /root/mycreds.env:
#   HZN_NODE_PATTERN  Pattern to register with (default: IBM/pattern-ibm.helloworld)
# If /root/agent-install.crt is non-empty it is used as the hub CA certificate.

set -e

AGENT_NUM=${1:-1}
HUB_IP=${2}
CERT_FILE=/root/agent-install.crt

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

# Resolve service URLs: explicit URLs win, otherwise derive from the hub IP
if [ -z "$HZN_EXCHANGE_URL" ]; then
    if [ -z "$HUB_IP" ]; then
        log_error "HUB_IP not provided and HZN_EXCHANGE_URL not set in mycreds.env"
        log_error "Usage: $0 <agent_number> [hub_ip]"
        exit 1
    fi
    HZN_EXCHANGE_URL="http://${HUB_IP}:3090/v1"
    HZN_FSS_CSSURL="http://${HUB_IP}:9443/"
    HZN_AGBOT_URL="http://${HUB_IP}:3111"
    HZN_FDO_SVC_URL="http://${HUB_IP}:9008/api"
fi

if [ -z "$HZN_FSS_CSSURL" ]; then
    log_error "HZN_FSS_CSSURL not set in mycreds.env"
    exit 1
fi

HZN_NODE_PATTERN="${HZN_NODE_PATTERN:-IBM/pattern-ibm.helloworld}"

# Use the hub CA certificate if one was provided; otherwise fetch it from CSS.
# Any HZN_MGMT_HUB_CERT_PATH in mycreds.env refers to the host, so replace it.
if [ -s "$CERT_FILE" ]; then
    HZN_MGMT_HUB_CERT_PATH="$CERT_FILE"
    CERT_ARG="$CERT_FILE"
    log_info "Using hub CA certificate ${CERT_FILE}"
else
    unset HZN_MGMT_HUB_CERT_PATH
    touch "$CERT_FILE"
    CERT_ARG="css:"
fi

log_info "Exchange URL: ${HZN_EXCHANGE_URL}"

# Write agent install config and export the same variables for the installer
log_info "Writing agent install configuration..."
HZN_VARS="HZN_ORG_ID HZN_EXCHANGE_USER_AUTH HZN_EXCHANGE_URL HZN_FSS_CSSURL HZN_AGBOT_URL HZN_FDO_SVC_URL HZN_MGMT_HUB_CERT_PATH"
: > /root/agent-install.cfg
chmod 600 /root/agent-install.cfg
for var in $HZN_VARS; do
    if [ -n "${!var}" ]; then
        echo "${var}=${!var}" >> /root/agent-install.cfg
        export "$var"
    fi
done

# Fail fast if the Exchange is unreachable (any HTTP response counts as reachable)
log_info "Checking Exchange reachability..."
CURL_CERT_ARGS=()
if [ -n "$HZN_MGMT_HUB_CERT_PATH" ]; then
    CURL_CERT_ARGS=(--cacert "$HZN_MGMT_HUB_CERT_PATH")
fi
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${CURL_CERT_ARGS[@]}" \
    "${HZN_EXCHANGE_URL%/}/admin/version" || true)
if [ "$HTTP_CODE" = "000" ]; then
    log_error "Cannot reach Exchange at ${HZN_EXCHANGE_URL} from agent${AGENT_NUM}"
    exit 1
fi

# Install Open Horizon agent
log_info "Installing Open Horizon agent (this takes ~5-10 minutes)..."
if ! curl -sSL https://raw.githubusercontent.com/open-horizon/anax/refs/heads/master/agent-install/agent-install.sh \
    | bash -s -- -i anax: -k /root/agent-install.cfg -c "$CERT_ARG" \
        -p "$HZN_NODE_PATTERN" -w '*' -T 120; then
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
    log_error "Cannot connect to Exchange at ${HZN_EXCHANGE_URL}"
    exit 1
fi

log_info "✓ Agent installation complete and healthy (agent${AGENT_NUM})"
log_info "Agent registered with Exchange at ${HZN_EXCHANGE_URL}"

# Populate shell environment for all users
# Writes /etc/profile.d/open-horizon.sh so HZN_* vars are available in every
# interactive login shell (ubuntu and root) without manual sourcing.
if [ -f /etc/profile.d/open-horizon.sh ]; then
    log_info "✓ /etc/profile.d/open-horizon.sh already exists — skipping write"
else
    echo "# Open Horizon environment variables — written by install-agent.sh" > /etc/profile.d/open-horizon.sh
    for var in $HZN_VARS; do
        if [ -n "${!var}" ]; then
            echo "export ${var}=\"${!var}\"" >> /etc/profile.d/open-horizon.sh
        fi
    done
    chmod 644 /etc/profile.d/open-horizon.sh
    log_info "✓ Open Horizon env vars written to /etc/profile.d/open-horizon.sh"
fi
