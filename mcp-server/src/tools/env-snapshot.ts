import { z } from 'zod';
import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';
import { CommandExecutor } from '../vagrant/executor.js';
import { runAsyncOperation } from '../ops/async-operation.js';

export const EnvSnapshotInputSchema = z.object({
  env_name: z.string(),
  operation: z.enum(['list', 'save', 'restore', 'delete']),
  snapshot_name: z.string().optional(),
  target: z.enum(['hub', 'agent1', 'agent2', 'agent3', 'agent4', 'agent5', 'agent6', 'agent7', 'all']).default('all'),
  description: z.string().optional(),
});

export async function envSnapshotHandler(args: unknown) {
  const input = EnvSnapshotInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  const executor = new CommandExecutor();
  const config = await envManager.getEnv(input.env_name);

  const envDir = envManager.getEnvDir(input.env_name);

  switch (input.operation) {
    case 'list':
      return snapshotList(input.env_name, input.target, envDir, config.system_configuration, executor);

    case 'save':
      return snapshotSave(input, envDir, config.system_configuration, executor);

    case 'restore':
      return snapshotRestore(input, envDir, config.system_configuration, envManager);

    case 'delete':
      return snapshotDelete(input, envDir, config.system_configuration, executor);

    default:
      throw new Error(`Unknown snapshot operation: ${input.operation}`);
  }
}

// ── list ──────────────────────────────────────────────────────────────────────

async function snapshotList(
  envName: string,
  target: string,
  envDir: string,
  systemConfiguration: string,
  executor: CommandExecutor
) {
  const results: { hub: string[] | null; agents: string[] } = { hub: null, agents: [] };

  if (target === 'hub' || target === 'all') {
    try {
      const hubResult = await executor.executeVagrant('snapshot', ['list'], {
        cwd: join(envDir, 'hub'),
        env: { VAGRANT_VAGRANTFILE: 'Vagrantfile.hub' },
      });
      results.hub = parseSnapshotList(hubResult.stdout);
    } catch {}
  }

  if (target === 'all' || target.startsWith('agent')) {
    try {
      const agentsResult = await executor.executeVagrant('snapshot', ['list'], {
        cwd: join(envDir, 'agents'),
        env: { VAGRANT_VAGRANTFILE: `Vagrantfile.${systemConfiguration}` },
      });
      results.agents = parseSnapshotList(agentsResult.stdout);
    } catch {}
  }

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(
          { success: true, environment: envName, snapshots: results },
          null, 2
        ),
      },
    ],
  };
}

// ── save ──────────────────────────────────────────────────────────────────────

async function snapshotSave(
  input: z.infer<typeof EnvSnapshotInputSchema>,
  envDir: string,
  systemConfiguration: string,
  executor: CommandExecutor
) {
  if (!input.snapshot_name) {
    throw new Error('snapshot_name is required for save operation');
  }

  const cwd = input.target === 'hub' ? join(envDir, 'hub') : join(envDir, 'agents');
  const vagrantfile = input.target === 'hub'
    ? 'Vagrantfile.hub'
    : `Vagrantfile.${systemConfiguration}`;
  const targetVM = input.target === 'hub'
    ? 'default'
    : input.target === 'all' ? undefined : input.target;

  const snapshotArgs = targetVM
    ? [targetVM, input.snapshot_name]
    : [input.snapshot_name];

  const result = await executor.executeVagrant('snapshot', ['save', ...snapshotArgs], {
    cwd,
    env: { VAGRANT_VAGRANTFILE: vagrantfile },
    timeout: 300000,
  });

  const message = result.exit_code === 0
    ? `Snapshot "${input.snapshot_name}" saved successfully${input.description ? ` — ${input.description}` : ''}`
    : 'Snapshot save failed';

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(
          {
            success: result.exit_code === 0,
            environment: input.env_name,
            operation: 'save',
            snapshot_name: input.snapshot_name,
            target: input.target,
            message,
          },
          null, 2
        ),
      },
    ],
  };
}

// ── restore ───────────────────────────────────────────────────────────────────

async function snapshotRestore(
  input: z.infer<typeof EnvSnapshotInputSchema>,
  envDir: string,
  systemConfiguration: string,
  _envManager: EnvironmentManager
) {
  if (!input.snapshot_name) {
    throw new Error('snapshot_name is required for restore operation');
  }

  const opsDir = join(envDir, 'ops');
  const snapshotName = input.snapshot_name;
  const target = input.target;

  const operationId = await runAsyncOperation(
    input.env_name,
    opsDir,
    'snapshot-restore',
    async (opId, logger) => {
      const executor = new CommandExecutor();

      const cwd = target === 'hub' ? join(envDir, 'hub') : join(envDir, 'agents');
      const vagrantfile = target === 'hub'
        ? 'Vagrantfile.hub'
        : `Vagrantfile.${systemConfiguration}`;
      const targetVM = target === 'hub'
        ? 'default'
        : target === 'all' ? undefined : target;

      const restoreArgs = targetVM ? [targetVM, snapshotName] : [snapshotName];

      logger.writeLine(`[${new Date().toISOString()}] Restoring snapshot "${snapshotName}" for ${target}...`);

      const result = await executor.executeVagrant('snapshot', ['restore', ...restoreArgs], {
        cwd,
        env: { VAGRANT_VAGRANTFILE: vagrantfile },
        logFile: join(opsDir, `op-${opId}.log`),
        timeout: 600000,
      });

      logger.writeLine(`[${new Date().toISOString()}] Restore completed with exit code ${result.exit_code}`);
      return result.exit_code;
    }
  );

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(
          {
            success: true,
            message: `Snapshot restore started in background`,
            operation_id: operationId,
            environment: input.env_name,
            snapshot_name: snapshotName,
            target,
          },
          null, 2
        ),
      },
    ],
  };
}

// ── delete ────────────────────────────────────────────────────────────────────

async function snapshotDelete(
  input: z.infer<typeof EnvSnapshotInputSchema>,
  envDir: string,
  systemConfiguration: string,
  executor: CommandExecutor
) {
  if (!input.snapshot_name) {
    throw new Error('snapshot_name is required for delete operation');
  }

  const cwd = input.target === 'hub' ? join(envDir, 'hub') : join(envDir, 'agents');
  const vagrantfile = input.target === 'hub'
    ? 'Vagrantfile.hub'
    : `Vagrantfile.${systemConfiguration}`;
  const targetVM = input.target === 'hub'
    ? 'default'
    : input.target === 'all' ? undefined : input.target;

  const deleteArgs = targetVM
    ? [targetVM, input.snapshot_name]
    : [input.snapshot_name];

  const result = await executor.executeVagrant('snapshot', ['delete', ...deleteArgs], {
    cwd,
    env: { VAGRANT_VAGRANTFILE: vagrantfile },
  });

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(
          {
            success: result.exit_code === 0,
            environment: input.env_name,
            operation: 'delete',
            snapshot_name: input.snapshot_name,
            target: input.target,
            message: result.exit_code === 0
              ? `Snapshot "${input.snapshot_name}" deleted successfully`
              : 'Snapshot delete failed',
          },
          null, 2
        ),
      },
    ],
  };
}

// ── helpers ───────────────────────────────────────────────────────────────────

function parseSnapshotList(output: string): string[] {
  return output
    .split('\n')
    .map(l => l.trim())
    .filter(l => l !== '' && !l.includes('==>') && !l.includes('Name:'));
}
