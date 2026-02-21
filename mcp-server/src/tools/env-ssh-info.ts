import { z } from 'zod';
import { EnvironmentManager } from '../env/manager.js';
import { CommandExecutor } from '../vagrant/executor.js';
import { parseSSHConfig } from '../vagrant/parser.js';
import { resolveVMTarget } from '../vagrant/target.js';

export const EnvSSHInfoInputSchema = z.object({
  env_name: z.string(),
  target: z.enum(['hub', 'agent1', 'agent2', 'agent3', 'agent4', 'agent5', 'agent6', 'agent7']).default('hub'),
});

export async function envSSHInfoHandler(args: unknown) {
  const input = EnvSSHInfoInputSchema.parse(args);

  const envManager = new EnvironmentManager();
  const executor = new CommandExecutor();

  const { cwd, vagrantfile, vmName } = await resolveVMTarget(
    input.env_name,
    input.target,
    envManager
  );

  const result = await executor.executeVagrant('ssh-config', [vmName], {
    cwd,
    env: { VAGRANT_VAGRANTFILE: vagrantfile },
  });

  const sshConfig = parseSSHConfig(result.stdout);

  const response = {
    success: true,
    environment: input.env_name,
    target: input.target,
    ssh_config: sshConfig,
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
