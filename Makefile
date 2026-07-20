# The Open Horizon organization ID namespace where you will be publishing files
export HZN_ORG_ID ?= myorg

# Blessed Samples configuration
# NOTE: EXPOSE_REGISTRY_PORT no longer maps to a Vagrant forwarded_port.
# Instead, use 'make port-forward' to expose hub services on localhost after provisioning.
export EXPOSE_REGISTRY_PORT ?= false

VMNAME := agent1

# Which system configuration to be provisioned
export SYSTEM_CONFIGURATION ?= unicycle

# Configuration parameters
export NUM_AGENTS ?= 1
export MEMORY ?= 2048
export DISK_SIZE ?= 20

# Multipass Ubuntu cloud image to use
export MULTIPASS_IMAGE ?= 22.04

# Hub IP is discovered after provisioning and stored in mycreds.env
export HUB_IP ?=

# Detect Operating System running Make
OS := $(shell uname -s)

# Map system configurations to parameters
ifeq ($(SYSTEM_CONFIGURATION),unicycle)
    NUM_AGENTS := 1
    MEMORY := 2048
    DISK_SIZE := 20
else ifeq ($(SYSTEM_CONFIGURATION),bicycle)
    NUM_AGENTS := 3
    MEMORY := 2048
    DISK_SIZE := 20
else ifeq ($(SYSTEM_CONFIGURATION),car)
    NUM_AGENTS := 5
    MEMORY := 2048
    DISK_SIZE := 20
else ifeq ($(SYSTEM_CONFIGURATION),semi)
    NUM_AGENTS := 7
    MEMORY := 2048
    DISK_SIZE := 20
endif

default: status

check:
	@echo "Checking required tools..."
	@if ! command -v multipass >/dev/null 2>&1; then \
		echo "ERROR: 'multipass' not found. Install from https://multipass.run"; \
	else \
		echo "  ✓ multipass: $$(multipass version | head -1)"; \
	fi
	@if ! command -v jq >/dev/null 2>&1; then \
		echo "ERROR: 'jq' not found. Install with: sudo apt-get install jq  (Linux) or brew install jq  (macOS)"; \
	else \
		echo "  ✓ jq: $$(jq --version)"; \
	fi
	@echo ""
	@echo "=====================     ============================================="
	@echo "ENVIRONMENT VARIABLES     VALUES"
	@echo "=====================     ============================================="
	@echo "SYSTEM_CONFIGURATION      ${SYSTEM_CONFIGURATION}"
	@echo "NUM_AGENTS                ${NUM_AGENTS}"
	@echo "MEMORY                    ${MEMORY}"
	@echo "DISK_SIZE                 ${DISK_SIZE}"
	@echo "MULTIPASS_IMAGE           ${MULTIPASS_IMAGE}"
	@echo "HUB_IP                    ${HUB_IP}"
	@echo "HZN_ORG_ID                ${HZN_ORG_ID}"
	@echo "OS                        ${OS}"
	@echo "=====================     ============================================="
	@echo ""

# Detect host IP address (cross-platform)
detect-host-ip:
ifeq ($(OS),Darwin)
	@IFACE=$$(route -n get default 2>/dev/null | grep interface | awk '{print $$2}'); \
	if [ -n "$$IFACE" ]; then \
		IP=$$(ifconfig $$IFACE 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $$2}' | head -1); \
		if [ -n "$$IP" ]; then \
			echo "$$IP"; \
		else \
			echo "ERROR: Could not detect IP for interface $$IFACE" >&2; \
			exit 1; \
		fi; \
	else \
		echo "ERROR: Could not detect default network interface" >&2; \
		exit 1; \
	fi
else
	@IP=$$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+'); \
	if [ -z "$$IP" ]; then \
		IP=$$(hostname -I 2>/dev/null | awk '{print $$1}'); \
	fi; \
	if [ -n "$$IP" ] && [ "$$IP" != "127.0.0.1" ]; then \
		echo "$$IP"; \
	else \
		echo "ERROR: Could not detect host IP address" >&2; \
		exit 1; \
	fi
endif

# Display detected host IP for verification
check-host-ip:
	@echo "Detected host IP address: $$($(MAKE) -s detect-host-ip)"

# Generate agent-install-external.env with host IP
agent-config-external:
	@echo "Generating agent-install-external.env..."
	@HOST_IP=$$($(MAKE) -s detect-host-ip); \
	if [ -z "$$HOST_IP" ]; then \
		echo "ERROR: Failed to detect host IP"; \
		exit 1; \
	fi; \
	echo "Using host IP: $$HOST_IP"; \
	echo "export HZN_EXCHANGE_URL=http://$$HOST_IP:3090/v1" > agent-install-external.env; \
	echo "export HZN_FSS_CSSURL=http://$$HOST_IP:9443/" >> agent-install-external.env; \
	echo "export HZN_AGBOT_URL=http://$$HOST_IP:3111" >> agent-install-external.env; \
	echo "export HZN_FDO_SVC_URL=http://$$HOST_IP:9008/api" >> agent-install-external.env; \
	chmod 644 agent-install-external.env; \
	echo "✓ Created agent-install-external.env with host IP $$HOST_IP"

# Generate agent-install-internal.env with hub VM IP
agent-config-internal:
	@echo "Generating agent-install-internal.env..."
	@if [ ! -f mycreds.env ]; then \
		echo "ERROR: mycreds.env not found. Run 'make up-hub' first."; \
		exit 1; \
	fi; \
	. ./mycreds.env; \
	if [ -z "$$HUB_IP" ]; then \
		echo "ERROR: HUB_IP missing from mycreds.env. Re-run 'make up-hub'."; \
		exit 1; \
	fi; \
	echo "Using hub IP: $$HUB_IP"; \
	echo "export HZN_EXCHANGE_URL=http://$$HUB_IP:3090/v1" > agent-install-internal.env; \
	echo "export HZN_FSS_CSSURL=http://$$HUB_IP:9443/" >> agent-install-internal.env; \
	echo "export HZN_AGBOT_URL=http://$$HUB_IP:3111" >> agent-install-internal.env; \
	echo "export HZN_FDO_SVC_URL=http://$$HUB_IP:9008/api" >> agent-install-internal.env; \
	chmod 644 agent-install-internal.env; \
	echo "✓ Created agent-install-internal.env with hub IP $$HUB_IP"

# Generate both agent configuration files
generate-agent-configs: agent-config-external agent-config-internal
	@echo ""
	@echo "Agent configuration files generated successfully!"
	@echo ""
	@echo "Usage:"
	@echo "  - agent-install-external.env: For agents connecting from the host machine"
	@echo "  - agent-install-internal.env: For agents connecting from within VMs"
	@echo ""
	@echo "To use: export \$$(cat agent-install-external.env)"

init: up-hub up

up-hub:
	@echo "Launching hub VM via Multipass (this takes ~20-40 minutes)..."
	@multipass launch --name hub --cpus 2 --memory 4G --disk 50G \
		--cloud-init cloud-init/hub.yaml $(MULTIPASS_IMAGE)
	@echo "Hub VM launched. Waiting for IP address..."
	@HUB_IP=""; \
	for i in $$(seq 1 10); do \
		HUB_IP=$$(multipass info hub --format json 2>/dev/null | jq -r '.info.hub.ipv4[0] // empty' 2>/dev/null); \
		if [ -n "$$HUB_IP" ] && [ "$$HUB_IP" != "null" ]; then \
			echo "✓ Hub IP: $$HUB_IP"; \
			break; \
		fi; \
		echo "  Waiting for IP... (attempt $$i/10)"; \
		sleep 5; \
	done; \
	if [ -z "$$HUB_IP" ] || [ "$$HUB_IP" = "null" ]; then \
		echo "ERROR: Could not discover hub VM IP after 10 attempts."; \
		exit 1; \
	fi; \
	echo "Extracting Open Horizon credentials from hub VM..."; \
	multipass exec hub -- bash -c 'for i in $$(seq 1 30); do [ -f /root/mycreds.env ] && cat /root/mycreds.env && exit 0; sleep 10; done; echo "ERROR: /root/mycreds.env not found after 5 minutes" >&2; exit 1' > mycreds.env; \
	if [ $$? -ne 0 ]; then \
		echo "ERROR: Failed to extract credentials. Hub provisioning may have failed."; \
		echo "Check hub logs: make connect-hub"; \
		exit 1; \
	fi; \
	echo "export HUB_IP=\"$$HUB_IP\"" >> mycreds.env; \
	if ! grep -q "HZN_ORG_ID" mycreds.env; then \
		echo "ERROR: HZN_ORG_ID missing from mycreds.env"; \
		exit 1; \
	fi; \
	if ! grep -q "HZN_EXCHANGE_USER_AUTH" mycreds.env; then \
		echo "ERROR: HZN_EXCHANGE_USER_AUTH missing from mycreds.env"; \
		exit 1; \
	fi; \
	echo "✓ Hub provisioning complete. Credentials saved to mycreds.env."

up:
	@if [ ! -f mycreds.env ]; then \
		echo "ERROR: mycreds.env not found. Run 'make up-hub' first."; \
		exit 1; \
	fi
	@. ./mycreds.env; \
	if [ -z "$$HUB_IP" ]; then \
		echo "ERROR: HUB_IP missing from mycreds.env. Re-run 'make up-hub'."; \
		exit 1; \
	fi; \
	echo "Launching $(NUM_AGENTS) agent VM(s) via Multipass..."; \
	PIDS=""; \
	for i in $$(seq 1 $(NUM_AGENTS)); do \
		export AGENT_NUM=$$i; \
		export HUB_IP=$$HUB_IP; \
		export HZN_ORG_ID=$$HZN_ORG_ID; \
		export HZN_EXCHANGE_USER_AUTH=$$HZN_EXCHANGE_USER_AUTH; \
		AGENT_CLOUD_INIT="/tmp/agent$$i-cloud-init.yaml"; \
		envsubst < cloud-init/agent.yaml.template > $$AGENT_CLOUD_INIT; \
		echo "  Starting agent$$i..."; \
		multipass launch --name agent$$i \
			--cpus 1 \
			--memory $(MEMORY)M \
			--disk $(DISK_SIZE)G \
			--cloud-init $$AGENT_CLOUD_INIT \
			$(MULTIPASS_IMAGE) & \
		PIDS="$$PIDS $$!"; \
	done; \
	echo "Waiting for all agent VMs to finish provisioning..."; \
	FAILED=0; \
	for PID in $$PIDS; do \
		wait $$PID || FAILED=1; \
	done; \
	if [ $$FAILED -ne 0 ]; then \
		echo "ERROR: One or more agent VMs failed to provision."; \
		exit 1; \
	fi; \
	echo "✓ All agent VMs provisioned."

connect-hub:
	@multipass shell hub

connect:
	@multipass shell $(VMNAME)

status:
	@multipass list

status-hub:
	@multipass list | grep -E "^(Name|hub)" || echo "Hub VM not found."

down: destroy destroy-hub clean

clean:
	@rm -f mycreds.env summary.txt agent-install-external.env agent-install-internal.env
	@rm -f /tmp/agent*-cloud-init.yaml
	@echo "✓ Generated files cleaned."

destroy:
	@echo "Destroying agent VMs..."
	@for i in $$(seq 1 $(NUM_AGENTS)); do \
		if multipass list | grep -q "^agent$$i "; then \
			echo "  Deleting agent$$i..."; \
			multipass delete agent$$i; \
		fi; \
	done; \
	multipass purge; \
	echo "✓ Agent VMs destroyed."

destroy-hub:
	@echo "Destroying hub VM..."
	@if multipass list | grep -q "^hub "; then \
		multipass delete hub; \
		multipass purge; \
		echo "✓ Hub VM destroyed."; \
	else \
		echo "Hub VM not found; nothing to destroy."; \
	fi

browse:
ifeq ($(OS),Darwin)
	@open http://127.0.0.1:8123
else
	@xdg-open http://127.0.0.1:8123
endif

# ---------------------------------------------------------------------------
# Port Forwarding (exposes hub services on localhost via SSH tunnels)
# Port-forwards: Exchange(3090), AgBot(3111), FDO(9008), CSS(9443)
# Previously EXPOSE_REGISTRY_PORT used a Vagrant forwarded_port; now use
# 'make port-forward' instead. Set EXPOSE_REGISTRY_PORT=true to also forward
# the local registry (port 5000).
# ---------------------------------------------------------------------------

port-forward:
	@if [ ! -f mycreds.env ]; then \
		echo "ERROR: mycreds.env not found. Run 'make up-hub' first."; \
		exit 1; \
	fi
	@echo "Starting port-forward tunnels to hub services..."
	@. ./mycreds.env; \
	EXTRA_PORT=""; \
	if [ "$(EXPOSE_REGISTRY_PORT)" = "true" ]; then \
		EXTRA_PORT="-L 5000:localhost:5000"; \
	fi; \
	multipass exec hub -- sudo bash -c '\
		which socat >/dev/null 2>&1 || apt-get install -q -y socat; \
		for port in 3090 3111 9008 9443 '"$$([ "$(EXPOSE_REGISTRY_PORT)" = "true" ] && echo 5000)"'; do \
			[ -z "$$port" ] && continue; \
			socat TCP-LISTEN:$$port,fork,reuseaddr TCP:127.0.0.1:$$port & \
		done' 2>/dev/null & \
	echo "$$!" > /tmp/port-forward.pid
	@echo "✓ Port-forward started (PID: $$(cat /tmp/port-forward.pid))"
	@echo "  Exchange:  http://localhost:3090"
	@echo "  AgBot:     http://localhost:3111"
	@echo "  FDO:       http://localhost:9008"
	@echo "  CSS:       http://localhost:9443"

stop-port-forward:
	@if [ -f /tmp/port-forward.pid ]; then \
		kill $$(cat /tmp/port-forward.pid) 2>/dev/null || true; \
		rm -f /tmp/port-forward.pid; \
		echo "✓ Port-forward stopped."; \
	else \
		echo "No port-forward PID file found; nothing to stop."; \
	fi

# ---------------------------------------------------------------------------
# Blessed Samples targets
# ---------------------------------------------------------------------------

# Manually trigger the blessed samples build pipeline on the hub VM
build-blessed-samples:
	@if ! multipass list 2>/dev/null | grep -q "^hub "; then \
		echo "ERROR: Hub VM is not running. Run 'make up-hub' first."; \
		exit 1; \
	fi
	@echo "Transferring build script to hub VM..."
	@multipass transfer scripts/build-blessed-samples.sh hub:/tmp/build-blessed-samples.sh
	@multipass exec hub -- chmod +x /tmp/build-blessed-samples.sh
	@if [ -f blessedSamples.txt ]; then \
		multipass transfer blessedSamples.txt hub:/tmp/blessedSamples.txt; \
	else \
		echo "WARNING: blessedSamples.txt not found; running with empty list."; \
		multipass exec hub -- touch /tmp/blessedSamples.txt; \
	fi
	@. ./mycreds.env; \
	multipass exec hub -- bash -c "\
		BLESSED_SAMPLES_FILE=/tmp/blessedSamples.txt \
		HUB_IP=$$HUB_IP \
		REGISTRY_URL=$$HUB_IP:5000 \
		BLESSED_SAMPLES_CREDENTIALS=/root/mycreds.env \
		/tmp/build-blessed-samples.sh /tmp/blessedSamples.txt"

# List services configured in blessedSamples.txt (host-side, no SSH needed)
list-blessed-samples:
	@if [ -f blessedSamples.txt ]; then \
		echo "Services in blessedSamples.txt:"; \
		grep -v '^#' blessedSamples.txt | grep -v '^[[:space:]]*$$' || echo "(no entries)"; \
	else \
		echo "blessedSamples.txt not found. Create one to enable blessed samples."; \
	fi

# Check whether the local container registry on the hub VM is running
registry-status:
	@if ! multipass list 2>/dev/null | grep -q "^hub "; then \
		echo "Hub VM is not running."; \
	else \
		multipass exec hub -- docker ps --filter name=registry --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'; \
	fi

# List images in the local registry catalog
registry-catalog:
	@if ! multipass list 2>/dev/null | grep -q "^hub "; then \
		echo "Hub VM is not running."; \
	else \
		multipass exec hub -- bash -c "curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool 2>/dev/null || curl -s http://localhost:5000/v2/_catalog"; \
	fi

# Print the latest blessed samples build log (host-visible copy)
blessed-samples-logs:
	@if [ -f blessed-samples-build-latest.log ]; then \
		cat blessed-samples-build-latest.log; \
	else \
		echo "No log found. Run 'make build-blessed-samples' first."; \
	fi

# Clean blessed samples assets from hub VM (cloned repos, logs, optionally Exchange services)
# Set DRY_RUN=true to preview what would be deleted without actually deleting.
clean-blessed-samples:
	@echo "Cleaning blessed samples assets..."
	@if multipass list 2>/dev/null | grep -q "^hub "; then \
		if [ "$(DRY_RUN)" = "true" ]; then \
			echo "[DRY RUN] Would remove /tmp/blessed-samples/"; \
			echo "[DRY RUN] Would remove /var/log/blessed-samples-build-*.log"; \
			echo "[DRY RUN] Would remove local registry images (if any)"; \
		else \
			multipass exec hub -- bash -c "\
				rm -rf /tmp/blessed-samples/ && \
				rm -f /var/log/blessed-samples-build-*.log && \
				echo '✓ Cloned repos and logs removed'"; \
		fi; \
	else \
		echo "Hub VM is not running; skipping VM-side cleanup."; \
	fi
	@if [ -f blessed-samples-build-latest.log ]; then rm -f blessed-samples-build-latest.log; echo "✓ Local log removed"; fi
	@echo "✓ Blessed samples cleanup complete"

.PHONY: default check init up-hub up status down destroy browse connect clean \
        connect-hub status-hub destroy-hub \
        detect-host-ip check-host-ip \
        agent-config-external agent-config-internal generate-agent-configs \
        port-forward stop-port-forward \
        build-blessed-samples list-blessed-samples registry-status registry-catalog \
        blessed-samples-logs clean-blessed-samples
