import { z } from 'zod';
import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';
import { SystemConfigurationSchema, EnvironmentOverridesSchema } from '../env/types.js';
import { CommandExecutor } from '../vagrant/executor.js';
import { runAsyncOperation } from '../ops/async-operation.js';

export const EnvCreateInputSchema = z.object({
  name: z.string().regex(/^[a-z0-9-]+$/, 'Name must contain only lowercase letters, numbers, and hyphens'),
  system_configuration: SystemConfigurationSchema,
  overrides: EnvironmentOverridesSchema,
  auto_provision: z.boolean().optional().default(false),
});

export async function envCreateHandler(args: unknown) {
  const input = EnvCreateInputSchema.parse(args);

  const envManager = new EnvironmentManager();

  const metadata = await envManager.createEnv({
    name: input.name,
    system_configuration: input.system_configuration,
    overrides: input.overrides,
  });

  const response: Record<string, unknown> = {
    success: true,
    environment: {
      name: metadata.name,
      system_configuration: metadata.system_configuration,
      path: metadata.path,
      created_at: metadata.created_at,
    },
  };

  if (input.auto_provision) {
    const envDir = envManager.getEnvDir(metadata.name);
    const opsDir = join(envDir, 'ops');

    const envVars: Record<string, string> = {
      SYSTEM_CONFIGURATION: metadata.system_configuration,
    };
    if (metadata.overrides?.num_agents)  envVars.NUM_AGENTS   = String(metadata.overrides.num_agents);
    if (metadata.overrides?.base_ip)     envVars.BASE_IP      = String(metadata.overrides.base_ip);
    if (metadata.overrides?.memory_mb)   envVars.MEMORY       = String(metadata.overrides.memory_mb);
    if (metadata.overrides?.disk_gb)     envVars.DISK_SIZE    = String(metadata.overrides.disk_gb);
    if (metadata.overrides?.hub_os_type)   envVars.HUB_OS_TYPE   = metadata.overrides.hub_os_type;
    if (metadata.overrides?.agent_os_type) envVars.AGENT_OS_TYPE = metadata.overrides.agent_os_type;
    if (metadata.overrides?.box_version)   envVars.BOX_VERSION   = metadata.overrides.box_version;

    const operationId = await runAsyncOperation(
      metadata.name,
      opsDir,
      'provision',
      async (opId, logger) => {
        const executor = new CommandExecutor();
        logger.writeLine(`[${new Date().toISOString()}] Auto-provisioning ${metadata.system_configuration}...`);
        const result = await executor.executeMake('init', [], {
          cwd: envDir,
          env: envVars,
          logFile: join(opsDir, `op-${opId}.log`),
          timeout: 3600000,
        });
        logger.writeLine(`[${new Date().toISOString()}] Provision completed with exit code ${result.exit_code}`);
        return result.exit_code;
      }
    );

    response.message = 'Environment created and provisioning started in background.';
    response.operation_id = operationId;
    response.next_steps = [
      'Check operation status with operation_status tool',
      'View logs with operation_logs tool',
      'Inspect environment with env_inspect after completion',
    ];
  } else {
    response.message = 'Environment created successfully.';
    response.next_step = {
      tool: 'env_provision',
      args: { env_name: metadata.name },
    };
  }

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(response, null, 2),
      },
    ],
  };
}
