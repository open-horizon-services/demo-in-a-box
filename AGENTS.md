# PROJECT KNOWLEDGE BASE

**Generated:** 2026-05-13 (updated for Issue #34)
**Branch:** issue-34

## OVERVIEW
Infrastructure-as-code project for provisioning Open Horizon demo environments using Vagrant + VirtualBox. Creates hub VM (Exchange/CSS/AgBot/FDO/MongoDB) + 1-7 agent VMs with HelloWorld workload. Supports optional `blessedSamples.txt` for automated service builds.

## STRUCTURE
```
demo-in-a-box/
├── configuration/          # Vagrant configs (hub + ERB template)
├── scripts/               # Provisioning scripts
│   └── build-blessed-samples.sh  # Blessed samples build pipeline
├── tests/                 # Test scripts
│   └── test-blessed-samples.sh   # Unit tests for build pipeline
├── .github/               # Issue templates, PR template
├── blessedSamples.txt      # (optional) Services to auto-build on hub
├── BLESSED_SAMPLES.md      # Blessed samples documentation
├── Makefile              # Primary orchestration (init, up, down, connect)
├── README.md             # Architecture diagrams, usage docs
├── MAINTAINERS.md        # Governance
└── LICENSE               # Apache 2.0
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Change VM resources | `Makefile` lines 10-13 | NUM_AGENTS, BASE_IP, MEMORY, DISK_SIZE |
| Modify hub services | `configuration/Vagrantfile.hub` | 4GB RAM, ports 3090/3111/9008/9443/5000 |
| Modify agent provisioning | `configuration/Vagrantfile.template.erb` | ERB template, IP scheme 192.168.56.X0 |
| System topologies | `Makefile` lines 16-36 | unicycle/bicycle/car/semi configs |
| Provision VMs | `make init` | Runs up-hub + up |
| Connect to agent | `make connect VMNAME=agent2` | Default: agent1 |
| Destroy all VMs | `make down` | Runs destroy + destroy-hub + clean |
| Configure blessed samples | `blessedSamples.txt` (project root) | One service entry per line |
| Blessed samples pipeline | `scripts/build-blessed-samples.sh` | Clone→build→push→publish |
| Run blessed samples manually | `make build-blessed-samples` | Hub VM must be running |
| Local registry status | `make registry-status` | Docker Registry v2 at 192.168.56.10:5000 |
| Local registry catalog | `make registry-catalog` | Lists built images |
| Build log | `blessed-samples-build-latest.log` | Host copy, updated after each run |

## CONVENTIONS

### IP Addressing (CRITICAL)
- **Hub:** 192.168.56.10 (fixed)
- **Agents:** 192.168.56.&lt;BASE_IP + (agent_number - 1) * 10&gt;
  - Agent 1: .20
  - Agent 2: .30
  - Agent 3: .40, etc.
- **Local container registry:** 192.168.56.10:5000 (hub VM, Docker Registry v2)

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
- `EXPOSE_REGISTRY_PORT` — Forward registry port 5000 to host (default: false). Set to `true` for external device (Raspberry Pi) access.
- `FAIL_FAST` — Abort blessed samples build on first failure (default: false)
- `USE_LOCAL_REGISTRY` — Rewrite image names in service definitions to use local registry prefix (default: false)

### Generated Files (NOT COMMITTED)
- `Vagrantfile.{unicycle,bicycle,car,semi}` — ERB-generated configs
- `mycreds.env` — HZN_ORG_ID + HZN_EXCHANGE_USER_AUTH extracted from hub
- `summary.txt` — Temp file during hub provisioning
- `blessed-samples-build-latest.log` — Latest blessed samples build log (host copy)

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

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
