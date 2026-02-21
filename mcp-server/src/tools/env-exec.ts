import { z } from 'zod';
import { EnvironmentManager } from '../env/manager.js';
import { CommandExecutor } from '../vagrant/executor.js';
import { resolveVMTarget } from '../vagrant/target.js';

export const EnvExecInputSchema = z.object({
  env_name: z.string(),
  target: z.enum(['hub', 'agent1', 'agent2', 'agent3', 'agent4', 'agent5', 'agent6', 'agent7']).default('hub'),
  command: z.string().min(1).max(1000),
  timeout_ms: z.number().min(1000).max(300000).optional().default(60000),
});

export async function envExecHandler(args: unknown) {
  const input = EnvExecInputSchema.parse(args);

  // Strip characters that could alter argument boundaries on the remote shell
  // (`$` for variable expansion, backticks for command substitution).
  // Note: with shell:false in spawn, these only matter at the remote VM level.
  const sanitizedCommand = input.command.replace(/[`$]/g, '');

  const envManager = new EnvironmentManager();
  const executor = new CommandExecutor();

  const { cwd, vagrantfile, vmName } = await resolveVMTarget(
    input.env_name,
    input.target,
    envManager
  );

  // Pass the command as a separate argument — no extra quoting needed because
  // spawn (shell:false) passes args directly to the process without a shell
  // interpreting them locally.
  const result = await executor.executeVagrant('ssh', [vmName, '-c', sanitizedCommand], {
    cwd,
    env: { VAGRANT_VAGRANTFILE: vagrantfile },
    timeout: input.timeout_ms,
  });

  const response = {
    success: result.exit_code === 0,
    environment: input.env_name,
    target: input.target,
    command: sanitizedCommand,
    exit_code: result.exit_code,
    stdout: result.stdout,
    stderr: result.stderr,
    duration_ms: result.duration_ms,
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
