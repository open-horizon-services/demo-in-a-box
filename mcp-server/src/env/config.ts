import { homedir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Resolve the repository root relative to this compiled file's location so that
// the server works regardless of the working directory it is started from.
// Compiled path: mcp-server/dist/env/config.js  →  ../../../  =  repo root
// Source path (tsx dev): mcp-server/src/env/config.ts  →  ../../../  =  repo root
const __dirname = dirname(fileURLToPath(import.meta.url));
const derivedRepoRoot = join(__dirname, '..', '..', '..');

/**
 * Absolute path to the repository root.
 * Override via the DEMO_IN_A_BOX_REPO_ROOT environment variable when the
 * auto-detected path is not correct (e.g. unusual deployment layouts).
 */
export const REPO_ROOT = process.env.DEMO_IN_A_BOX_REPO_ROOT ?? derivedRepoRoot;

export const ENV_BASE_DIR = join(homedir(), '.demo-in-a-box', 'envs');
export const GLOBAL_LOCK_FILE = join(homedir(), '.demo-in-a-box', 'global.lock');

export const DEFAULT_CONFIGS = {
  unicycle: { num_agents: 1, memory_mb: 2048, disk_gb: 20, base_ip: 20 },
  bicycle: { num_agents: 3, memory_mb: 2048, disk_gb: 20, base_ip: 20 },
  car: { num_agents: 5, memory_mb: 2048, disk_gb: 20, base_ip: 20 },
  semi: { num_agents: 7, memory_mb: 2048, disk_gb: 20, base_ip: 20 },
};
