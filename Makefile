# The Open Horizon organization ID namespace where you will be publishing files
export HZN_ORG_ID ?= myorg

VMNAME :=

# Which system configuration to be provisioned
export SYSTEM_CONFIGURATION ?= unicycle

# Configuration parameters for the ERB template
export NUM_AGENTS ?= 1
export BASE_IP ?= 20
export MEMORY ?= 2048
export DISK_SIZE ?= 20

export NETWORK_PREFIX ?= 192.168.56
export HUB_IP ?= $(NETWORK_PREFIX).10

# Configurable project default OS (change this to set new default OS)
DEFAULT_OS_TYPE ?= ubuntu-22

# Blessed samples configuration (optional)
# Set BLESSED_SAMPLES_FILE to use custom samples during hub provisioning
# Set OH_EXAMPLES_REPO to the raw URL of the examples repository
export BLESSED_SAMPLES_FILE ?= blessedSamples.txt
export OH_EXAMPLES_REPO ?=

# Per-VM OS selection (enables mixed environments)
export HUB_OS_TYPE ?= $(DEFAULT_OS_TYPE)
export AGENT_OS_TYPE ?= $(DEFAULT_OS_TYPE)

# Box version (shared) - also used for base Vagrant box version pinning
export BOX_VERSION ?= 1.0.0

# Map system configurations to parameters
ifeq ($(SYSTEM_CONFIGURATION),unicycle)
    NUM_AGENTS := 1
    BASE_IP := 20
    MEMORY := 2048
    DISK_SIZE := 20
else ifeq ($(SYSTEM_CONFIGURATION),bicycle)
    NUM_AGENTS := 3
    BASE_IP := 20
    MEMORY := 2048
    DISK_SIZE := 20
else ifeq ($(SYSTEM_CONFIGURATION),car)
    NUM_AGENTS := 5
    BASE_IP := 20
    MEMORY := 2048
    DISK_SIZE := 20
else ifeq ($(SYSTEM_CONFIGURATION),semi)
    NUM_AGENTS := 7
    BASE_IP := 20
    MEMORY := 2048
    DISK_SIZE := 20
endif

# Helper function to get box config for OS type
# Usage: $(call get_box_name,ubuntu-22)
get_box_name = $(if $(filter ubuntu-22,$(1)),demo-in-a-box/ubuntu-jammy-horizon,$(if $(filter ubuntu-24,$(1)),demo-in-a-box/ubuntu-noble-horizon,$(if $(filter fedora-41,$(1)),demo-in-a-box/fedora-41-horizon,$(error Unknown OS_TYPE: $(1). Valid: ubuntu-22, ubuntu-24, fedora-41))))
get_packer_template = $(if $(filter ubuntu-22,$(1)),packer/ubuntu-22-horizon.pkr.hcl,$(if $(filter ubuntu-24,$(1)),packer/ubuntu-24-horizon.pkr.hcl,$(if $(filter fedora-41,$(1)),packer/fedora-41-horizon.pkr.hcl,$(error Unknown OS_TYPE: $(1)))))
get_box_file = $(if $(filter ubuntu-22,$(1)),ubuntu-jammy-horizon-virtualbox-$(BOX_VERSION).box,$(if $(filter ubuntu-24,$(1)),ubuntu-noble-horizon-virtualbox-$(BOX_VERSION).box,$(if $(filter fedora-41,$(1)),fedora-41-horizon-virtualbox-$(BOX_VERSION).box,$(error Unknown OS_TYPE: $(1)))))
# Helper function to get base box with optional version pinning
# Only adds version if BOX_VERSION looks like a date (e.g., 20250415.01.137)
get_base_box_version = $(if $(filter 20%,$(BOX_VERSION)),/$(BOX_VERSION),)
get_base_box = $(if $(filter ubuntu-22,$(1)),ubuntu/jammy64$(call get_base_box_version),$(if $(filter ubuntu-24,$(1)),bento/ubuntu-24.04$(call get_base_box_version),$(if $(filter fedora-41,$(1)),bento/fedora-41$(call get_base_box_version),$(error Unknown OS_TYPE: $(1)))))

# Calculate hub and agent box names
export HUB_BOX_NAME := $(call get_box_name,$(HUB_OS_TYPE))
HUB_PACKER_TEMPLATE := $(call get_packer_template,$(HUB_OS_TYPE))
HUB_BOX_FILE := $(call get_box_file,$(HUB_OS_TYPE))
HUB_BASE_BOX := $(call get_base_box,$(HUB_OS_TYPE))

export AGENT_BOX_NAME := $(call get_box_name,$(AGENT_OS_TYPE))
AGENT_PACKER_TEMPLATE := $(call get_packer_template,$(AGENT_OS_TYPE))
AGENT_BOX_FILE := $(call get_box_file,$(AGENT_OS_TYPE))
AGENT_BASE_BOX := $(call get_base_box,$(AGENT_OS_TYPE))

# Legacy BOX_NAME for backward compatibility
export BOX_NAME ?= $(HUB_BOX_NAME)

export VAGRANT_HUB := "./configuration/Vagrantfile.hub"
export VAGRANT_VAGRANTFILE := "./configuration/Vagrantfile.${SYSTEM_CONFIGURATION}"
export VAGRANT_TEMPLATE := "./configuration/Vagrantfile.template.erb"

# Detect Operating System running Make
OS := $(shell uname -s)

default: status

check:
	@echo "=====================     ============================================="
	@echo "ENVIRONMENT VARIABLES     VALUES"
	@echo "=====================     ============================================="
	@echo "DEFAULT_OS_TYPE           ${DEFAULT_OS_TYPE}"
	@echo "HUB_OS_TYPE               ${HUB_OS_TYPE}"
	@echo "AGENT_OS_TYPE             ${AGENT_OS_TYPE}"
	@echo "HUB_BOX_NAME              ${HUB_BOX_NAME}"
	@echo "AGENT_BOX_NAME            ${AGENT_BOX_NAME}"
	@echo "BOX_VERSION               ${BOX_VERSION}"
	@echo "SYSTEM_CONFIGURATION      ${SYSTEM_CONFIGURATION}"
	@echo "NUM_AGENTS                ${NUM_AGENTS}"
	@echo "BASE_IP                   ${BASE_IP}"
	@echo "MEMORY                    ${MEMORY}"
	@echo "DISK_SIZE                 ${DISK_SIZE}"
	@echo "NETWORK_PREFIX            ${NETWORK_PREFIX}"
	@echo "HUB_IP                    ${HUB_IP}"
	@echo "VAGRANT_HUB               ${VAGRANT_HUB}"
	@echo "VAGRANT_TEMPLATE          ${VAGRANT_TEMPLATE}"
	@echo "VAGRANT_VAGRANTFILE       ${VAGRANT_VAGRANTFILE}"
	@echo "HZN_ORG_ID                ${HZN_ORG_ID}"
	@echo "BLESSED_SAMPLES_FILE      ${BLESSED_SAMPLES_FILE}"
	@echo "OH_EXAMPLES_REPO          ${OH_EXAMPLES_REPO}"
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
	@echo "Using hub IP: $(HUB_IP)"; \
	echo "export HZN_EXCHANGE_URL=http://$(HUB_IP):3090/v1" > agent-install-internal.env; \
	echo "export HZN_FSS_CSSURL=http://$(HUB_IP):9443/" >> agent-install-internal.env; \
	echo "export HZN_AGBOT_URL=http://$(HUB_IP):3111" >> agent-install-internal.env; \
	echo "export HZN_FDO_SVC_URL=http://$(HUB_IP):9008/api" >> agent-install-internal.env; \
	chmod 644 agent-install-internal.env; \
	echo "✓ Created agent-install-internal.env with hub IP $(HUB_IP)"

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
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant up
	@test -f mycreds.env || { echo "ERROR: Credentials file not generated. Hub provisioning may have failed."; exit 1; }
	@grep -q "HZN_ORG_ID" mycreds.env || { echo "ERROR: HZN_ORG_ID missing from mycreds.env"; exit 1; }
	@grep -q "HZN_EXCHANGE_USER_AUTH" mycreds.env || { echo "ERROR: HZN_EXCHANGE_USER_AUTH missing from mycreds.env"; exit 1; }
	@echo "Hub provisioning complete. Credentials validated."

up: 
	$(eval include ./mycreds.env)
	@erb hzn_org_id=${HZN_ORG_ID} hzn_exchange_user_auth=${HZN_EXCHANGE_USER_AUTH} num_agents=$(NUM_AGENTS) base_ip=$(BASE_IP) memory=$(MEMORY) disk_size=$(DISK_SIZE) $(VAGRANT_TEMPLATE) > $(VAGRANT_VAGRANTFILE)
	@VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant up --parallel

connect-hub:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant ssh

connect:
	@if [ -f $(VAGRANT_VAGRANTFILE) ]; then \
		VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant ssh $(VMNAME); \
	else \
		echo "Error: Vagrantfile not found at $(VAGRANT_VAGRANTFILE). Run 'make up' first to generate it."; \
		exit 1; \
	fi

status:
	@if [ -f $(VAGRANT_VAGRANTFILE) ]; then \
		VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant status; \
	else \
		echo "Error: Vagrantfile not found at $(VAGRANT_VAGRANTFILE). Run 'make up' first to generate it."; \
		exit 1; \
	fi

status-hub:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant status

down: destroy destroy-hub clean

clean:
	@if [ -f $(VAGRANT_VAGRANTFILE) ]; then rm $(VAGRANT_VAGRANTFILE); fi
	@if [ -f summary.txt ]; then rm summary.txt; fi
	@if [ -f mycreds.env ]; then rm mycreds.env; fi
	@rm -f *-horizon-virtualbox-*.box
	@vagrant global-status --prune

destroy:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant destroy -f

destroy-hub:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant destroy -f

browse:
ifeq ($(OS),Darwin)
	@open http://127.0.0.1:8123
else
	@xdg-open http://127.0.0.1:8123
endif

# Build hub box using Vagrant-based approach (more reliable than Packer)
build-hub-box:
	@echo "Building hub custom box ($(HUB_OS_TYPE))..."
	./build-custom-box.sh $(HUB_OS_TYPE) $(BOX_VERSION)

# Build agent box
build-agent-box:
	@echo "Building agent custom box ($(AGENT_OS_TYPE))..."
	./build-custom-box.sh $(AGENT_OS_TYPE) $(BOX_VERSION)

# Build both (skip duplicates if same OS)
build-boxes:
ifeq ($(HUB_OS_TYPE),$(AGENT_OS_TYPE))
	@echo "========================================="
	@echo "Building boxes for: $(HUB_OS_TYPE)"
	@echo "Total boxes to build: 1"
	@echo "Estimated total time: 10-15 minutes"
	@echo "========================================="
	@echo ""
	@$(MAKE) build-hub-box
else
	@echo "========================================="
	@echo "Building boxes for mixed environment:"
	@echo "  Hub:    $(HUB_OS_TYPE)"
	@echo "  Agents: $(AGENT_OS_TYPE)"
	@echo "Total boxes to build: 2"
	@echo "Estimated total time: 20-30 minutes"
	@echo "========================================="
	@echo ""
	@echo "[1/2] Building hub box ($(HUB_OS_TYPE))..."
	@echo ""
	@$(MAKE) build-hub-box
	@echo ""
	@echo "[2/2] Building agent box ($(AGENT_OS_TYPE))..."
	@echo ""
	@$(MAKE) build-agent-box
endif
	@echo ""
	@echo "========================================="
	@echo "✓ All boxes built successfully!"
	@echo "========================================="

# Add hub box
add-hub-box:
	@echo "Adding hub custom box to Vagrant..."
	@vagrant box add --name $(HUB_BOX_NAME) $(HUB_BOX_FILE) --force

# Add agent box
add-agent-box:
	@echo "Adding agent custom box to Vagrant..."
	@vagrant box add --name $(AGENT_BOX_NAME) $(AGENT_BOX_FILE) --force

# Add both (skip duplicates if same OS)
add-boxes:
ifeq ($(HUB_OS_TYPE),$(AGENT_OS_TYPE))
	@echo "Adding box to Vagrant..."
	@$(MAKE) add-hub-box
	@echo "✓ Box added successfully"
else
	@echo "Adding boxes to Vagrant..."
	@$(MAKE) add-hub-box
	@$(MAKE) add-agent-box
	@echo "✓ All boxes added successfully"
endif

# Remove hub box
remove-hub-box:
	@echo "Removing hub custom box from Vagrant..."
	@vagrant box remove $(HUB_BOX_NAME) || true

# Remove agent box
remove-agent-box:
	@echo "Removing agent custom box from Vagrant..."
	@vagrant box remove $(AGENT_BOX_NAME) || true

# Remove both
remove-boxes:
ifeq ($(HUB_OS_TYPE),$(AGENT_OS_TYPE))
	@$(MAKE) remove-hub-box
else
	@$(MAKE) remove-hub-box
	@$(MAKE) remove-agent-box
endif

# Clean build artifacts (but preserve .box files - only 'make clean' deletes those)
clean-box:
	@echo "Cleaning Packer build artifacts..."
	@rm -rf packer_output
	@rm -f box-metadata.json

# Rebuild everything
rebuild-boxes: remove-boxes clean-box build-boxes add-boxes

# Convenience targets for single-OS builds
build-ubuntu-22:
	@HUB_OS_TYPE=ubuntu-22 AGENT_OS_TYPE=ubuntu-22 $(MAKE) build-boxes

build-ubuntu-24:
	@HUB_OS_TYPE=ubuntu-24 AGENT_OS_TYPE=ubuntu-24 $(MAKE) build-boxes

build-fedora-41:
	@HUB_OS_TYPE=fedora-41 AGENT_OS_TYPE=fedora-41 $(MAKE) build-boxes

# Legacy compatibility (keep existing target names)
build-box: build-boxes
add-box: add-boxes
remove-box: remove-boxes
rebuild-box: rebuild-boxes

.PHONY: default check init up-hub up status down destroy browse connect clean \
        connect-hub status-hub destroy-hub \
        build-box build-boxes build-hub-box build-agent-box \
        add-box add-boxes add-hub-box add-agent-box \
        remove-box remove-boxes remove-hub-box remove-agent-box \
        clean-box rebuild-box rebuild-boxes \
        build-ubuntu-22 build-ubuntu-24 build-fedora-41
