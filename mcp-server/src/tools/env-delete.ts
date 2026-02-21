import { z } from 'zod';
import { stat } from 'fs/promises';
import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';

export const EnvDeleteInputSchema = z.object({
  env_name: z.string(),
  force: z.boolean().optional().default(false),
});

export async function envDeleteHandler(args: unknown) {
  const input = EnvDeleteInputSchema.parse(args);

  const envManager = new EnvironmentManager();

  // Validates the environment exists (throws if not)
  await envManager.getEnv(input.env_name);

  const envDir = envManager.getEnvDir(input.env_name);

  // Check whether Vagrant state directories exist, which suggests VMs may
  // have been created and could still be running.
  let mayHaveRunningVMs = false;
  for (const subdir of ['hub', 'agents']) {
    try {
      await stat(join(envDir, subdir, '.vagrant'));
      mayHaveRunningVMs = true;
      break;
    } catch {
      // .vagrant directory not present — no VMs created for this subdir
    }
  }

  if (mayHaveRunningVMs && !input.force) {
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(
            {
              success: false,
              error:
                'Environment may have running VMs. Run env_deprovision first to destroy them, or pass force=true to delete the metadata anyway (VMs will remain in VirtualBox).',
              environment: input.env_name,
            },
            null,
            2
          ),
        },
      ],
    };
  }

  await envManager.deleteEnv(input.env_name);

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(
          {
            success: true,
            environment: input.env_name,
            message: `Environment "${input.env_name}" deleted.${
              mayHaveRunningVMs
                ? ' Warning: VMs may still be registered in VirtualBox — remove them manually if needed.'
                : ''
            }`,
          },
          null,
          2
        ),
      },
    ],
  };
}
