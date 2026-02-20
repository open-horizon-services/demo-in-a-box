# PROJECT KNOWLEDGE BASE

**Generated:** 2026-01-31 13:44  
**Commit:** 7a1c4a4  
**Branch:** issue-22

## OVERVIEW
Infrastructure-as-code project for provisioning Open Horizon demo environments using Vagrant + VirtualBox. Creates hub VM (Exchange/CSS/AgBot/FDO/MongoDB) + 1-7 agent VMs with HelloWorld workload.

## STRUCTURE
```
demo-in-a-box/
├── configuration/          # Vagrant configs (hub + ERB template)
├── .github/               # Issue templates, PR template
├── Makefile              # Primary orchestration (init, up, down, connect)
├── README.md             # Architecture diagrams, usage docs
├── MAINTAINERS.md        # Governance
└── LICENSE               # Apache 2.0
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Change VM resources | `Makefile` lines 10-13 | NUM_AGENTS, BASE_IP, MEMORY, DISK_SIZE |
| Modify hub services | `configuration/Vagrantfile.hub` | 4GB RAM, ports 3090/3111/9008/9443 |
| Modify agent provisioning | `configuration/Vagrantfile.template.erb` | ERB template, IP scheme 192.168.56.X0 |
| System topologies | `Makefile` lines 16-36 | unicycle/bicycle/car/semi configs |
| Provision VMs | `make init` | Runs up-hub + up |
| Connect to agent | `make connect VMNAME=agent2` | Default: agent1 |
| Destroy all VMs | `make down` | Runs destroy + destroy-hub + clean |

## CONVENTIONS

### IP Addressing (CRITICAL)
- **Hub:** 192.168.56.10 (fixed)
- **Agents:** 192.168.56.&lt;BASE_IP + (agent_number - 1) * 10&gt;
  - Agent 1: .20
  - Agent 2: .30
  - Agent 3: .40, etc.

### System Configurations
- **unicycle:** 1 agent (default)
- **bicycle:** 3 agents
- **car:** 5 agents (requires 16GB host RAM)
- **semi:** 7 agents (requires 16GB host RAM)

### Environment Variables
Set before `make init`:
- `SYSTEM_CONFIGURATION` — unicycle/bicycle/car/semi (default: unicycle)
- `NUM_AGENTS` — Override agent count
- `BASE_IP` — Starting IP offset (default: 20)
- `MEMORY` — MB per agent VM (default: 2048)
- `DISK_SIZE` — GB per agent VM (default: 20)
- `BOX_VERSION` — Custom box version (default: 1.0.0). When set to a date-like value (e.g., 20250415.01.137), also pins the base Vagrant box version for reproducibility.
- `BLESSED_SAMPLES_FILE` — Filename containing custom sample repository URLs (default: blessedSamples.txt)
- `OH_EXAMPLES_REPO` — Raw URL to the examples repository (required for custom blessed samples)

See [BLESSED_SAMPLES.md](BLESSED_SAMPLES.md) for detailed instructions on using custom blessed samples.

### Generated Files (NOT COMMITTED)
- `Vagrantfile.{unicycle,bicycle,car,semi}` — ERB-generated configs
- `mycreds.env` — HZN_ORG_ID + HZN_EXCHANGE_USER_AUTH extracted from hub
- `summary.txt` — Temp file during hub provisioning

## ANTI-PATTERNS (THIS PROJECT)

### Supply Chain Risks
- Hub provisioning: `curl | bash` from open-horizon/devops master branch (NOT pinned)
- Agent install: `curl | bash` from open-horizon/anax master branch (NOT pinned)
- **Risk:** Scripts can change without notice; prefer commit/tag pinning

### Vagrant Box Versions
- Uses `ubuntu/jammy64` without version constraint by default
- **Mitigation:** When `BOX_VERSION` is set to a date-like value (e.g., `20250415.01.137`), it also pins the base Vagrant box version for reproducibility. Default `BOX_VERSION=1.0.0` uses the BOX_VERSION value (not a date-like version, so no base box pinning).

### Error Suppression
- Makefile targets use `@` prefix (suppress output)
- **Risk:** Errors may be hidden during provisioning

### Hardcoded Network
- Private network 192.168.56.x hardcoded in Vagrantfiles
- Only BASE_IP configurable; network range is not

## UNIQUE STYLES

### ERB Template Generation
Makefile `up` target dynamically generates Vagrantfile from template:
```make
erb hzn_org_id=${HZN_ORG_ID} ... $(VAGRANT_TEMPLATE) > $(VAGRANT_VAGRANTFILE)
```

### Credential Extraction
Hub provisioning outputs credentials via `tee summary.txt`, extracts with `grep | cut`:
```make
grep 'export HZN_ORG_ID=' summary.txt | cut -c16- | tail -n1 > mycreds.env
```

### VAGRANT_VAGRANTFILE Override
Uses `VAGRANT_VAGRANTFILE` env var to switch between configs:
```make
VAGRANT_VAGRANTFILE=$(VAGRANT_HUB) vagrant up
```

### Parallel Provisioning
Agent VMs provisioned concurrently:
```make
VAGRANT_VAGRANTFILE=$(VAGRANT_VAGRANTFILE) vagrant up --parallel
```

## COMMANDS

### Setup
```bash
make check          # Verify env vars + dependencies
make status         # Check Vagrant installation
make init           # Full provision (hub + agents)
```

### Advanced
```bash
export SYSTEM_CONFIGURATION=car
export MEMORY=4096
make init           # Custom config

make up-hub         # Hub only (manual agent setup)
make connect-hub    # SSH to hub
make connect VMNAME=agent3  # SSH to specific agent
```

### Verification (inside agent VM)
```bash
export $(cat agent-install.cfg)
hzn version         # CLI + agent versions match
hzn node list       # Agent running + HelloWorld workload
hzn ex user ls      # Exchange connectivity
hzn ex node ls      # All registered agents
```

### Teardown
```bash
make down           # DESTRUCTIVE: Destroys all VMs + cleans files
```

## NOTES

### Prerequisites
- Debian-based x86_64 host (Ubuntu)
- Required tools: make, vagrant, virtualbox, erb
- Hub VM: 4GB RAM, 50GB disk
- Agent VM: 2GB RAM (default), 20GB disk
- **car/semi:** Requires 16GB host RAM minimum

### Provisioning Time
- unicycle: ~30 minutes
- semi: ~60 minutes

### Port Forwarding
Hub VM forwards to host:
- 3090 (Exchange)
- 3111 (AgBot)
- 9008 (FDO)
- 9443 (CSS)

### No Automated Testing
- No CI/CD, unit tests, or integration tests
- Manual verification only (see Commands → Verification)
- PR template requires grammar linting (manual)

### Documentation Linting
PR template checklist:
- "The Guide has been linted against a language and grammar tool"
- "The Guide is easy to follow and understand for new users"
