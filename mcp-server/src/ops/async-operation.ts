import { OperationLedger } from './ledger.js';
import { OperationLogger } from './logger.js';
import { lockManager } from '../env/locks.js';

/**
 * Run a long-running operation asynchronously with full lifecycle management.
 *
 * The fn callback receives (operationId, logger) and should:
 *   - Write progress to logger via logger.writeLine()
 *   - Return a numeric exit code (non-zero = failure), or void for success
 *   - Throw to indicate a fatal error
 *   - NOT call logger.close() — the helper closes the logger automatically
 *
 * Returns the operation ID immediately; the operation runs in background.
 */
export async function runAsyncOperation(
  envName: string,
  opsDir: string,
  type: string,
  fn: (operationId: string, logger: OperationLogger) => Promise<number | void>
): Promise<string> {
  const ledger = new OperationLedger(opsDir);
  const { id: operationId, logger } = await ledger.createOperation(envName, type);

  Promise.resolve().then(async () => {
    try {
      await lockManager.withEnvLock(envName, async () => {
        await lockManager.withGlobalSlot(async () => {
          await ledger.updateOperation(operationId, {
            status: 'running',
            started_at: new Date().toISOString(),
          });

          let exitCode: number;
          try {
            exitCode = (await fn(operationId, logger)) ?? 0;
          } catch (fnError: any) {
            logger.writeLine(`[${new Date().toISOString()}] ERROR: ${fnError.message}`);
            await ledger.updateOperation(operationId, {
              status: 'failed',
              finished_at: new Date().toISOString(),
              error_summary: fnError.message,
            });
            await logger.close();
            return;
          }

          await ledger.updateOperation(operationId, {
            status: exitCode === 0 ? 'succeeded' : 'failed',
            finished_at: new Date().toISOString(),
            exit_code: exitCode,
            ...(exitCode !== 0 ? { error_summary: 'Operation failed. Check logs for details.' } : {}),
          });

          await logger.close();
        });
      });
    } catch (lockError: any) {
      logger.writeLine(`[${new Date().toISOString()}] ERROR: ${lockError.message}`);
      try {
        await ledger.updateOperation(operationId, {
          status: 'failed',
          finished_at: new Date().toISOString(),
          error_summary: lockError.message,
        });
      } catch {}
      await logger.close().catch(() => {});
    }
  });

  return operationId;
}
