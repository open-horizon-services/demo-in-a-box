# demo-in-a-box

This is a set of materials designed to allow anyone to create a portable set of computers that will demonstrate most aspects of Open Horizon and OH-delivered applications in a single location. It should contain a Bill of Materials, initial configuration, setup instructions, and examples of how to demonstrate most features.

## Pre-requisites

### Required (All Installation Methods)

* `make`
* `vagrant`
* `virtualbox`
* `erb` (Ruby's ERB template processor)

### Optional (For Custom Box - Recommended)

* `packer` - For building optimized base box (see Installation section)

### System Requirements

* **Architecture:** `x86_64`
* **OS:** Debian-based (Ubuntu recommended)
* **RAM:** 8GB minimum (16GB recommended for car/semi configurations)
* **Disk:** 20GB minimum (80GB for semi with standard boxes, 30GB with custom box)

## System Configurations

The `x86_64` architecture host can be configured one of four ways:

### Unicycle Configuration

Two VMs, with the primary running the Exchange and an Agent using 1/2 of the available resources, and the remaining VM running an Agent also using 1/2 of the available resources.

```mermaid
graph TD
    subgraph "Unicycle Configuration"
    
    subgraph "Hub VM (4GB RAM)"
    Exchange["Exchange Service"]
    CSS["Sync Service (CSS)"]
    AgBot["Agreement Bot"]
    FDO["FDO Service"]
    MongoDB["MongoDB"]
    HubAgent["Agent"]
    end
    
    subgraph "Agent VM (2GB RAM)"
    Agent1["Agent"]
    HelloWorld1["Hello World Workload"]
    end
    
    Exchange --> CSS
    Exchange --> AgBot
    Exchange --> FDO
    Exchange --> MongoDB
    
    Agent1 --> Exchange
    HubAgent --> Exchange
    
    classDef hub fill:#f9f,stroke:#333,stroke-width:2px
    classDef agent fill:#bbf,stroke:#333,stroke-width:1px
    class Exchange,CSS,AgBot,FDO,MongoDB,HubAgent hub
    class Agent1,HelloWorld1 agent
    
    end
    
    IP1["Hub VM IP: 192.168.56.10"] --> Exchange
    IP2["Agent VM IP: 192.168.56.20"] --> Agent1
```

### Bicycle Configuration

Three VMs, with the primary running the Exchange and an Agent using 1/2 of the available resources, and the remaining two running Agents each using 1/4 of the available resources.

```mermaid
graph TD
    subgraph "Bicycle Configuration"
    
    subgraph "Hub VM (4GB RAM)"
    Exchange["Exchange Service"]
    CSS["Sync Service (CSS)"]
    AgBot["Agreement Bot"]
    FDO["FDO Service"]
    MongoDB["MongoDB"]
    HubAgent["Agent"]
    end
    
    subgraph "Agent VM 1 (2GB RAM)"
    Agent1["Agent"]
    HelloWorld1["Hello World Workload"]
    end
    
    subgraph "Agent VM 2 (2GB RAM)"
    Agent2["Agent"]
    HelloWorld2["Hello World Workload"]
    end
    
    Exchange --> CSS
    Exchange --> AgBot
    Exchange --> FDO
    Exchange --> MongoDB
    
    Agent1 --> Exchange
    Agent2 --> Exchange
    HubAgent --> Exchange
    
    classDef hub fill:#f9f,stroke:#333,stroke-width:2px
    classDef agent fill:#bbf,stroke:#333,stroke-width:1px
    class Exchange,CSS,AgBot,FDO,MongoDB,HubAgent hub
    class Agent1,HelloWorld1,Agent2,HelloWorld2 agent
    
    end
    
    IP1["Hub VM IP: 192.168.56.10"] --> Exchange
    IP2["Agent VM 1 IP: 192.168.56.20"] --> Agent1
    IP3["Agent VM 2 IP: 192.168.56.30"] --> Agent2
```

### Car Configuration

Five VMs (recommended for the 16GB RAM configuration only), with the primary running the Exchange and an Agent using 1/4 of the available resources, and the remaining four running Agents each using 1/8 of the available resources.

```mermaid
graph TD
    subgraph "Car Configuration"
    
    subgraph "Hub VM (4GB RAM)"
    Exchange["Exchange Service"]
    CSS["Sync Service (CSS)"]
    AgBot["Agreement Bot"]
    FDO["FDO Service"]
    MongoDB["MongoDB"]
    HubAgent["Agent"]
    end
    
    subgraph "Agent VM 1 (2GB RAM)"
    Agent1["Agent"]
    HelloWorld1["Hello World Workload"]
    end
    
    subgraph "Agent VM 2 (2GB RAM)"
    Agent2["Agent"]
    HelloWorld2["Hello World Workload"]
    end
    
    subgraph "Agent VM 3 (2GB RAM)"
    Agent3["Agent"]
    HelloWorld3["Hello World Workload"]
    end
    
    subgraph "Agent VM 4 (2GB RAM)"
    Agent4["Agent"]
    HelloWorld4["Hello World Workload"]
    end
    
    Exchange --> CSS
    Exchange --> AgBot
    Exchange --> FDO
    Exchange --> MongoDB
    
    Agent1 --> Exchange
    Agent2 --> Exchange
    Agent3 --> Exchange
    Agent4 --> Exchange
    HubAgent --> Exchange
    
    classDef hub fill:#f9f,stroke:#333,stroke-width:2px
    classDef agent fill:#bbf,stroke:#333,stroke-width:1px
    class Exchange,CSS,AgBot,FDO,MongoDB,HubAgent hub
    class Agent1,HelloWorld1,Agent2,HelloWorld2,Agent3,HelloWorld3,Agent4,HelloWorld4 agent
    
    end
    
    IP1["Hub VM IP: 192.168.56.10"] --> Exchange
    IP2["Agent VM 1 IP: 192.168.56.20"] --> Agent1
    IP3["Agent VM 2 IP: 192.168.56.30"] --> Agent2
    IP4["Agent VM 3 IP: 192.168.56.40"] --> Agent3
    IP5["Agent VM 4 IP: 192.168.56.50"] --> Agent4
```

### Semi Configuration

Seven VMs (recommended for the 16GB RAM configuration only), with the primary running the Exchange and an Agent using 1/4 of the available resources, and the remaining six running Agents each using 1/8 of the available resources.

```mermaid
graph LR
    subgraph "Semi Configuration"
    
    Hub["Hub VM\n192.168.56.10\n4GB RAM\nExchange + Agent"]
    
    Agent1["Agent VM 1\n192.168.56.20\n2GB RAM"]
    Agent2["Agent VM 2\n192.168.56.30\n2GB RAM"]
    Agent3["Agent VM 3\n192.168.56.40\n2GB RAM"]
    Agent4["Agent VM 4\n192.168.56.50\n2GB RAM"]
    Agent5["Agent VM 5\n192.168.56.60\n2GB RAM"]
    Agent6["Agent VM 6\n192.168.56.70\n2GB RAM"]
    
    Hub --- Agent1
    Hub --- Agent2
    Hub --- Agent3
    Hub --- Agent4
    Hub --- Agent5
    Hub --- Agent6
    
    classDef hub fill:#f9f,stroke:#333,stroke-width:2px
    classDef agent fill:#bbf,stroke:#333,stroke-width:1px
    class Hub hub
    class Agent1,Agent2,Agent3,Agent4,Agent5,Agent6 agent
    
    end
```

### Network Configuration

The following diagram shows how the VMs are connected in the network:

```mermaid
graph TD
    subgraph "Network Configuration"
    
    Host["Host Machine"]
    
    subgraph "VirtualBox Network"
    Hub["Hub VM\n192.168.56.10"]
    Agent1["Agent VM 1\n192.168.56.20"]
    Agent2["Agent VM 2\n192.168.56.30"]
    AgentN["Agent VM N\n192.168.56.X0"]
    end
    
    Host --- Hub
    Host --- Agent1
    Host --- Agent2
    Host --- AgentN
    
    Hub -- "Port 3090 (Exchange)" --- Agent1
    Hub -- "Port 3090 (Exchange)" --- Agent2
    Hub -- "Port 3090 (Exchange)" --- AgentN
    
    Hub -- "Port 9443 (CSS)" --- Agent1
    Hub -- "Port 9443 (CSS)" --- Agent2
    Hub -- "Port 9443 (CSS)" --- AgentN
    
    Hub -- "Port 3111 (AgBot)" --- Agent1
    Hub -- "Port 3111 (AgBot)" --- Agent2
    Hub -- "Port 3111 (AgBot)" --- AgentN
    
    Hub -- "Port 9008 (FDO)" --- Agent1
    Hub -- "Port 9008 (FDO)" --- Agent2
    Hub -- "Port 9008 (FDO)" --- AgentN
    
    classDef host fill:#bfb,stroke:#333,stroke-width:2px
    classDef hub fill:#f9f,stroke:#333,stroke-width:2px
    classDef agent fill:#bbf,stroke:#333,stroke-width:1px
    class Host host
    class Hub hub
    class Agent1,Agent2,AgentN agent
    
    end
```

### Legend

- **Pink/Purple Nodes**: Hub VM components (Exchange, CSS, AgBot, FDO, MongoDB)
- **Blue Nodes**: Agent VM components
- **Green Node**: Host machine

## Installation

Clone the repository, then `cd` into the repo folder.

### Standard Installation (Recommended)

For optimized provisioning with faster VM creation and reduced bandwidth usage, first build the custom base box:

1. **Install Packer** (if not already installed):
   ```bash
   # macOS
   brew tap hashicorp/tap
   brew install hashicorp/tap/packer
   
   # Linux (Ubuntu/Debian)
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install packer
   ```

2. **Build and add custom box** (one-time, ~10-15 minutes):
   ```bash
   make rebuild-box
   ```

3. **Verify and provision**:
   ```bash
   make check
   make init
   ```

**Benefits of custom box:**
- ⏱️ 5-10 minutes faster per VM (packages pre-installed)
- 📦 60% less disk usage (linked clones)
- 🌐 Reduced network bandwidth during provisioning
- ✅ More reliable (tested package versions)

See [BUILD_BOX.md](BUILD_BOX.md) for detailed custom box documentation.

### Quick Start (Without Custom Box)

If you prefer to use the standard Ubuntu base box without customization:

```bash
export BOX_NAME=ubuntu/jammy64
make check
make init
```

Running `make init` will provision the default system configuration ("unicycle"). To use any other configuration, first `export SYSTEM_CONFIGURATION=<system configuration string>` where `<system configuration string>` is one of "unicycle", "bicycle", "car", or "semi" _without the quotes_. Installation time varies:
- **With custom box:** 15-20 minutes (unicycle) to 30-40 minutes (semi)
- **Without custom box:** 30 minutes (unicycle) to 60 minutes (semi)

### Advanced Configuration

The system can be further customized by setting the following environment variables:

#### Resource Configuration
* `NUM_AGENTS` - Number of agent VMs to create (default: 1)
* `MEMORY` - Memory allocation per agent VM in MB (default: 2048)
* `DISK_SIZE` - Disk size per agent VM in GB (default: 20)

#### Network Configuration
* `NETWORK_PREFIX` - Network prefix for all VMs (default: 192.168.56)
* `HUB_IP` - Hub VM IP address (default: ${NETWORK_PREFIX}.10)
* `BASE_IP` - Starting IP final octet for agent VMs (default: 20)
  - Agent IPs calculated as: ${NETWORK_PREFIX}.${BASE_IP + (agent_number-1)*10}
  - Agent 1: ${NETWORK_PREFIX}.20, Agent 2: ${NETWORK_PREFIX}.30, etc.

#### Custom Resource Example
```shell
export SYSTEM_CONFIGURATION=custom
export NUM_AGENTS=4
export MEMORY=4096
export DISK_SIZE=40
make init
```

#### Custom Network Example
```shell
# Use different network to avoid conflicts
export NETWORK_PREFIX=10.0.10
export HUB_IP=10.0.10.5
export BASE_IP=30
make init

# Result:
# Hub:    10.0.10.5
# Agent1: 10.0.10.30
# Agent2: 10.0.10.40
# Agent3: 10.0.10.50
```

If you only want the hub running in a VM with an agent, and not a separate agent in a VM, just run `make up-hub` instead of `make init`, but make sure you copy over the credentials from the "mycreds.env" file on the host.

Running `make down` will de-provision the system and cannot be undone. Make sure you really want to do this.

## Usage

Run `make connect` to SSH to the first agent VM in _unicycle_ configuration. For all other configurations, specify the "VMNAME" as an argument: `make connect VMNAME=agent3`. The credentials can be set by running `export $(cat agent-install.cfg)`. To test that the installation is configured and working, run the following commands:

```shell
hzn version
```

This should return matching version numbers for both the CLI and the agent.

```shell
hzn node list
```

This will show the agent is running and the HelloWorld sample workload is configured and running.

```shell
hzn agreement list
```

This will show active agreements between the agent and the AgBot, confirming workload deployment.

```shell
hzn ex user ls
```

This will confirm that the CLI can connect to the exchange in the hub's VM, and that the credentials are valid.

```shell
hzn ex node ls
```

This will show all of the agents registered with the exchange in the hub VM.

```shell
exit
```

Will disconnect from the agent VM and end the SSH session.

```shell
make down
```

Will remove all of the VMs and delete temporary files.

## Advanced details

The system uses a single ERB template (`configuration/Vagrantfile.template.erb`) to generate the Vagrant configuration for all agent VMs. The template supports dynamic configuration through environment variables and maintains consistent IP addressing and resource allocation across all VMs.

### IP Addressing Scheme

Agent VMs are assigned IP addresses following the pattern: `192.168.56.<base_ip + (agent_number - 1) * 10>`. For example:
- Agent 1: 192.168.56.20
- Agent 2: 192.168.56.30
- Agent 3: 192.168.56.40
And so on...

### Resource Allocation

Each agent VM is configured with:
- Memory: 2048MB (2GB) by default
- Disk: 20GB by default
- CPU: 1 core (default VirtualBox setting)

These values can be customized using the environment variables described in the Advanced Configuration section.
