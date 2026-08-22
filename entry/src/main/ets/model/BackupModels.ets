export class BackupDeviceConfig {
  serverURL: string;
  lanURL: string;
  publicURL: string;
  autoSwitchNetwork: boolean;

  constructor(serverURL: string = '', lanURL: string = '', publicURL: string = '', autoSwitchNetwork: boolean = false) {
    this.serverURL = serverURL;
    this.lanURL = lanURL;
    this.publicURL = publicURL;
    this.autoSwitchNetwork = autoSwitchNetwork;
  }
}

export class BackupLiveRoom {
  url: string;
  is_listening: boolean;

  constructor(url: string = '', isListening: boolean = false) {
    this.url = url;
    this.is_listening = isListening;
  }
}

export class BackupServerConfig {
  rpc_bind: string;
  out_put_path: string;
  app_data_path: string;
  live_rooms: BackupLiveRoom[];

  constructor(rpcBind: string = '', outputPath: string = '', appDataPath: string = '',
    liveRooms: BackupLiveRoom[] = []) {
    this.rpc_bind = rpcBind;
    this.out_put_path = outputPath;
    this.app_data_path = appDataPath;
    this.live_rooms = liveRooms;
  }
}

export interface BackupIdResult {
  id: string;
  created_at: string | null;
}

export interface RestoreResult {
  status: string;
  job_id: string | null;
  message: string | null;
}

export interface RestoreRequestBody {
  id?: string;
  package?: BackupPackage;
}

export interface ServerRpcConfigInput {
  bind?: string;
}

export interface ServerLiveRoomInput {
  url?: string;
  is_listening?: boolean;
}

export interface ServerConfigInput {
  rpc?: ServerRpcConfigInput;
  out_put_path?: string;
  app_data_path?: string;
  live_rooms?: ServerLiveRoomInput[];
}

interface BackupDeviceConfigInput {
  serverURL?: string;
  lanURL?: string;
  publicURL?: string;
  autoSwitchNetwork?: boolean;
}

interface BackupLiveRoomInput {
  url?: string;
  is_listening?: boolean;
}

interface BackupServerConfigInput {
  rpc_bind?: string;
  out_put_path?: string;
  app_data_path?: string;
  live_rooms?: BackupLiveRoomInput[];
}

interface BackupPackageInput {
  schemaVersion?: number;
  exportedAt?: string;
  iosConfig?: BackupDeviceConfigInput;
  server?: BackupServerConfigInput;
}

class SortedBackupDeviceConfig {
  autoSwitchNetwork: boolean;
  lanURL: string;
  publicURL: string;
  serverURL: string;

  constructor(value: BackupDeviceConfig) {
    this.autoSwitchNetwork = value.autoSwitchNetwork;
    this.lanURL = value.lanURL;
    this.publicURL = value.publicURL;
    this.serverURL = value.serverURL;
  }
}

class SortedBackupLiveRoom {
  is_listening: boolean;
  url: string;

  constructor(value: BackupLiveRoom) {
    this.is_listening = value.is_listening;
    this.url = value.url;
  }
}

class SortedBackupServerConfig {
  app_data_path: string;
  live_rooms: SortedBackupLiveRoom[];
  out_put_path: string;
  rpc_bind: string;

  constructor(value: BackupServerConfig) {
    this.app_data_path = value.app_data_path;
    this.live_rooms = value.live_rooms.map((room: BackupLiveRoom): SortedBackupLiveRoom =>
      new SortedBackupLiveRoom(room));
    this.out_put_path = value.out_put_path;
    this.rpc_bind = value.rpc_bind;
  }
}

class SortedBackupPackage {
  exportedAt: string;
  iosConfig: SortedBackupDeviceConfig;
  schemaVersion: number;
  server: SortedBackupServerConfig;

  constructor(value: BackupPackage) {
    this.exportedAt = value.exportedAt;
    this.iosConfig = new SortedBackupDeviceConfig(value.iosConfig);
    this.schemaVersion = value.schemaVersion;
    this.server = new SortedBackupServerConfig(value.server);
  }
}

export class BackupPackage {
  schemaVersion: number;
  exportedAt: string;
  iosConfig: BackupDeviceConfig;
  server: BackupServerConfig;

  constructor(schemaVersion: number = 1, exportedAt: string = BackupPackage.utcNowSeconds(),
    iosConfig: BackupDeviceConfig = new BackupDeviceConfig(), server: BackupServerConfig = new BackupServerConfig()) {
    this.schemaVersion = schemaVersion;
    this.exportedAt = exportedAt;
    this.iosConfig = iosConfig;
    this.server = server;
  }

  toJson(): string {
    return JSON.stringify(new SortedBackupPackage(this), null, 2);
  }

  static fromJson(json: string): BackupPackage {
    const parsed: BackupPackageInput = JSON.parse(json) as BackupPackageInput;
    const deviceValue: BackupDeviceConfigInput = parsed.iosConfig ?? {};
    const serverValue: BackupServerConfigInput = parsed.server ?? {};
    const roomValues: BackupLiveRoomInput[] = serverValue.live_rooms ?? [];
    const rooms: BackupLiveRoom[] = roomValues.map((room: BackupLiveRoomInput): BackupLiveRoom =>
      new BackupLiveRoom(room.url ?? '', room.is_listening ?? false));
    return new BackupPackage(
      parsed.schemaVersion ?? 1,
      parsed.exportedAt ?? '',
      new BackupDeviceConfig(deviceValue.serverURL ?? '', deviceValue.lanURL ?? '', deviceValue.publicURL ?? '',
        deviceValue.autoSwitchNetwork ?? false),
      new BackupServerConfig(serverValue.rpc_bind ?? '', serverValue.out_put_path ?? '',
        serverValue.app_data_path ?? '', rooms)
    );
  }

  static fromServerConfig(device: BackupDeviceConfig, cfg: object,
    exportedAt: string = BackupPackage.utcNowSeconds()): BackupPackage {
    let value: ServerConfigInput;
    if (cfg instanceof Map) {
      const configMap: Map<string, Object> = cfg as Map<string, Object>;
      const rpcValue: Object | undefined = configMap.get('rpc');
      const outputValue: Object | undefined = configMap.get('out_put_path');
      const appDataValue: Object | undefined = configMap.get('app_data_path');
      const roomsValue: Object | undefined = configMap.get('live_rooms');
      value = {
        rpc: rpcValue === undefined ? undefined : rpcValue as ServerRpcConfigInput,
        out_put_path: outputValue === undefined ? undefined : String(outputValue),
        app_data_path: appDataValue === undefined ? undefined : String(appDataValue),
        live_rooms: roomsValue === undefined ? undefined : roomsValue as ServerLiveRoomInput[]
      };
    } else {
      value = cfg as ServerConfigInput;
    }
    const roomValues: ServerLiveRoomInput[] = value.live_rooms ?? [];
    const rooms: BackupLiveRoom[] = roomValues.map((room: ServerLiveRoomInput): BackupLiveRoom =>
      new BackupLiveRoom(room.url ?? '', room.is_listening ?? false));
    return new BackupPackage(1, exportedAt, device,
      new BackupServerConfig(value.rpc?.bind ?? '', value.out_put_path ?? '', value.app_data_path ?? '', rooms));
  }

  private static utcNowSeconds(): string {
    return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  }
}
