# PROJECT KNOWLEDGE BASE

> **Note:** `AGENTS.md` is read by some AI editors (e.g., OpenAI Codex, GitHub Copilot agent mode) as their primary context file. For **Claude Code**, the canonical source is [`CLAUDE.md`](CLAUDE.md) — refer there for the full, up-to-date technical reference.
>
> The content below is kept intentionally brief. See `CLAUDE.md` for complete architecture, commands, and conventions.

## OVERVIEW

Infrastructure-as-code project for provisioning Open Horizon demo environments using Vagrant + VirtualBox. Creates hub VM (Exchange/CSS/AgBot/FDO/MongoDB) + 1-7 agent VMs with HelloWorld workload.

There are two subsystems:
1. **Makefile + Vagrant layer** (root) — direct CLI provisioning via `make` targets
2. **MCP server** (`mcp-server/`) — TypeScript MCP server exposing the same provisioning as AI-callable tools

## CANONICAL REFERENCE

All architectural details, commands, conventions, and MCP server internals are documented in **[CLAUDE.md](CLAUDE.md)**.

Key topics covered there:
- Common `make` and `npm` commands
- IP addressing scheme and system configuration topologies (unicycle/bicycle/car/semi)
- MCP server layer breakdown (`env/`, `vagrant/`, `ops/`, `tools/`)
- Async operation pattern (`runAsyncOperation`)
- Security model (command allowlist, no `shell: true`, input sanitization)
- Key conventions (generated files, box naming, BOX_VERSION date detection)
- Custom blessed samples setup

## QUICK REFERENCE

```bash
# Vagrant layer
make check && make init         # Verify deps + full provision
make down                       # DESTRUCTIVE: destroy all VMs

# MCP server
cd mcp-server && npm install
npm run build && npm start      # Compile + run
npm test                        # Run unit tests
npm run inspect                 # Interactive browser-based tool tester
```
