import { z } from 'zod';
import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';
import { CommandExecutor } from '../vagrant/executor.js';
import { runAsyncOperation } from '../ops/async-operation.js';

export const EnvDeprovisionInputSchema = z.object({
  env_name: z.string(),
  destroy: z.boolean().optional().default(true),
  cleanup_files: z.boolean().optional().default(false),
});

export async function envDeprovisionHandler(args: unknown) {
  const input = EnvDeprovisionInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  const config = await envManager.getEnv(input.env_name);

  const envDir = envManager.getEnvDir(input.env_name);
  const opsDir = join(envDir, 'ops');

  const destroy = input.destroy;
  const cleanupFiles = input.cleanup_files;
  const systemConfiguration = config.system_configuration;

  const operationId = await runAsyncOperation(
    input.env_name,
    opsDir,
    'deprovision',
    async (_opId, logger) => {
      const executor = new CommandExecutor();

      if (destroy) {
        logger.writeLine(`[${new Date().toISOString()}] Running make down to destroy VMs...`);

        const result = await executor.executeMake('down', [], {
          cwd: envDir,
          logFile: join(opsDir, `op-${_opId}.log`),
          timeout: 600000,
        });

        logger.writeLine(`[${new Date().toISOString()}] Deprovision completed with exit code ${result.exit_code}`);

        // cleanup_files runs after VMs are destroyed, before we return
        if (cleanupFiles && result.exit_code === 0) {
          logger.writeLine(`[${new Date().toISOString()}] Cleaning up environment files...`);
          await envManager.deleteEnv(input.env_name);
          logger.writeLine(`[${new Date().toISOString()}] Environment files deleted.`);
        }

        return result.exit_code;
      } else {
        // Halt (suspend) without destroying — halt both hub and agents
        logger.writeLine(`[${new Date().toISOString()}] Halting hub VM...`);

        const hubResult = await executor.executeVagrant('halt', [], {
          cwd: join(envDir, 'hub'),
          env: { VAGRANT_VAGRANTFILE: 'Vagrantfile.hub' },
          logFile: join(opsDir, `op-${_opId}.log`),
        });
        logger.writeLine(`[${new Date().toISOString()}] Hub halted with exit code ${hubResult.exit_code}`);

        logger.writeLine(`[${new Date().toISOString()}] Halting agent VMs...`);
        const agentResult = await executor.executeVagrant('halt', [], {
          cwd: join(envDir, 'agents'),
          env: { VAGRANT_VAGRANTFILE: `Vagrantfile.${systemConfiguration}` },
          logFile: join(opsDir, `op-${_opId}.log`),
        });
        logger.writeLine(`[${new Date().toISOString()}] Agents halted with exit code ${agentResult.exit_code}`);

        return hubResult.exit_code !== 0 ? hubResult.exit_code : agentResult.exit_code;
      }
    }
  );

  const response = {
    success: true,
    message: destroy ? 'Deprovision (destroy) started in background' : 'VM halt started in background',
    operation_id: operationId,
    environment: input.env_name,
    cleanup_files: cleanupFiles,
    next_steps: [
      'Check operation status with operation_status tool',
      'View logs with operation_logs tool',
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
