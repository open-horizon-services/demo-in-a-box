import { mkdir, readdir, readFile, rm, stat, symlink, writeFile } from 'fs/promises';
import { join } from 'path';
import { EnvironmentConfig, EnvironmentMetadata } from '../types.js';
import { DEFAULT_CONFIGS, ENV_BASE_DIR, REPO_ROOT } from './config.js';
import { EnvironmentConfigInput, EnvironmentConfigSchema } from './types.js';

export class EnvironmentManager {
  private readonly baseDir: string;

  constructor(baseDir?: string) {
    this.baseDir = baseDir ?? ENV_BASE_DIR;
  }

  async createEnv(input: EnvironmentConfigInput): Promise<EnvironmentMetadata> {
    const config: EnvironmentConfig = {
      ...input,
      created_at: new Date().toISOString(),
    };

    EnvironmentConfigSchema.parse(config);

    const envDir = this.getEnvDir(config.name);

    try {
      await stat(envDir);
      throw new Error(`Environment "${config.name}" already exists`);
    } catch (error: any) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }

    await mkdir(envDir, { recursive: true });
    await mkdir(join(envDir, 'hub'), { recursive: true });
    await mkdir(join(envDir, 'agents'), { recursive: true });
    await mkdir(join(envDir, 'ops'), { recursive: true });

    await this.createSymlinks(envDir);

    await writeFile(
      join(envDir, 'env.json'),
      JSON.stringify(config, null, 2),
      'utf-8'
    );

    return {
      ...config,
      path: envDir,
    };
  }

  private async createSymlinks(envDir: string): Promise<void> {
    const hubDir = join(envDir, 'hub');
    const agentsDir = join(envDir, 'agents');

    const makefilePath = join(REPO_ROOT, 'Makefile');
    const configDir = join(REPO_ROOT, 'configuration');
    const vagrantHubPath = join(REPO_ROOT, 'configuration', 'Vagrantfile.hub');
    const vagrantTemplatePath = join(REPO_ROOT, 'configuration', 'Vagrantfile.template.erb');

    try {
      await symlink(makefilePath, join(hubDir, 'Makefile'));
      await symlink(configDir, join(hubDir, 'configuration'));
      await symlink(vagrantHubPath, join(hubDir, 'Vagrantfile.hub'));

      await symlink(makefilePath, join(agentsDir, 'Makefile'));
      await symlink(configDir, join(agentsDir, 'configuration'));
      await symlink(vagrantTemplatePath, join(agentsDir, 'Vagrantfile.template.erb'));
    } catch (error: any) {
      if (error.code !== 'EEXIST') {
        throw new Error(`Failed to create symlinks: ${error.message}`);
      }
    }
  }

  async listEnvs(): Promise<EnvironmentMetadata[]> {
    try {
      await mkdir(this.baseDir, { recursive: true });
      const entries = await readdir(this.baseDir);

      const envs: EnvironmentMetadata[] = [];

      for (const entry of entries) {
        try {
          const envDir = join(this.baseDir, entry);
          const stats = await stat(envDir);
          
          if (stats.isDirectory()) {
            const config = await this.getEnv(entry);
            envs.push({
              ...config,
              path: envDir,
            });
          }
        } catch (error) {
          continue;
        }
      }
      
      return envs;
    } catch (error: any) {
      if (error.code === 'ENOENT') {
        return [];
      }
      throw error;
    }
  }

  async getEnv(name: string): Promise<EnvironmentConfig> {
    const envDir = this.getEnvDir(name);
    const configPath = join(envDir, 'env.json');
    
    try {
      const content = await readFile(configPath, 'utf-8');
      const config = JSON.parse(content);
      return EnvironmentConfigSchema.parse(config);
    } catch (error: any) {
      if (error.code === 'ENOENT') {
        throw new Error(`Environment "${name}" does not exist`);
      }
      throw new Error(`Failed to read environment config: ${error.message}`);
    }
  }

  async deleteEnv(name: string): Promise<void> {
    const envDir = this.getEnvDir(name);
    
    try {
      await stat(envDir);
    } catch (error: any) {
      if (error.code === 'ENOENT') {
        throw new Error(`Environment "${name}" does not exist`);
      }
      throw error;
    }

    await rm(envDir, { recursive: true, force: true });
  }

  getEnvDir(name: string): string {
    return join(this.baseDir, name);
  }

  getDefaultConfig(systemConfig: 'unicycle' | 'bicycle' | 'car' | 'semi') {
    return DEFAULT_CONFIGS[systemConfig];
  }
}
