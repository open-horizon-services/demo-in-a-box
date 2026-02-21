import { z } from 'zod';

export const SystemConfigurationSchema = z.enum(['unicycle', 'bicycle', 'car', 'semi']);

export const OsTypeSchema = z.enum(['ubuntu-22', 'ubuntu-24', 'fedora-41']);

export const EnvironmentOverridesSchema = z.object({
  memory_mb: z.number().min(1024).max(16384).optional(),
  disk_gb: z.number().min(10).max(500).optional(),
  base_ip: z.number().min(10).max(250).optional(),
  num_agents: z.number().min(1).max(10).optional(),
  hub_os_type: OsTypeSchema.optional(),
  agent_os_type: OsTypeSchema.optional(),
  box_version: z.string().optional(),
}).optional();

export const EnvironmentConfigSchema = z.object({
  name: z.string().regex(/^[a-z0-9-]+$/, 'Name must contain only lowercase letters, numbers, and hyphens'),
  system_configuration: SystemConfigurationSchema,
  overrides: EnvironmentOverridesSchema,
  created_at: z.string().datetime(),
});

export type EnvironmentConfigInput = {
  name: string;
  system_configuration: 'unicycle' | 'bicycle' | 'car' | 'semi';
  overrides?: {
    memory_mb?: number;
    disk_gb?: number;
    base_ip?: number;
    num_agents?: number;
  };
};
