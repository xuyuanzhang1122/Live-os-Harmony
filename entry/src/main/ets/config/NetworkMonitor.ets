import { connection } from '@kit.NetworkKit';

import { APIClient } from '../net/APIClient';

export class NetworkMonitor {
  private readonly onNetworkChange: () => void;
  private netConnection: connection.NetConnection | null = null;

  constructor(onNetworkChange: () => void) {
    this.onNetworkChange = onNetworkChange;
  }

  start(): void {
    if (this.netConnection !== null) {
      return;
    }
    try {
      const netConnection: connection.NetConnection = connection.createNetConnection();
      netConnection.on('netAvailable', (_handle: connection.NetHandle): void => this.onNetworkChange());
      netConnection.on('netLost', (_handle: connection.NetHandle): void => this.onNetworkChange());
      netConnection.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo): void => this.onNetworkChange());
      netConnection.register((error): void => {
        if (error) {
          this.stop();
        }
      });
      this.netConnection = netConnection;
    } catch (_) {
      this.netConnection = null;
    }
  }

  stop(): void {
    const current: connection.NetConnection | null = this.netConnection;
    this.netConnection = null;
    if (current !== null) {
      try {
        current.unregister((): void => {});
      } catch (_) {
      }
    }
  }

  static async probeLanReachable(lanURL: string, apiKey: string): Promise<boolean> {
    if (!(await NetworkMonitor.hasLANBearer())) {
      return false;
    }
    if (await NetworkMonitor.probeOnce(lanURL, apiKey)) {
      return true;
    }
    await NetworkMonitor.delay(500);
    return NetworkMonitor.probeOnce(lanURL, apiKey);
  }

  /// 蜂窝或无网络时局域网地址必然不可达，直接跳过探测
  private static async hasLANBearer(): Promise<boolean> {
    try {
      const handle: connection.NetHandle = await connection.getDefaultNet();
      const caps: connection.NetCapabilities = await connection.getNetCapabilities(handle);
      const bearers: Array<connection.NetBearType> = caps.bearerTypes;
      return bearers.includes(connection.NetBearType.BEARER_WIFI) ||
        bearers.includes(connection.NetBearType.BEARER_ETHERNET);
    } catch (_) {
      return false;
    }
  }

  private static async probeOnce(lanURL: string, apiKey: string): Promise<boolean> {
    return new APIClient(lanURL, apiKey).probeServer();
  }

  private static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }
}

export async function probeLanReachable(lanURL: string, apiKey: string): Promise<boolean> {
  return NetworkMonitor.probeLanReachable(lanURL, apiKey);
}
