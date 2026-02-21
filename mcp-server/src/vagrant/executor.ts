import { spawn } from 'child_process';
import { CommandResult } from '../types.js';
import { isAllowedMakeCommand, isAllowedVagrantCommand } from './commands.js';
import { createWriteStream } from 'fs';

export interface ExecuteOptions {
  cwd: string;
  env?: Record<string, string>;
  timeout?: number;
  logFile?: string;
}

export class CommandExecutor {
  async executeMake(
    command: string,
    args: string[],
    options: ExecuteOptions
  ): Promise<CommandResult> {
    if (!isAllowedMakeCommand(command)) {
      throw new Error(`Make command "${command}" is not allowed`);
    }

    return this.executeCommand('make', [command, ...args], options);
  }

  async executeVagrant(
    command: string,
    args: string[],
    options: ExecuteOptions
  ): Promise<CommandResult> {
    if (!isAllowedVagrantCommand(command)) {
      throw new Error(`Vagrant command "${command}" is not allowed`);
    }

    return this.executeCommand('vagrant', [command, ...args], options);
  }

  private async executeCommand(
    cmd: string,
    args: string[],
    options: ExecuteOptions
  ): Promise<CommandResult> {
    const startTime = Date.now();
    const timeout = options.timeout || 300000;

    return new Promise((resolve, reject) => {
      let stdout = '';
      let stderr = '';

      const env = {
        ...process.env,
        ...options.env,
      };

      const child = spawn(cmd, args, {
        cwd: options.cwd,
        env,
        // shell: false (default) — args are passed directly to the process so
        // shell metacharacters in arguments cannot be interpreted locally.
      });

      let logStream: ReturnType<typeof createWriteStream> | null = null;
      if (options.logFile) {
        logStream = createWriteStream(options.logFile, { flags: 'a' });
      }

      const timeoutHandle = setTimeout(() => {
        child.kill('SIGTERM');
        setTimeout(() => child.kill('SIGKILL'), 5000);
      }, timeout);

      child.stdout?.on('data', (data: Buffer) => {
        const str = data.toString();
        stdout += str;
        logStream?.write(str);
      });

      child.stderr?.on('data', (data: Buffer) => {
        const str = data.toString();
        stderr += str;
        logStream?.write(str);
      });

      child.on('error', (error) => {
        clearTimeout(timeoutHandle);
        logStream?.end();
        reject(new Error(`Failed to execute ${cmd}: ${error.message}`));
      });

      child.on('close', (code) => {
        clearTimeout(timeoutHandle);
        logStream?.end();

        const duration = Date.now() - startTime;

        resolve({
          stdout,
          stderr,
          exit_code: code ?? -1,
          duration_ms: duration,
        });
      });
    });
  }
}
