# Provisioning Process for `make init`

This document describes in plain English what happens when you run `make init` to provision a unicycle environment (1 hub VM + 1 agent VM).

## Overview

The `make init` command provisions a complete Open Horizon demo environment by:
1. Creating and configuring a hub VM that runs the Open Horizon management services
2. Creating and configuring agent VM(s) that register with the hub and run workloads

For a unicycle configuration, this creates 2 VMs total: 1 hub + 1 agent.

---

## Phase 1: Hub VM Provisioning (`make up-hub`)

### Step 1: Check for Existing Hub VM
- Checks if a hub VM already exists using `multipass info hub`
- If found, stops and deletes it to ensure a clean installation
- Purges any deleted VMs from Multipass

### Step 2: Launch Hub VM
- Creates a new Ubuntu VM named "hub" using Multipass
- VM specifications:
  - 2 CPU cores
  - 4 GB RAM
  - 50 GB disk
  - Ubuntu 22.04 (default)
- Applies cloud-init configuration from `cloud-init/hub.yaml`

### Step 3: Hub Cloud-Init Provisioning
The cloud-init script automatically runs inside the hub VM and:
- Updates package lists
- Installs required packages: Docker, curl, jq, Python 3, net-tools, ufw
- Enables and starts Docker service
- Opens firewall ports for Open Horizon services:
  - 3090 (Exchange API)
  - 3111 (Agreement Bot)
  - 9008 (FDO service)
  - 9443 (Cloud Sync Service)
  - 5000 (Local Docker registry)
- Starts a local Docker registry container on port 5000
- Waits for the registry to become healthy (up to 5 minutes)

### Step 4: Wait for Hub IP Address
- Polls Multipass for the hub VM's IP address (up to 10 attempts, 5 seconds apart)
- The IP is dynamically assigned by Multipass DHCP (e.g., 192.168.64.x on macOS)
- Stores the discovered IP in a variable for later use

### Step 5: Wait for Cloud-Init Completion
- Checks for the existence of `/var/lib/cloud/instance/boot-finished` file
- Polls every 10 seconds for up to 10 minutes
- This ensures Docker and the registry are fully configured before proceeding

### Step 6: Install Open Horizon Exchange
- Transfers `scripts/install-exchange.sh` to the hub VM
- Executes the installation script, which:
  
  **6a. Discovers Hub IP**
  - Determines the hub's internal IP address
  - Sets environment variables for the deployment
  
  **6b. Deploys Management Hub**
  - Downloads and runs the official `deploy-mgmt-hub.sh` script from GitHub
  - Deploys Docker containers with pinned versions:
    - Exchange API (version: testing)
    - Cloud Sync Service/CSS (version: testing)
    - MongoDB (version: 4.0.6)
    - Agreement Bot
    - FDO service
  - Captures all deployment output to `/tmp/deploy-output.txt`
  
  **6c. Extracts Credentials**
  - Parses the deployment output to extract authentication credentials
  - Creates primary credential file: `/root/mycreds.env` with:
    - `HZN_ORG_ID` (organization ID, typically "myorg")
    - `HZN_EXCHANGE_USER_AUTH` (admin username:password)
  - Creates additional credential files for different user roles:
    - `/root/root-root.env` (root/root credentials)
    - `/root/root-hubadmin.env` (root/hubadmin credentials)
    - `/root/ibm-admin.env` (IBM/admin credentials)
    - `/root/myorg-admin.env` (myorg/admin credentials)
    - `/root/myorg-node1.env` (device registration token)
  - Validates that primary credentials were successfully extracted
  
  **6d. Health Checks**
  - Waits for CSS container to report healthy status (up to 10 minutes)
  - Waits for AgBot container to report healthy status (up to 10 minutes)
  - Monitors Docker container health checks
  - Logs detailed error information if any service fails to start
  
  **6e. Rollback on Failure**
  - If any step fails, automatically rolls back the deployment
  - Stops and removes all Open Horizon containers
  - Cleans up credential files
  - Exits with error status

### Step 7: Copy Credentials to Host
- Copies `/root/mycreds.env` from the hub VM to the host machine
- Appends the hub IP address to the local `mycreds.env` file
- Validates that required credentials (HZN_ORG_ID and HZN_EXCHANGE_USER_AUTH) are present

### Step 8: Hub Provisioning Complete
- Hub VM is now running with all Open Horizon management services
- Credentials are available on the host for agent registration
- Local Docker registry is ready to store container images

**Total time for hub provisioning: ~20-40 minutes**

---

## Phase 2: Agent VM Provisioning (`make up`)

### Step 1: Validate Prerequisites
- Checks that `mycreds.env` exists on the host
- Loads credentials and hub IP from the file
- Verifies that HUB_IP is set

### Step 2: Check for Existing Agent VMs
- For each agent (1 agent in unicycle configuration):
  - Checks if the agent VM already exists
  - If found, stops and deletes it to ensure a clean installation
- Purges any deleted VMs from Multipass

### Step 3: Render Agent Cloud-Init Files
- For each agent VM to be created:
  - Reads the template from `cloud-init/agent.yaml.template`
  - Substitutes environment variables using `envsubst`:
    - `${HUB_IP}` - Hub VM's IP address
    - `${HZN_ORG_ID}` - Organization ID from credentials
    - `${HZN_EXCHANGE_USER_AUTH}` - Admin credentials
    - `${AGENT_NUM}` - Agent number (1 for unicycle)
  - Writes the rendered cloud-init file to `.bob/tmp/agent1-cloud-init.yaml`

### Step 4: Launch Agent VMs in Parallel
- Creates agent VM(s) concurrently using Multipass
- For unicycle: launches 1 agent VM named "agent1"
- VM specifications per agent:
  - 1 CPU core
  - 2 GB RAM (default, configurable)
  - 20 GB disk (default, configurable)
  - Ubuntu 22.04 (default)
- Applies the rendered cloud-init configuration
- Launches run in background processes for parallel provisioning

### Step 5: Agent Cloud-Init Provisioning
The cloud-init script automatically runs inside each agent VM and:

**5a. Install Base Packages**
- Updates package lists
- Installs: Docker, curl, jq, net-tools
- Enables and starts Docker service

**5b. Configure Docker for Insecure Registry**
- Creates or updates `/etc/docker/daemon.json`
- Adds the hub's registry (`<HUB_IP>:5000`) to insecure-registries list
- This allows pulling images from the hub's local registry without TLS
- Restarts Docker to apply the configuration
- Waits for Docker to become healthy (up to 1 minute)

**5c. Write Agent Configuration**
- Creates `/root/agent-install.cfg` with:
  - Organization ID
  - Exchange credentials
  - Exchange URL: `http://<HUB_IP>:3090/v1`
  - CSS URL: `http://<HUB_IP>:9443/`
  - AgBot URL: `http://<HUB_IP>:3111`
  - FDO service URL: `http://<HUB_IP>:9008/api`
- Creates empty certificate file: `/root/agent-install.crt`

**5d. Install Open Horizon Agent**
- Downloads the official agent installation script from GitHub
- Runs the script with parameters:
  - `-i anax:` - Install the Anax agent
  - `-k /root/agent-install.cfg` - Use the configuration file
  - `-c css:` - Pull agent software from CSS
  - `-p IBM/pattern-ibm.helloworld` - Register with HelloWorld pattern
  - `-w '*'` - Accept any workload
  - `-T 120` - 120 second timeout for registration
- The script:
  - Installs the Horizon CLI and agent packages
  - Registers the node with the Exchange
  - Starts the Horizon agent service
  - Deploys the HelloWorld workload container

**5e. Verify Agent Health**
- Waits for the agent to start (up to 2.5 minutes)
- Checks that `hzn node list` command works
- Verifies connectivity to the Exchange
- Confirms the agent is registered and running

### Step 6: Wait for All Agents
- Waits for all background agent provisioning processes to complete
- Checks exit status of each process
- Reports error if any agent failed to provision

### Step 7: Agent Provisioning Complete
- All agent VMs are running with Open Horizon agents installed
- Agents are registered with the hub and running the HelloWorld workload
- Agents can pull container images from the hub's local registry

**Total time for agent provisioning: ~10-20 minutes per agent**

---

## Final State

After `make init` completes successfully:

### Hub VM ("hub")
- Running Ubuntu 22.04
- Docker installed and running
- Open Horizon management services running in containers:
  - Exchange API (port 3090)
  - Cloud Sync Service (port 9443)
  - Agreement Bot (port 3111)
  - FDO service (port 9008)
  - MongoDB (internal)
- Local Docker registry (port 5000)
- Credentials stored in `/root/*.env` files

### Agent VM ("agent1")
- Running Ubuntu 22.04
- Docker installed and configured for hub registry
- Open Horizon agent installed and running
- Registered with hub Exchange
- HelloWorld workload container running
- Configuration stored in `/root/agent-install.cfg`

### Host Machine
- `mycreds.env` file with hub credentials and IP
- Temporary cloud-init files in `.bob/tmp/`
- Can connect to VMs using `make connect-hub` or `make connect`
- Can access hub services via port forwarding with `make port-forward`

---

## Total Provisioning Time

**Unicycle configuration (1 hub + 1 agent): ~30-45 minutes**

Breakdown:
- Hub VM creation: ~2 minutes
- Hub cloud-init: ~2-5 minutes
- Exchange deployment: ~20-40 minutes
- Agent VM creation: ~2 minutes
- Agent cloud-init + agent install: ~10-20 minutes

Times may vary based on:
- Host machine performance
- Network speed (downloading packages and container images)
- Whether packages/images are cached

---

## Error Handling

The provisioning process includes several safety mechanisms:

1. **Rerunnable**: `make init` can be re-run after interruption
2. **Clean slate**: Existing VMs are deleted before creating new ones
3. **Validation**: Credentials and IPs are validated at each step
4. **Health checks**: Services must report healthy before proceeding
5. **Rollback**: Hub deployment automatically rolls back on failure
6. **Timeouts**: Each waiting step has a maximum timeout
7. **Detailed logging**: Errors include container logs and status information

If provisioning fails, check:
- `make status` - VM status
- `make connect-hub` - Shell into hub to check logs
- `make connect` - Shell into agent to check logs
- Container logs: `docker logs <container-name>`
