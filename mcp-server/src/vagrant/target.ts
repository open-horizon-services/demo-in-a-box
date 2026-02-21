import { join } from 'path';
import { EnvironmentManager } from '../env/manager.js';

export interface VMTarget {
  cwd: string;
  vagrantfile: string;
  vmName: string;
}

/**
 * Resolve the working directory, Vagrantfile name, and VM name for a given
 * environment + target combination.  Centralises the hub/agent routing logic
 * that was previously copy-pasted across env-exec.ts and env-ssh-info.ts.
 */
export async function resolveVMTarget(
  envName: string,
  target: string,
  envManager: EnvironmentManager
): Promise<VMTarget> {
  const envDir = envManager.getEnvDir(envName);

  if (target === 'hub') {
    return {
      cwd: join(envDir, 'hub'),
      vagrantfile: 'Vagrantfile.hub',
      vmName: 'default',
    };
  }

  const config = await envManager.getEnv(envName);
  return {
    cwd: join(envDir, 'agents'),
    vagrantfile: `Vagrantfile.${config.system_configuration}`,
    vmName: target,
  };
}
