# Demo-in-a-Box MCP Server

Model Context Protocol (MCP) server for provisioning and managing Open Horizon demo environments using Vagrant + VirtualBox.

## Overview

This MCP server provides tools to:
- Create isolated demo environments (unicycle/bicycle/car/semi configurations)
- Provision VMs asynchronously with full logging
- Inspect environment status (desired vs observed state)
- Execute commands on running VMs
- Manage SSH connections
- Track operations with detailed logs

## Architecture

- **Transport:** stdio (for local integration with MCP clients)
- **State Management:** Per-environment directories in `~/.demo-in-a-box/envs/<name>/`
- **Concurrency:** File locks + global limit (max 2 concurrent vagrant operations)
- **Async Operations:** Long-running operations return `operation_id` for polling

### Directory Structure

```
~/.demo-in-a-box/
└── envs/
    └── my-unicycle/
        ├── env.json              # Desired configuration
        ├── env.lock              # File lock
        ├── hub/
        │   ├── .vagrant/         # Isolated Vagrant state
        │   ├── Vagrantfile.hub   # Symlink to repo
        │   └── mycreds.env       # Generated credentials
        ├── agents/
        │   ├── .vagrant/
        │   └── Vagrantfile.*     # Generated from template
        └── ops/
            ├── op-<uuid>.json    # Operation metadata
            └── op-<uuid>.log     # Operation logs
```

## Installation

```bash
cd mcp-server
npm install
npm run build
```

## Usage

### Running the Server

```bash
npm start          # Run compiled server (requires npm run build first)
npm run dev        # Run with tsx — no build step, for development
```

The server communicates via stdio using the MCP protocol.

## IDE Integration

The server's location and repository root are resolved automatically from the
compiled file path.  If needed, override with the `DEMO_IN_A_BOX_REPO_ROOT`
environment variable.

### VS Code (v1.99+ with GitHub Copilot or Claude extension)

The repo ships a `.vscode/mcp.json` that VS Code picks up automatically.  Open
the workspace root and VS Code will offer to enable the server.

To configure manually, create `.vscode/mcp.json` in the repo root:

```json
{
  "servers": {
    "demo-in-a-box": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/mcp-server/dist/index.js"],
      "env": {
        "DEMO_IN_A_BOX_REPO_ROOT": "${workspaceFolder}"
      }
    }
  }
}
```

### Cursor

Add to `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` (project-scoped):

```json
{
  "mcpServers": {
    "demo-in-a-box": {
      "command": "node",
      "args": ["/absolute/path/to/demo-in-a-box/mcp-server/dist/index.js"],
      "env": {
        "DEMO_IN_A_BOX_REPO_ROOT": "/absolute/path/to/demo-in-a-box"
      }
    }
  }
}
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`
(macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "demo-in-a-box": {
      "command": "node",
      "args": ["/absolute/path/to/demo-in-a-box/mcp-server/dist/index.js"],
      "env": {
        "DEMO_IN_A_BOX_REPO_ROOT": "/absolute/path/to/demo-in-a-box"
      }
    }
  }
}
```

Restart Claude Desktop after saving the config file.

## Testing the Server

### MCP Inspector (recommended during development)

The official browser-based tool for interactive testing — no AI client needed:

```bash
cd mcp-server
npm run inspect
# Opens http://localhost:5173 with all 12 tools available
```

Browse tools, fill in inputs, and inspect raw JSON responses without spinning
up a full AI client.

### Development test client

```bash
npm run dev   # keep the server running on stdio
```

Then connect any MCP-compatible client (Claude Desktop, Cursor, VS Code) and
interact through natural language.

## Available Tools

### 1. env_create

Create a new demo environment with specified configuration.

**Input:**
```json
{
  "name": "my-demo",
  "system_configuration": "unicycle",
  "overrides": {
    "memory_mb": 4096,
    "disk_gb": 30
  },
  "auto_provision": false
}
```

**System Configurations:**
- `unicycle`: 1 agent VM
- `bicycle`: 3 agent VMs
- `car`: 5 agent VMs
- `semi`: 7 agent VMs

### 2. env_list

List all demo environments.

**Input:**
```json
{
  "filter_status": "optional-filter"
}
```

### 3. env_inspect

Get detailed status of an environment.

**Input:**
```json
{
  "env_name": "my-demo"
}
```

**Returns:**
- Desired configuration
- Observed VM states (hub + agents)
- IP addresses
- Port mappings
- Artifacts (credentials, SSH keys)

### 4. env_provision

Start provisioning VMs (async operation).

**Input:**
```json
{
  "env_name": "my-demo",
  "force_recreate": false
}
```

**Returns:** `operation_id` for tracking progress

**Note:** Provisioning takes 30-60 minutes depending on configuration.

### 5. operation_status

Check status of an async operation.

**Input:**
```json
{
  "operation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Statuses:**
- `queued`: Operation created, waiting to start
- `running`: Currently executing
- `succeeded`: Completed successfully
- `failed`: Completed with errors
- `cancelled`: Cancelled by user

### 6. operation_logs

Retrieve logs from an operation with pagination.

**Input:**
```json
{
  "operation_id": "550e8400-e29b-41d4-a716-446655440000",
  "offset": 0,
  "limit": 1000,
  "tail": false
}
```

### 7. env_ssh_info

Get SSH connection details for a VM.

**Input:**
```json
{
  "env_name": "my-demo",
  "target": "hub"
}
```

**Targets:** `hub`, `agent1`, `agent2`, ..., `agent7`

### 8. env_exec

Execute a command on a VM.

**Input:**
```json
{
  "env_name": "my-demo",
  "target": "hub",
  "command": "hzn version",
  "timeout_ms": 60000
}
```

### 9. env_deprovision

Deprovision (destroy or halt) VMs (async operation).

**Input:**
```json
{
  "env_name": "my-demo",
  "destroy": true,
  "cleanup_files": false
}
```

**Options:**
- `destroy: true` - Destroy VMs completely
- `destroy: false` - Just halt VMs (can restart later)
- `cleanup_files: true` - Also delete environment directory

### 10. env_snapshot

Manage VM snapshots for backup and restore.

**Input:**
```json
{
  "env_name": "my-demo",
  "operation": "list",
  "snapshot_name": "pre-upgrade",
  "target": "all"
}
```

**Operations:**
- `list` - List all snapshots
- `save` - Create new snapshot
- `restore` - Restore from snapshot (async)
- `delete` - Delete snapshot

**Targets:** `hub`, `agent1`, ..., `agent7`, `all`

### 11. env_credentials

Retrieve Open Horizon credentials from environment.

**Input:**
```json
{
  "env_name": "my-demo",
  "show_secrets": false
}
```

**Security:**
- Credentials redacted by default
- Set `show_secrets: true` to reveal plain text
- Returns HZN_ORG_ID and HZN_EXCHANGE_USER_AUTH
- Only available after environment is provisioned

## Example Workflow

```typescript
// 1. Create environment
await env_create({
  name: "test-env",
  system_configuration: "unicycle"
});

// 2. Start provisioning
const { operation_id } = await env_provision({
  env_name: "test-env"
});

// 3. Monitor progress
await operation_status({ operation_id });
await operation_logs({ operation_id, limit: 100 });

// 4. Inspect when complete
await env_inspect({ env_name: "test-env" });

// 5. Execute commands
await env_exec({
  env_name: "test-env",
  target: "hub",
  command: "hzn version"
});

// 6. Clean up
await env_deprovision({
  env_name: "test-env",
  destroy: true
});
```

## Error Recovery

### Provision Failures

If provisioning fails:
1. Check logs: `operation_logs` with the operation_id
2. Fix underlying issue (network, disk space, VirtualBox)
3. Retry: `env_provision` with `force_recreate: true`

### Lock Timeouts

If you get lock timeout errors:
- Another operation may be running on the same environment
- Wait for it to complete or manually remove `~/.demo-in-a-box/envs/<name>/env.lock`

### Interrupted Operations

Operations handle interruptions gracefully:
- Locks are released on process exit
- Operation status reflects actual state
- Can retry provisioning from any state

## Security

- **Input Validation:** All inputs validated with Zod schemas
- **Command Allowlist:** Only specific make/vagrant commands permitted
- **Command Sanitization:** User commands sanitized before execution
- **File Locks:** Prevent concurrent modifications
- **Credential Handling:** mycreds.env files stay in environment directories

## Development

### Running Tests

```bash
npm test              # Run all tests
npm run test:watch   # Watch mode
```

### Building

```bash
npm run build        # Compile TypeScript
npm run lint         # Type check without building
```

## Troubleshooting

### Server won't start
- Check Node.js version (>=18 required)
- Verify all dependencies installed: `npm install`
- Check stdio transport is available (not running in browser)

### VMs won't provision
- Verify VirtualBox is installed and running
- Check available disk space (20GB+ per agent VM)
- Ensure virtualization enabled in BIOS
- Check host has sufficient RAM (2GB+ per agent VM)

### Can't connect to VMs
- Verify VMs are running: `env_inspect`
- Check vagrant ssh-config: `env_ssh_info`
- Ensure private network configured correctly

## License

Apache 2.0 - See LICENSE file in repository root
