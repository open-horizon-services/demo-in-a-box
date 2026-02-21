export type SystemConfiguration = 'unicycle' | 'bicycle' | 'car' | 'semi';

export type OperationStatus = 'queued' | 'running' | 'succeeded' | 'failed' | 'cancelled';

export type VMState = 'running' | 'stopped' | 'not_created' | 'saved' | 'poweroff' | 'aborted';

export type OsType = 'ubuntu-22' | 'ubuntu-24' | 'fedora-41';

export interface EnvironmentConfig {
  name: string;
  system_configuration: SystemConfiguration;
  overrides?: {
    memory_mb?: number;
    disk_gb?: number;
    base_ip?: number;
    num_agents?: number;
    hub_os_type?: OsType;
    agent_os_type?: OsType;
    box_version?: string;
  };
  created_at: string;
}

export interface EnvironmentMetadata extends EnvironmentConfig {
  path: string;
}

export interface VMStatus {
  name: string;
  state: VMState;
  ip?: string;
  provider?: string;
}

export interface HubStatus extends VMStatus {
  ports?: {
    exchange: number;  // 3090
    agbot: number;     // 3111
    fdo: number;       // 9008
    css: number;       // 9443
  };
}

export interface EnvironmentStatus {
  desired: EnvironmentConfig;
  observed: {
    hub: HubStatus;
    agents: VMStatus[];
  };
  artifacts: {
    creds_present: boolean;
    ssh_keys_present: boolean;
  };
  last_operation?: OperationMetadata;
}

export interface OperationMetadata {
  id: string;
  env_name: string;
  type: string;
  status: OperationStatus;
  created_at: string;
  started_at?: string;
  finished_at?: string;
  exit_code?: number;
  error_summary?: string;
}

export interface SSHConfig {
  host: string;
  hostname: string;
  port: number;
  user: string;
  identity_file: string;
  connection_command: string;
}

export interface CommandResult {
  stdout: string;
  stderr: string;
  exit_code: number;
  duration_ms: number;
}
