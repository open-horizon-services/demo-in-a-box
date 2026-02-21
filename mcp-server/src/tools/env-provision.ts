import { z } from 'zod';
import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';
import { CommandExecutor } from '../vagrant/executor.js';
import { runAsyncOperation } from '../ops/async-operation.js';

export const EnvProvisionInputSchema = z.object({
  env_name: z.string(),
  force_recreate: z.boolean().optional().default(false),
});

export async function envProvisionHandler(args: unknown) {
  const input = EnvProvisionInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  const config = await envManager.getEnv(input.env_name);

  const envDir = envManager.getEnvDir(input.env_name);
  const opsDir = join(envDir, 'ops');

  const envVars: Record<string, string> = {
    SYSTEM_CONFIGURATION: config.system_configuration,
  };
  if (config.overrides?.num_agents)    envVars.NUM_AGENTS    = String(config.overrides.num_agents);
  if (config.overrides?.base_ip)       envVars.BASE_IP       = String(config.overrides.base_ip);
  if (config.overrides?.memory_mb)     envVars.MEMORY        = String(config.overrides.memory_mb);
  if (config.overrides?.disk_gb)       envVars.DISK_SIZE     = String(config.overrides.disk_gb);
  if (config.overrides?.hub_os_type)   envVars.HUB_OS_TYPE   = config.overrides.hub_os_type;
  if (config.overrides?.agent_os_type) envVars.AGENT_OS_TYPE = config.overrides.agent_os_type;
  if (config.overrides?.box_version)   envVars.BOX_VERSION   = config.overrides.box_version;

  const forceRecreate = input.force_recreate;

  const operationId = await runAsyncOperation(
    input.env_name,
    opsDir,
    'provision',
    async (opId, logger) => {
      const executor = new CommandExecutor();

      if (forceRecreate) {
        logger.writeLine(`[${new Date().toISOString()}] Running make down to clean up existing VMs...`);
        const downResult = await executor.executeMake('down', [], {
          cwd: envDir,
          logFile: join(opsDir, `op-${opId}.log`),
        });
        if (downResult.exit_code !== 0) {
          logger.writeLine(`[${new Date().toISOString()}] Warning: make down failed (exit ${downResult.exit_code}), continuing...`);
        }
      }

      logger.writeLine(`[${new Date().toISOString()}] Starting provision for ${config.system_configuration}...`);

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

  const response = {
    success: true,
    message: 'Provisioning started in background',
    operation_id: operationId,
    environment: input.env_name,
    next_steps: [
      'Check operation status with operation_status tool',
      'View logs with operation_logs tool',
      'Inspect environment with env_inspect after completion',
    ],
  };

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(response, null, 2),
      },
    ],
  };
}
