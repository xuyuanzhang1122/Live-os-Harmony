import { connection, http } from '@kit.NetworkKit';

interface ProbeHeaders {
  Authorization?: string;
}

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
    const base: string = lanURL.trim().replace(/\/+$/, '');
    if (!/^https?:\/\//i.test(base)) {
      return false;
    }
    const request: http.HttpRequest = http.createHttp();
    const headers: ProbeHeaders = {};
    if (apiKey.length > 0) {
      headers.Authorization = `Bearer ${apiKey}`;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 2000,
      readTimeout: 2000,
      usingCache: false
    };
    try {
      const response: http.HttpResponse = await request.request(`${base}/api/info`, options);
      // 收到任何 HTTP 状态码（含 401/404/405）都说明服务器可达；
      // 只有请求本身抛错（超时、无路由）才视为不可达
      return response.responseCode > 0;
    } catch (_) {
      return false;
    } finally {
      request.destroy();
    }
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
