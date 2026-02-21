import { z } from 'zod';
import { EnvironmentManager } from '../env/manager.js';
import { requireOperation } from '../ops/find-operation.js';

export const OperationStatusInputSchema = z.object({
  operation_id: z.string(),
});

export async function operationStatusHandler(args: unknown) {
  const input = OperationStatusInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  const { operation } = await requireOperation(input.operation_id, envManager);

  const response: Record<string, unknown> = {
    success: true,
    operation,
  };

  if (operation.status === 'failed' && operation.error_summary) {
    response.next_actions = [
      'Check operation logs using operation_logs tool',
      'Review error and fix underlying issue',
      'Retry provisioning with env_provision',
    ];
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
