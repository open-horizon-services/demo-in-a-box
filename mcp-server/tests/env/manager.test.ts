import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { EnvironmentManager } from '../../src/env/manager.js';
import { rm } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';

// Each test run gets its own isolated directory under the OS temp folder so
// that tests never read from or write to the production ~/.demo-in-a-box/envs.
let TEST_ENV_BASE: string;

describe('EnvironmentManager', () => {
  let manager: EnvironmentManager;

  beforeEach(() => {
    TEST_ENV_BASE = join(tmpdir(), `demo-in-a-box-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
    manager = new EnvironmentManager(TEST_ENV_BASE);
  });

  afterEach(async () => {
    try {
      await rm(TEST_ENV_BASE, { recursive: true, force: true });
    } catch {}
  });

  describe('createEnv', () => {
    it('should create environment with valid config', async () => {
      const input = {
        name: 'test-env-1',
        system_configuration: 'unicycle' as const,
      };

      const result = await manager.createEnv(input);

      expect(result.name).toBe('test-env-1');
      expect(result.system_configuration).toBe('unicycle');
      expect(result.created_at).toBeDefined();
      expect(result.path).toContain('test-env-1');
    });

    it('should reject invalid environment names', async () => {
      const input = {
        name: 'Test_Env_1',
        system_configuration: 'unicycle' as const,
      };

      await expect(manager.createEnv(input)).rejects.toThrow();
    });

    it('should reject duplicate environment names', async () => {
      const input = {
        name: 'test-env-duplicate',
        system_configuration: 'unicycle' as const,
      };

      await manager.createEnv(input);
      await expect(manager.createEnv(input)).rejects.toThrow('already exists');
    });

    it('should create environment with overrides', async () => {
      const input = {
        name: 'test-env-overrides',
        system_configuration: 'bicycle' as const,
        overrides: {
          memory_mb: 4096,
          disk_gb: 30,
        },
      };

      const result = await manager.createEnv(input);

      expect(result.overrides).toEqual({
        memory_mb: 4096,
        disk_gb: 30,
      });
    });

    it('should create environment with OS type overrides', async () => {
      const input = {
        name: 'test-env-os',
        system_configuration: 'unicycle' as const,
        overrides: {
          hub_os_type: 'ubuntu-24' as const,
          agent_os_type: 'fedora-41' as const,
          box_version: '2.0.0',
        },
      };

      const result = await manager.createEnv(input);

      expect(result.overrides?.hub_os_type).toBe('ubuntu-24');
      expect(result.overrides?.agent_os_type).toBe('fedora-41');
      expect(result.overrides?.box_version).toBe('2.0.0');
    });
  });

  describe('listEnvs', () => {
    it('should return array of environments', async () => {
      const envs = await manager.listEnvs();
      expect(Array.isArray(envs)).toBe(true);
    });

    it('should list created environments', async () => {
      await manager.createEnv({
        name: 'test-env-list-1',
        system_configuration: 'unicycle',
      });

      await manager.createEnv({
        name: 'test-env-list-2',
        system_configuration: 'bicycle',
      });

      const envs = await manager.listEnvs();

      expect(envs.length).toBeGreaterThanOrEqual(2);
      const names = envs.map(e => e.name);
      expect(names).toContain('test-env-list-1');
      expect(names).toContain('test-env-list-2');
    });
  });

  describe('getEnv', () => {
    it('should retrieve environment config', async () => {
      await manager.createEnv({
        name: 'test-env-get',
        system_configuration: 'car',
      });

      const config = await manager.getEnv('test-env-get');

      expect(config.name).toBe('test-env-get');
      expect(config.system_configuration).toBe('car');
    });

    it('should throw error for non-existent environment', async () => {
      await expect(manager.getEnv('non-existent')).rejects.toThrow('does not exist');
    });
  });

  describe('deleteEnv', () => {
    it('should delete existing environment', async () => {
      await manager.createEnv({
        name: 'test-env-delete',
        system_configuration: 'unicycle',
      });

      await manager.deleteEnv('test-env-delete');

      await expect(manager.getEnv('test-env-delete')).rejects.toThrow('does not exist');
    });

    it('should throw error when deleting non-existent environment', async () => {
      await expect(manager.deleteEnv('non-existent')).rejects.toThrow('does not exist');
    });
  });

  describe('getDefaultConfig', () => {
    it('should return correct defaults for unicycle', () => {
      const config = manager.getDefaultConfig('unicycle');
      expect(config.num_agents).toBe(1);
      expect(config.memory_mb).toBe(2048);
    });

    it('should return correct defaults for bicycle', () => {
      const config = manager.getDefaultConfig('bicycle');
      expect(config.num_agents).toBe(3);
    });

    it('should return correct defaults for car', () => {
      const config = manager.getDefaultConfig('car');
      expect(config.num_agents).toBe(5);
    });

    it('should return correct defaults for semi', () => {
      const config = manager.getDefaultConfig('semi');
      expect(config.num_agents).toBe(7);
    });
  });
});
