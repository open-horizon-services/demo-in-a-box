import { z } from 'zod';
import { EnvironmentManager } from '../env/manager.js';

export const EnvListInputSchema = z.object({
  // Filters by system_configuration (unicycle, bicycle, car, semi).
  // Pass an empty string or omit to return all environments.
  filter_status: z.string().optional(),
});

export async function envListHandler(args: unknown) {
  const input = EnvListInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  let envs = await envManager.listEnvs();

  if (input.filter_status && input.filter_status.trim() !== '') {
    const filter = input.filter_status.trim().toLowerCase();
    envs = envs.filter(env => env.system_configuration === filter);
  }

  const response = {
    success: true,
    count: envs.length,
    filter_applied: input.filter_status ? input.filter_status.trim() : null,
    environments: envs.map(env => ({
      name: env.name,
      system_configuration: env.system_configuration,
      created_at: env.created_at,
      path: env.path,
    })),
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
