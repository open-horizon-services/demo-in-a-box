import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

import { lockManager } from './env/locks.js';
import { envCreateHandler } from './tools/env-create.js';
import { envListHandler } from './tools/env-list.js';
import { envInspectHandler } from './tools/env-inspect.js';
import { envProvisionHandler } from './tools/env-provision.js';
import { operationStatusHandler } from './tools/operation-status.js';
import { operationLogsHandler } from './tools/operation-logs.js';
import { envSSHInfoHandler } from './tools/env-ssh-info.js';
import { envExecHandler } from './tools/env-exec.js';
import { envDeprovisionHandler } from './tools/env-deprovision.js';
import { envSnapshotHandler } from './tools/env-snapshot.js';
import { envCredentialsHandler } from './tools/env-credentials.js';
import { envDeleteHandler } from './tools/env-delete.js';

export class DemoInABoxMCPServer {
  private server: Server;

  constructor() {
    this.server = new Server(
      {
        name: 'demo-in-a-box',
        version: '1.0.0',
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.setupToolHandlers();
    this.setupErrorHandlers();
  }

  private setupToolHandlers(): void {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: 'env_create',
          description: 'Create a new Open Horizon demo environment with specified configuration',
          inputSchema: {
            type: 'object',
            properties: {
              name: {
                type: 'string',
                description: 'Environment name (lowercase letters, numbers, hyphens only)',
              },
              system_configuration: {
                type: 'string',
                enum: ['unicycle', 'bicycle', 'car', 'semi'],
                description: 'System topology: unicycle (1 agent), bicycle (3), car (5), semi (7)',
              },
              overrides: {
                type: 'object',
                properties: {
                  memory_mb:     { type: 'number', description: 'Memory per agent VM in MB' },
                  disk_gb:       { type: 'number', description: 'Disk per agent VM in GB' },
                  base_ip:       { type: 'number', description: 'Starting IP offset for agent VMs' },
                  num_agents:    { type: 'number', description: 'Override number of agents' },
                  hub_os_type:   { type: 'string', enum: ['ubuntu-22', 'ubuntu-24', 'fedora-41'], description: 'OS for hub VM' },
                  agent_os_type: { type: 'string', enum: ['ubuntu-22', 'ubuntu-24', 'fedora-41'], description: 'OS for agent VMs' },
                  box_version:   { type: 'string', description: 'Custom Vagrant box version (e.g. 1.0.0)' },
                },
              },
              auto_provision: {
                type: 'boolean',
                description: 'Immediately start provisioning after creation (returns operation_id)',
              },
            },
            required: ['name', 'system_configuration'],
          },
        },
        {
          name: 'env_list',
          description: 'List all demo environments, optionally filtered by system configuration',
          inputSchema: {
            type: 'object',
            properties: {
              filter_status: {
                type: 'string',
                enum: ['unicycle', 'bicycle', 'car', 'semi'],
                description: 'Filter by system configuration',
              },
            },
          },
        },
        {
          name: 'env_inspect',
          description: 'Get detailed status of a demo environment (desired state, observed VM states, artifacts)',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name to inspect',
              },
            },
            required: ['env_name'],
          },
        },
        {
          name: 'env_provision',
          description: 'Start provisioning VMs for an environment (async operation, returns operation_id)',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name to provision',
              },
              force_recreate: {
                type: 'boolean',
                description: 'Run make down before provisioning to clean up existing VMs',
              },
            },
            required: ['env_name'],
          },
        },
        {
          name: 'env_deprovision',
          description: 'Deprovision (destroy or halt) VMs in an environment (async operation)',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name',
              },
              destroy: {
                type: 'boolean',
                description: 'Destroy VMs completely (true) or just halt/suspend them (false)',
              },
              cleanup_files: {
                type: 'boolean',
                description: 'Also delete environment metadata directory after successful destroy',
              },
            },
            required: ['env_name'],
          },
        },
        {
          name: 'env_delete',
          description: 'Delete an environment\'s metadata and files. Use env_deprovision first to destroy VMs.',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name to delete',
              },
              force: {
                type: 'boolean',
                description: 'Delete even if VMs may still be running (they will remain in VirtualBox)',
              },
            },
            required: ['env_name'],
          },
        },
        {
          name: 'env_snapshot',
          description: 'Manage VM snapshots (list/save/restore/delete)',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name',
              },
              operation: {
                type: 'string',
                enum: ['list', 'save', 'restore', 'delete'],
                description: 'Snapshot operation',
              },
              snapshot_name: {
                type: 'string',
                description: 'Snapshot name (required for save/restore/delete)',
              },
              target: {
                type: 'string',
                enum: ['hub', 'agent1', 'agent2', 'agent3', 'agent4', 'agent5', 'agent6', 'agent7', 'all'],
                description: 'Target VM(s)',
              },
              description: {
                type: 'string',
                description: 'Human-readable note appended to the save confirmation message',
              },
            },
            required: ['env_name', 'operation'],
          },
        },
        {
          name: 'env_ssh_info',
          description: 'Get SSH connection details for a VM in the environment',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name',
              },
              target: {
                type: 'string',
                enum: ['hub', 'agent1', 'agent2', 'agent3', 'agent4', 'agent5', 'agent6', 'agent7'],
                description: 'Target VM (default: hub)',
              },
            },
            required: ['env_name'],
          },
        },
        {
          name: 'env_exec',
          description: 'Execute a command on a VM in the environment via vagrant ssh',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name',
              },
              target: {
                type: 'string',
                enum: ['hub', 'agent1', 'agent2', 'agent3', 'agent4', 'agent5', 'agent6', 'agent7'],
                description: 'Target VM (default: hub)',
              },
              command: {
                type: 'string',
                description: 'Command to execute on the VM',
              },
              timeout_ms: {
                type: 'number',
                description: 'Command timeout in milliseconds (default: 60000)',
              },
            },
            required: ['env_name', 'command'],
          },
        },
        {
          name: 'env_credentials',
          description: 'Retrieve Open Horizon credentials from a provisioned environment (redacted by default)',
          inputSchema: {
            type: 'object',
            properties: {
              env_name: {
                type: 'string',
                description: 'Environment name',
              },
              show_secrets: {
                type: 'boolean',
                description: 'Show HZN_EXCHANGE_USER_AUTH in plain text (default: false)',
              },
            },
            required: ['env_name'],
          },
        },
        {
          name: 'operation_status',
          description: 'Check status of an async operation (provision, deprovision, snapshot-restore)',
          inputSchema: {
            type: 'object',
            properties: {
              operation_id: {
                type: 'string',
                description: 'Operation ID returned from an async tool',
              },
            },
            required: ['operation_id'],
          },
        },
        {
          name: 'operation_logs',
          description: 'Retrieve logs from an async operation with pagination or tail support',
          inputSchema: {
            type: 'object',
            properties: {
              operation_id: {
                type: 'string',
                description: 'Operation ID',
              },
              offset: {
                type: 'number',
                description: 'Line offset for paginated forward reads (ignored when tail=true)',
              },
              limit: {
                type: 'number',
                description: 'Maximum number of lines to return (default: 1000)',
              },
              tail: {
                type: 'boolean',
                description: 'Return the last `limit` lines instead of reading from `offset`',
              },
            },
            required: ['operation_id'],
          },
        },
      ],
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      try {
        switch (request.params.name) {
          case 'env_create':        return await envCreateHandler(request.params.arguments);
          case 'env_list':          return await envListHandler(request.params.arguments);
          case 'env_inspect':       return await envInspectHandler(request.params.arguments);
          case 'env_provision':     return await envProvisionHandler(request.params.arguments);
          case 'env_deprovision':   return await envDeprovisionHandler(request.params.arguments);
          case 'env_delete':        return await envDeleteHandler(request.params.arguments);
          case 'env_snapshot':      return await envSnapshotHandler(request.params.arguments);
          case 'env_ssh_info':      return await envSSHInfoHandler(request.params.arguments);
          case 'env_exec':          return await envExecHandler(request.params.arguments);
          case 'env_credentials':   return await envCredentialsHandler(request.params.arguments);
          case 'operation_status':  return await operationStatusHandler(request.params.arguments);
          case 'operation_logs':    return await operationLogsHandler(request.params.arguments);
          default:
            throw new Error(`Unknown tool: ${request.params.name}`);
        }
      } catch (error: any) {
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(
                { success: false, error: error.message },
                null,
                2
              ),
            },
          ],
          isError: true,
        };
      }
    });
  }

  private setupErrorHandlers(): void {
    this.server.onerror = (error) => {
      console.error('[MCP Error]', error);
    };

    // Consolidated signal handlers — release locks then close server.
    // locks.ts only registers an `exit` handler; SIGINT/SIGTERM are handled here.
    process.on('SIGINT', async () => {
      await this.close();
      process.exit(0);
    });

    process.on('SIGTERM', async () => {
      await this.close();
      process.exit(0);
    });
  }

  async connect(): Promise<void> {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Demo-in-a-Box MCP server running on stdio');
  }

  async close(): Promise<void> {
    // Release all held file locks before closing the transport so that
    // in-flight operations leave a clean state.
    await lockManager.releaseAll();
    await this.server.close();
  }

  getServer(): Server {
    return this.server;
  }
}
