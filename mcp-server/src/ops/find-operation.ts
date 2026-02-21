import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';
import { OperationLedger } from './ledger.js';
import { OperationMetadata } from '../types.js';

/**
 * Scan all known environments to find an operation by ID.
 * Returns null if the operation is not found in any environment.
 */
export async function findOperation(
  operationId: string,
  envManager: EnvironmentManager
): Promise<OperationMetadata | null> {
  const envs = await envManager.listEnvs();

  for (const env of envs) {
    const opsDir = join(env.path, 'ops');
    const ledger = new OperationLedger(opsDir);

    try {
      return await ledger.getOperation(operationId);
    } catch {
      continue;
    }
  }

  return null;
}

/**
 * Same as findOperation but throws if the operation is not found.
 */
export async function requireOperation(
  operationId: string,
  envManager: EnvironmentManager
): Promise<{ operation: OperationMetadata; opsDir: string }> {
  const envs = await envManager.listEnvs();

  for (const env of envs) {
    const opsDir = join(env.path, 'ops');
    const ledger = new OperationLedger(opsDir);

    try {
      const operation = await ledger.getOperation(operationId);
      return { operation, opsDir };
    } catch {
      continue;
    }
  }

  throw new Error(`Operation "${operationId}" not found`);
}
