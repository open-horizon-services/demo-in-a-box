#!/bin/bash
# Test script to verify that agent VMs have the same credential files as the hub VM
# Usage: ./verify-agent-credentials.sh [agent_number]

AGENT_NUM=${1:-1}
AGENT_NAME="agent${AGENT_NUM}"

echo "Verifying credential files on ${AGENT_NAME}..."
echo ""

# List of expected credential files
CRED_FILES=(
    "mycreds.env"
    "root-root.env"
    "root-hubadmin.env"
    "ibm-admin.env"
    "myorg-admin.env"
    "myorg-node1.env"
)

# Check if agent VM exists
if ! multipass list | grep -q "^${AGENT_NAME} "; then
    echo "ERROR: ${AGENT_NAME} VM not found"
    exit 1
fi

echo "Checking credential files on ${AGENT_NAME}:"
echo "=============================================="

MISSING=0
PRESENT=0

for cred_file in "${CRED_FILES[@]}"; do
    if multipass exec "${AGENT_NAME}" -- sudo bash -c "test -f /root/${cred_file}" 2>/dev/null; then
        echo "✓ /root/${cred_file} exists"
        ((PRESENT++))
        
        # Show first line of file (without revealing sensitive data)
        echo "  Content preview:"
        multipass exec "${AGENT_NAME}" -- sudo head -1 "/root/${cred_file}" 2>/dev/null | sed 's/=.*/=***/' || echo "  (could not read)"
    else
        echo "✗ /root/${cred_file} MISSING"
        ((MISSING++))
    fi
    echo ""
done

echo "=============================================="
echo "Summary: ${PRESENT} present, ${MISSING} missing"
echo ""

if [ $MISSING -gt 0 ]; then
    echo "ERROR: Some credential files are missing on ${AGENT_NAME}"
    exit 1
else
    echo "SUCCESS: All credential files are present on ${AGENT_NAME}"
    exit 0
fi
