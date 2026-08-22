import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { APIClient } from '../net/APIClient';
import { ApiCache } from '../net/ApiCache';
import { ThumbnailCache } from '../cache/ThumbnailCache';
import { ServerInfo } from '../model/Common';
import { ApiKeyStore } from './ApiKeyStore';
import { NetworkMonitor } from './NetworkMonitor';

@ObservedV2
export class AppConfig {
  private static instance: AppConfig | null = null;

  @Trace serverURL: string = '';
  @Trace lanURL: string = '';
  @Trace publicURL: string = '';
  @Trace autoSwitchNetwork: boolean = false;
  @Trace backupServerURL: string = '';
  @Trace activeURL: string = '';
  @Trace isOnLAN: boolean = false;
  @Trace apiKeyBound: boolean = false;
  @Trace serverInfo: ServerInfo | null = null;

  private context: common.UIAbilityContext | null = null;
  private prefs: preferences.Preferences | null = null;
  private keyStore: ApiKeyStore | null = null;
  private apiKey: string = '';
  private cachedClient: APIClient | null = null;
  private cachedClientURL: string = '';
  private cachedClientKey: string = '';
  private monitor: NetworkMonitor | null = null;
  private initialized: boolean = false;
  private restoring: boolean = false;
  private networkRefreshToken: number = 0;

  private constructor() {
    APIClient.configureBackupBaseURLProvider((): string => this.backupServerURL);
  }

  static getInstance(context?: common.UIAbilityContext): AppConfig {
    if (AppConfig.instance === null) {
      AppConfig.instance = new AppConfig();
    }
    if (context !== undefined) {
      AppConfig.instance.attachContext(context);
    }
    return AppConfig.instance;
  }

  static selectActiveURL(autoSwitchNetwork: boolean, serverURL: string, lanURL: string,
    publicURL: string, lanReachable: boolean): string {
    if (!autoSwitchNetwork) {
      return serverURL.trim();
    }
    const lan: string = lanURL.trim();
    const remote: string = publicURL.trim();
    if (lan.length > 0 && remote.length > 0) {
      return lanReachable ? lan : remote;
    }
    if (lan.length > 0) {
      return lan;
    }
    return remote;
  }

  static clientNeedsRebuild(oldURL: string, newURL: string, oldKey: string, newKey: string): boolean {
    return oldURL !== newURL || oldKey !== newKey;
  }

  async getApiKey(): Promise<string> {
    if (this.keyStore !== null) {
      this.apiKey = await this.keyStore.get();
      this.apiKeyBound = this.apiKey.length > 0;
    }
    return this.apiKey;
  }

  async setApiKey(value: string): Promise<void> {
    const normalized: string = value.trim();
    if (this.keyStore !== null) {
      await this.keyStore.set(normalized);
    }
    const changed: boolean = this.apiKey !== normalized;
    this.apiKey = normalized;
    this.apiKeyBound = normalized.length > 0;
    if (changed) {
      this.clearClient();
      await this.refreshNetworkStatus();
    }
  }

  async clearApiKey(): Promise<void> {
    if (this.keyStore !== null) {
      await this.keyStore.clear();
    }
    const changed: boolean = this.apiKey.length > 0;
    this.apiKey = '';
    this.apiKeyBound = false;
    if (changed) {
      this.clearClient();
      await this.refreshNetworkStatus();
    }
  }

  async refreshNetworkStatus(): Promise<void> {
    const refreshToken: number = this.networkRefreshToken + 1;
    this.networkRefreshToken = refreshToken;
    let lanReachable: boolean = false;
    const lan: string = this.lanURL.trim();
    const remote: string = this.publicURL.trim();
    if (this.autoSwitchNetwork && lan.length > 0 && remote.length > 0) {
      lanReachable = await NetworkMonitor.probeLanReachable(lan, this.apiKey);
    }
    if (refreshToken !== this.networkRefreshToken) {
      return;
    }
    this.isOnLAN = this.autoSwitchNetwork && lan.length > 0 && (remote.length === 0 || lanReachable);
    const nextURL: string = AppConfig.selectActiveURL(this.autoSwitchNetwork, this.serverURL, lan, remote,
      lanReachable);
    if (nextURL !== this.activeURL) {
      this.activeURL = nextURL;
      this.clearClient();
    }
  }

  getClient(): APIClient {
    if (this.cachedClient === null ||
      AppConfig.clientNeedsRebuild(this.cachedClientURL, this.activeURL, this.cachedClientKey, this.apiKey)) {
      this.cachedClient = new APIClient(this.activeURL, this.apiKey);
      this.cachedClientURL = this.activeURL;
      this.cachedClientKey = this.apiKey;
    }
    return this.cachedClient;
  }

  @Monitor('serverURL', 'lanURL', 'publicURL', 'autoSwitchNetwork', 'backupServerURL')
  onPersistentSettingsChanged(_monitor: IMonitor): void {
    if (this.restoring) {
      return;
    }
    this.persistSettings().catch((): void => {});
    this.refreshNetworkStatus().catch((): void => {});
  }

  private attachContext(context: common.UIAbilityContext): void {
    if (this.context !== null) {
      return;
    }
    this.context = context;
    this.initialize().catch((): void => {});
  }

  private async initialize(): Promise<void> {
    if (this.initialized || this.context === null) {
      return;
    }
    this.initialized = true;
    try {
      ApiCache.getInstance(this.context.cacheDir);
      ThumbnailCache.getInstance(this.context.cacheDir);
      this.prefs = await preferences.getPreferences(this.context, 'config');
      this.restoring = true;
      this.serverURL = String(await this.prefs.get('serverURL', ''));
      this.lanURL = String(await this.prefs.get('lanURL', ''));
      this.publicURL = String(await this.prefs.get('publicURL', ''));
      this.autoSwitchNetwork = Boolean(await this.prefs.get('autoSwitchNetwork', false));
      this.backupServerURL = String(await this.prefs.get('backupServerURL', ''));
    } catch (_) {
      this.restoring = false;
      this.initialized = false;
      return;
    }
    this.restoring = false;
    this.keyStore = new ApiKeyStore(this.prefs);
    this.apiKey = await this.keyStore.get();
    this.apiKeyBound = this.apiKey.length > 0;
    this.monitor = new NetworkMonitor((): void => {
      if (this.autoSwitchNetwork) {
        this.refreshNetworkStatus().catch((): void => {});
      }
    });
    this.monitor.start();
    await this.refreshNetworkStatus();
  }

  private async persistSettings(): Promise<void> {
    const store: preferences.Preferences | null = this.prefs;
    if (store === null) {
      return;
    }
    try {
      await store.put('serverURL', this.serverURL);
      await store.put('lanURL', this.lanURL);
      await store.put('publicURL', this.publicURL);
      await store.put('autoSwitchNetwork', this.autoSwitchNetwork);
      await store.put('backupServerURL', this.backupServerURL);
      await store.flush();
    } catch (_) {
    }
  }

  private clearClient(): void {
    this.cachedClient = null;
    this.cachedClientURL = '';
    this.cachedClientKey = '';
  }
}
