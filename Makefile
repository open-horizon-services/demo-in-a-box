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
	@echo "SYSTEM_CONFIGURATION      ${SYSTEM_CONFIGURATION}"
	@echo "NUM_AGENTS               ${NUM_AGENTS}"
	@echo "BASE_IP                 ${BASE_IP}"
	@echo "MEMORY                  ${MEMORY}"
	@echo "DISK_SIZE               ${DISK_SIZE}"
	@echo "VAGRANT_HUB             ${VAGRANT_HUB}"
	@echo "VAGRANT_TEMPLATE        ${VAGRANT_TEMPLATE}"
	@echo "VAGRANT_VAGRANTFILE     ${VAGRANT_VAGRANTFILE}"
	@echo "HZN_ORG_ID              ${HZN_ORG_ID}"
	@echo "OS                      ${OS}"
	@echo "=====================     ============================================="
	@echo ""

init: up-hub up

up-hub: 
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant up | tee summary.txt
	@grep 'export HZN_ORG_ID=' summary.txt | cut -c16- | tail -n1 > mycreds.env
	@grep 'export HZN_EXCHANGE_USER_AUTH=' summary.txt | cut -c16- | tail -n1 >>mycreds.env
	@if [ -f summary.txt ]; then rm summary.txt; fi

up: 
	$(eval include ./mycreds.env)
	@erb num_agents=$(NUM_AGENTS) base_ip=$(BASE_IP) memory=$(MEMORY) disk_size=$(DISK_SIZE) $(VAGRANT_TEMPLATE) > $(VAGRANT_VAGRANTFILE)
	@VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant up --parallel

connect-hub:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant ssh

connect:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant ssh $(VMNAME)

status:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant status

status-hub:
	@VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant status

down: destroy destroy-hub clean

clean:
	@if [ -f $(VAGRANT_VAGRANTFILE) ]; then rm $(VAGRANT_VAGRANTFILE); fi
	@if [ -f summary.txt ]; then rm summary.txt; fi
	@if [ -f mycreds.env ]; then rm mycreds.env; fi

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

.PHONY: default check init up-hub up status down destroy browse connect clean connect-hub status-hub destroy-hub