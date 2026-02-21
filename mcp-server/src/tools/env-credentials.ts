import { z } from 'zod';
import { readFile } from 'fs/promises';
import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';

export const EnvCredentialsInputSchema = z.object({
  env_name: z.string(),
  show_secrets: z.boolean().optional().default(false),
});

export async function envCredentialsHandler(args: unknown) {
  const input = EnvCredentialsInputSchema.parse(args);

  const envManager = new EnvironmentManager();

  // Validate the environment exists before attempting to read credentials
  await envManager.getEnv(input.env_name);

  const envDir = envManager.getEnvDir(input.env_name);
  const credsPath = join(envDir, 'hub', 'mycreds.env');

  try {
    const content = await readFile(credsPath, 'utf-8');
    const lines = content.split('\n');

    const credentials: Record<string, string> = {};

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;

      if (trimmed.startsWith('export ')) {
        const withoutExport = trimmed.substring(7);
        const [key, ...valueParts] = withoutExport.split('=');
        const value = valueParts.join('=');

        if (key === 'HZN_ORG_ID') {
          credentials.hzn_org_id = value;
        } else if (key === 'HZN_EXCHANGE_USER_AUTH') {
          credentials.hzn_exchange_user_auth = input.show_secrets
            ? value
            : '[REDACTED — set show_secrets=true to reveal]';
        }
      }
    }

    const response = {
      success: true,
      environment: input.env_name,
      credentials,
      warning: input.show_secrets
        ? 'WARNING: Credentials are shown in plain text. Keep this information secure!'
        : 'Credentials are redacted by default. Set show_secrets=true to reveal.',
    };

    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(response, null, 2),
        },
      ],
    };
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                success: false,
                error: 'Credentials file not found. Environment may not be fully provisioned yet.',
                environment: input.env_name,
              },
              null,
              2
            ),
          },
        ],
      };
    }
    throw error;
  }
}
