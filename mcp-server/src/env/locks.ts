import { open, mkdir } from 'fs/promises';
import { join, dirname } from 'path';
import { FileHandle } from 'fs/promises';
import { ENV_BASE_DIR } from './config.js';

const LOCK_TIMEOUT_MS = 30000;
const MAX_GLOBAL_CONCURRENT = 2;

let globalConcurrentCount = 0;
const globalWaiters: Array<() => void> = [];

export class LockManager {
  private lockHandles: Map<string, FileHandle> = new Map();

  async acquireEnvLock(envName: string): Promise<void> {
    const lockPath = join(ENV_BASE_DIR, envName, 'env.lock');
    
    await mkdir(dirname(lockPath), { recursive: true });

    const startTime = Date.now();
    
    while (true) {
      try {
        const handle = await open(lockPath, 'wx');
        this.lockHandles.set(envName, handle);
        return;
      } catch (error: any) {
        if (error.code === 'EEXIST') {
          if (Date.now() - startTime > LOCK_TIMEOUT_MS) {
            throw new Error(`Lock acquisition timeout for environment "${envName}"`);
          }
          await new Promise(resolve => setTimeout(resolve, 100));
        } else {
          throw error;
        }
      }
    }
  }

  async releaseEnvLock(envName: string): Promise<void> {
    const handle = this.lockHandles.get(envName);
    if (!handle) {
      return;
    }

    try {
      const lockPath = join(ENV_BASE_DIR, envName, 'env.lock');
      await handle.close();
      const fs = await import('fs/promises');
      await fs.unlink(lockPath);
    } catch (error) {
      console.error(`Failed to release lock for ${envName}:`, error);
    } finally {
      this.lockHandles.delete(envName);
    }
  }

  async withEnvLock<T>(envName: string, fn: () => Promise<T>): Promise<T> {
    await this.acquireEnvLock(envName);
    try {
      return await fn();
    } finally {
      await this.releaseEnvLock(envName);
    }
  }

  async acquireGlobalSlot(): Promise<void> {
    if (globalConcurrentCount < MAX_GLOBAL_CONCURRENT) {
      globalConcurrentCount++;
      return;
    }

    return new Promise<void>((resolve) => {
      globalWaiters.push(resolve);
    });
  }

  releaseGlobalSlot(): void {
    if (globalWaiters.length > 0) {
      const next = globalWaiters.shift();
      next?.();
    } else {
      globalConcurrentCount = Math.max(0, globalConcurrentCount - 1);
    }
  }

  async withGlobalSlot<T>(fn: () => Promise<T>): Promise<T> {
    await this.acquireGlobalSlot();
    try {
      return await fn();
    } finally {
      this.releaseGlobalSlot();
    }
  }

  async releaseAll(): Promise<void> {
    const envs = Array.from(this.lockHandles.keys());
    for (const env of envs) {
      await this.releaseEnvLock(env);
    }
  }
}

export const lockManager = new LockManager();

// Best-effort synchronous release on normal exit.
// SIGINT/SIGTERM are handled in server.ts so that server.close() and
// lockManager.releaseAll() both run in the correct order.
process.on('exit', () => {
  lockManager.releaseAll();
});
