import { z } from 'zod';
import { join } from 'path';
import { readFile } from 'fs/promises';
import { EnvironmentManager } from '../env/manager.js';
import { requireOperation } from '../ops/find-operation.js';

export const OperationLogsInputSchema = z.object({
  operation_id: z.string(),
  offset: z.number().min(0).optional().default(0),
  limit: z.number().min(1).max(10000).optional().default(1000),
  tail: z.boolean().optional().default(false),
});

export async function operationLogsHandler(args: unknown) {
  const input = OperationLogsInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  const { opsDir } = await requireOperation(input.operation_id, envManager);

  const logPath = join(opsDir, `op-${input.operation_id}.log`);

  let allLines: string[] = [];
  try {
    const content = await readFile(logPath, 'utf-8');
    allLines = content.split('\n');
  } catch (error: any) {
    if (error.code !== 'ENOENT') throw error;
    // Log file not yet created — return empty result
  }

  let lines: string[];
  let offset: number;
  let nextOffset: number;

  if (input.tail) {
    // Return the last `limit` lines, ignoring `offset`
    const start = Math.max(0, allLines.length - input.limit);
    lines = allLines.slice(start);
    offset = start;
    nextOffset = allLines.length;
  } else {
    lines = allLines.slice(input.offset, input.offset + input.limit);
    offset = input.offset;
    nextOffset = input.offset + lines.length;
  }

  const response = {
    success: true,
    operation_id: input.operation_id,
    offset,
    limit: input.limit,
    tail: input.tail,
    lines_returned: lines.length,
    next_offset: nextOffset,
    logs: lines.join('\n'),
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
