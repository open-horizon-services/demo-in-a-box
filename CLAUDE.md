# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Note on `AGENTS.md`:** Some AI editors (OpenAI Codex, GitHub Copilot agent mode) read `AGENTS.md` as their primary context file. `AGENTS.md` exists in this repo and defers to this file as the canonical technical reference. If you are Claude Code, use this file — `AGENTS.md` is kept as a stub that points here.

## Project Overview

**demo-in-a-box** is an infrastructure-as-code project that provisions Open Horizon demo environments using Vagrant + VirtualBox. It creates a hub VM (running Exchange/CSS/AgBot/FDO/MongoDB) plus 1–7 agent VMs that auto-register and deploy a HelloWorld workload.

There are two distinct subsystems:
1. **Makefile + Vagrant layer** (root): Direct CLI provisioning via `make` targets
2. **MCP server** (`mcp-server/`): TypeScript MCP server exposing the same provisioning as AI-callable tools

## Common Commands

### Vagrant/Make Layer

```bash
make check                          # Verify env vars + tool dependencies
make init                           # Full provision (hub + agents)
make up-hub                         # Hub VM only
make connect VMNAME=agent2          # SSH to a specific agent VM
make connect-hub                    # SSH to hub VM
make down                           # DESTRUCTIVE: destroy all VMs + clean files
make rebuild-boxes                  # Build custom Packer base boxes (one-time setup)
make generate-agent-configs         # Generate agent-install-external.env + agent-install-internal.env
make status                         # Show Vagrant installation info

# MCP Server Metadata Sync (recommended for use with MCP server)
make env-create ENV_NAME=my-env     # Create MCP metadata before provisioning
make env-status ENV_NAME=my-env    # Check MCP metadata status
make env-delete ENV_NAME=my-env     # Delete MCP metadata after destroy
make init-sync ENV_NAME=my-env     # Provision with MCP metadata sync
make destroy-sync ENV_NAME=my-env  # Destroy and remove MCP metadata
```

System configuration and OS are set via environment variables before `make init`:

```bash
export SYSTEM_CONFIGURATION=bicycle   # unicycle|bicycle|car|semi
export HUB_OS_TYPE=ubuntu-22          # ubuntu-22|ubuntu-24|fedora-41
export AGENT_OS_TYPE=fedora-41
export NUM_AGENTS=4                   # override agent count
export MEMORY=4096                    # MB per agent VM
make rebuild-boxes && make init
```

### MCP Server

```bash
cd mcp-server
npm install
npm run build          # Compile TypeScript → dist/
npm start              # Run compiled server (stdio transport)
npm run dev            # Run with tsx (no compile step)
npm test               # Run vitest unit tests
npm run test:watch     # Watch mode
npm run lint           # Type-check without building (tsc --noEmit)
npm run inspect        # Build + launch MCP Inspector at localhost:5173
```

## Architecture

### Makefile Layer

- `Makefile` is the primary orchestrator. Variables at the top define defaults (`NUM_AGENTS`, `BASE_IP`, `MEMORY`, `DISK_SIZE`, `NETWORK_PREFIX`, `HUB_IP`, `HUB_OS_TYPE`, `AGENT_OS_TYPE`, `BOX_VERSION`).
- `configuration/Vagrantfile.hub` — static hub VM config (4GB RAM, port forwards 3090/3111/9008/9443).
- `configuration/Vagrantfile.template.erb` — ERB template dynamically rendered for agent VMs at `make up` time. The Makefile injects variables via `erb key=value ... template > Vagrantfile`.
- `configuration/Vagrantfile.unicycle` — pre-rendered example (do not edit directly; it is generated).
- Agent IPs follow: `192.168.56.<BASE_IP + (agent_number - 1) * 10>`. Hub is always `192.168.56.10`.
- System configs map to agent counts: unicycle=1, bicycle=3, car=5, semi=7.
- `VAGRANT_VAGRANTFILE` env var is used to switch between hub and agent Vagrantfiles without moving files.
- After hub provisioning, credentials are extracted from `summary.txt` into `mycreds.env` via `grep | cut`.

### MCP Server (`mcp-server/src/`)

The server implements stdio MCP transport. Key layers:

| Layer | Path | Purpose |
|-------|------|---------|
| Entry + registration | `index.ts`, `server.ts` | Initializes server, registers 11 tools |
| Environment CRUD | `env/manager.ts` | Creates dirs under `~/.demo-in-a-box/envs/<name>/`, writes `env.json`, symlinks `Makefile` + `configuration/` |
| Config + types | `env/config.ts`, `env/types.ts` | Zod schemas, constants |
| Concurrency | `env/locks.ts` | File-based locks (`env.lock`) + global slot limit (max 2 concurrent vagrant ops) |
| Command execution | `vagrant/executor.ts` | Runs allowlisted make/vagrant commands with sanitization |
| Output parsing | `vagrant/parser.ts`, `vagrant/status.ts` | Parses `--machine-readable` CSV output |
| Operation tracking | `ops/ledger.ts`, `ops/logger.ts` | Persists op metadata (`op-<uuid>.json`) and streaming logs (`op-<uuid>.log`) |
| Tool handlers | `tools/env-*.ts`, `tools/operation-*.ts` | One file per tool (12 tools total); validate input with Zod, call managers/executors |

**Async pattern:** Long-running tools (`env_provision`, `env_deprovision`, snapshot restore) share a single `ops/async-operation.ts` helper — `runAsyncOperation(envName, opsDir, type, fn)` — that manages the lock, global slot, ledger lifecycle, and logger cleanup. Operations flow: `queued → running → succeeded/failed`.

**Security:** Commands go through an allowlist in `vagrant/commands.ts`; `spawn` is called without `shell: true` so local shell metacharacters in arguments are inert. User-supplied commands for `env_exec` have backticks and `$` stripped before being passed to `vagrant ssh -c`.

**REPO_ROOT:** `env/config.ts` derives the repository root from `import.meta.url` (works for both `tsx` dev and compiled `dist/`). Override with `DEMO_IN_A_BOX_REPO_ROOT` env var if the auto-detected path is wrong. The `.vscode/mcp.json` sets this automatically via `${workspaceFolder}`.

**State:** The filesystem is the source of truth. Each environment is isolated under its own directory with `.vagrant/` state, symlinked repo files, and per-environment operation logs.

### Packer Base Boxes (`packer/`)

Packer templates (`ubuntu-22-horizon.pkr.hcl`, `ubuntu-24-horizon.pkr.hcl`, `fedora-41-horizon.pkr.hcl`) pre-bake packages into base boxes to speed provisioning. Corresponding provision scripts are in `packer/scripts/`.

## Key Conventions

- **Generated files** (not committed): `Vagrantfile.{unicycle,bicycle,car,semi}`, `mycreds.env`, `summary.txt`, `agent-install-external.env`, `agent-install-internal.env`, `blessedSamples.txt`
- **Box naming:** `demo-in-a-box/ubuntu-jammy-horizon`, `demo-in-a-box/ubuntu-noble-horizon`, `demo-in-a-box/fedora-41-horizon`
- **BOX_VERSION date detection:** If `BOX_VERSION` starts with `20` (e.g., `20250415.01.137`), it is treated as a date and also pins the base Vagrant box version for reproducibility. Default `1.0.0` does not pin.
- **Testing is manual** — no CI. See `TESTING.md` for test procedures.
- **Documentation PRs** require grammar linting (see `.github/PULL_REQUEST_TEMPLATE.md`).

## Custom Blessed Samples

Place a `blessedSamples.txt` file (one git repo URL per line) in the project root. Each repo needs a `Makefile` with a `publish-only` target. Set `OH_EXAMPLES_REPO` to the raw URL of an examples repo that supports BYO samples, then run `make up-hub`. See `BLESSED_SAMPLES.md` for full details.
