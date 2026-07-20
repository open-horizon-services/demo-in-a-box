# PROJECT KNOWLEDGE BASE

**Generated:** 2026-05-13 (updated for Multipass/cloud-init migration)
**Branch:** issue-45

## OVERVIEW
Infrastructure-as-code project for provisioning Open Horizon demo environments using **Multipass + cloud-init** (replaces Vagrant + VirtualBox). Creates hub VM (Exchange/CSS/AgBot/FDO/MongoDB) + 1–7 agent VMs with HelloWorld workload. Supports optional `blessedSamples.txt` for automated service builds.

## STRUCTURE
```
demo-in-a-box/
├── cloud-init/                # Cloud-init configs (replaces configuration/Vagrantfile.*)
│   ├── hub.yaml               # Hub VM provisioning (Docker, deploy-mgmt-hub.sh, registry)
│   └── agent.yaml.template    # Agent VM template (envsubst renders per-agent at launch)
├── scripts/                   # Provisioning scripts
│   └── build-blessed-samples.sh  # Blessed samples build pipeline
├── tests/                     # Test scripts
│   └── test-blessed-samples.sh   # Unit tests for build pipeline
├── .github/                   # Issue templates, PR template
├── blessedSamples.txt          # (optional) Services to auto-build on hub
├── BLESSED_SAMPLES.md          # Blessed samples documentation
├── Makefile                   # Primary orchestration (init, up, down, connect)
├── README.md                  # Architecture diagrams, usage docs
├── MAINTAINERS.md             # Governance
└── LICENSE                    # Apache 2.0
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Change VM resources | `Makefile` — `NUM_AGENTS`, `MEMORY`, `DISK_SIZE` vars | Top of Makefile |
| Modify hub services | `cloud-init/hub.yaml` | 4 GB RAM, ports opened via UFW |
| Modify agent provisioning | `cloud-init/agent.yaml.template` | envsubst template; escape non-substituted `$VAR` as `\$VAR` |
| System topologies | `Makefile` `ifeq ($(SYSTEM_CONFIGURATION),...)` blocks | unicycle/bicycle/car/semi configs |
| Provision VMs | `make init` | Runs up-hub + up |
| Connect to agent | `make connect VMNAME=agent2` | Default: `agent1` |
| Destroy all VMs | `make down` | Runs destroy + destroy-hub + clean |
| Configure blessed samples | `blessedSamples.txt` (project root) | One service entry per line |
| Blessed samples pipeline | `scripts/build-blessed-samples.sh` | Clone→build→push→publish |
| Run blessed samples manually | `make build-blessed-samples` | Transfers script, runs via `multipass exec` |
| Local registry status | `make registry-status` | Docker Registry v2 on hub VM port 5000 |
| Local registry catalog | `make registry-catalog` | Lists built images |
| Build log | `blessed-samples-build-latest.log` | Host copy, updated after each run |

## CONVENTIONS

### IP Addressing (CRITICAL)
- **Hub IP:** Dynamically assigned by Multipass DHCP (e.g., `192.168.64.x` on macOS, `10.118.x.x` on Linux)
- **Discovery:** After `make up-hub`, the hub IP is discovered via `multipass info hub --format json | jq -r '.info.hub.ipv4[0]'`
- **Storage:** Stored as `export HUB_IP=<ip>` in `mycreds.env` on the host
- **Agents:** Receive the hub IP via their rendered cloud-init file at launch time
- **Local container registry:** `<HUB_IP>:5000` (hub VM, Docker Registry v2)
- **NO FIXED IPs:** The old `192.168.56.x` scheme is gone. Never hardcode hub/agent IPs.

### System Configurations
- **unicycle:** 1 agent (default)
- **bicycle:** 3 agents
- **car:** 5 agents (requires 16 GB host RAM)
- **semi:** 7 agents (requires 16 GB host RAM)

### Environment Variables
Set before `make init`:
- `SYSTEM_CONFIGURATION` — unicycle/bicycle/car/semi (default: unicycle)
- `NUM_AGENTS` — Override agent count
- `MEMORY` — MB per agent VM (default: 2048)
- `DISK_SIZE` — GB per agent VM (default: 20)
- `MULTIPASS_IMAGE` — Ubuntu cloud image version (default: 22.04)
- `EXPOSE_REGISTRY_PORT` — Use `make port-forward` instead; this flag now only affects which ports are tunnelled
- `FAIL_FAST` — Abort blessed samples build on first failure (default: false)
- `USE_LOCAL_REGISTRY` — Rewrite image names in service definitions to use local registry prefix (default: false)

**Removed variables (no longer exist):**
- `BOX_VERSION`, `BOX_NAME`, `HUB_BOX_NAME`, `AGENT_BOX_NAME` — box pipeline removed
- `HUB_OS_TYPE`, `AGENT_OS_TYPE`, `DEFAULT_OS_TYPE` — multi-OS not supported in this release
- `BASE_IP`, `NETWORK_PREFIX` — static IP scheme replaced by dynamic Multipass IPs
- `VAGRANT_HUB`, `VAGRANT_VAGRANTFILE`, `VAGRANT_TEMPLATE` — Vagrant removed

### Generated Files (NOT COMMITTED)
- `mycreds.env` — HZN_ORG_ID + HZN_EXCHANGE_USER_AUTH + HUB_IP extracted from hub VM
- `/tmp/agent*-cloud-init.yaml` — Per-agent rendered cloud-init files (temp, cleaned by `make clean`)
- `blessed-samples-build-latest.log` — Latest blessed samples build log (host copy)

## ANTI-PATTERNS (THIS PROJECT)

### Supply Chain Risks
- Hub provisioning: `curl | bash` from open-horizon/devops master branch (NOT pinned)
- Agent install: `curl | bash` from open-horizon/anax master branch (NOT pinned)
- **Risk:** Scripts can change without notice; prefer commit/tag pinning

### Dynamic IPs
- Hub and agent IPs assigned by Multipass DHCP; can change if VMs are deleted and recreated
- **Mitigation:** `make up-hub` always re-discovers and re-writes hub IP into `mycreds.env`

### Error Suppression
- Makefile targets use `@` prefix (suppress output)
- **Risk:** Errors may be hidden during provisioning

### envsubst Escaping
- `cloud-init/agent.yaml.template` uses `${VAR}` for substitution tokens
- Shell variables in runcmd scripts that must NOT be substituted must be escaped as `\$VAR`
- **Risk:** Forgetting to escape a `$VAR` will silently substitute or blank it

## UNIQUE STYLES

### Cloud-Init Template Rendering
Makefile `up` target renders per-agent cloud-init files using `envsubst`:
```make
envsubst < cloud-init/agent.yaml.template > /tmp/agentN-cloud-init.yaml
```

### Credential Extraction
Hub provisioning writes `/root/mycreds.env` inside the VM. Makefile extracts it:
```make
multipass exec hub -- bash -c '...; cat /root/mycreds.env' > mycreds.env
```
Then appends the discovered hub IP:
```make
echo "export HUB_IP=\"$$HUB_IP\"" >> mycreds.env
```

### IP Discovery
After launch, hub IP is polled with retries:
```make
multipass info hub --format json | jq -r '.info.hub.ipv4[0] // empty'
```

### Parallel Agent Provisioning
Agent VMs launched concurrently via background processes:
```make
multipass launch --name agentN ... &
PIDS="$PIDS $!"
wait $PID  # after loop
```

## COMMANDS

### Setup
```bash
make check          # Verify multipass + jq installed
make init           # Full provision (hub + agents)
```

### Advanced
```bash
export SYSTEM_CONFIGURATION=car
export MEMORY=4096
make init           # Custom config

make up-hub         # Hub only (manual agent setup)
make connect-hub    # Shell into hub VM
make connect VMNAME=agent3  # Shell into specific agent
make port-forward   # Expose hub ports on localhost (3090, 3111, 9008, 9443)
```

### Verification (inside agent VM)
```bash
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
- macOS, Linux, or Windows (WSL2) host — x86_64 or arm64
- Required tools: `make`, `multipass` ≥ 1.13, `jq`
- Hub VM: 4 GB RAM, 50 GB disk
- Agent VM: 2 GB RAM (default), 20 GB disk
- **car/semi:** Requires 16 GB host RAM minimum

### Provisioning Time
- unicycle: ~30–45 minutes (cloud-init installs packages on first run)
- semi: ~60–90 minutes

### Port Forwarding
Use `make port-forward` to expose hub services on localhost:
- 3090 (Exchange)
- 3111 (AgBot)
- 9008 (FDO)
- 9443 (CSS)
- 5000 (registry, if `EXPOSE_REGISTRY_PORT=true`)

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
