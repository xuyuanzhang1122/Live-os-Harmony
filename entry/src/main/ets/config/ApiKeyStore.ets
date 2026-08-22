import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';

const ASSET_ALIAS: string = 'api_key';
const FALLBACK_KEY: string = 'api_key_fallback';

export class ApiKeyStore {
  private readonly prefs: preferences.Preferences;

  constructor(prefs: preferences.Preferences) {
    this.prefs = prefs;
  }

  async get(): Promise<string> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, ApiKeyStore.encode(ASSET_ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      query.set(asset.Tag.RETURN_LIMIT, 1);
      const results: asset.AssetMap[] = await asset.query(query);
      if (results.length > 0) {
        const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
        if (secret instanceof Uint8Array) {
          return ApiKeyStore.decode(secret);
        }
      }
    } catch (_) {
      // Asset Store 异常或不可用时回退 preferences。
    }
    try {
      return String(await this.prefs.get(FALLBACK_KEY, ''));
    } catch (_) {
      return '';
    }
  }

  async set(value: string): Promise<void> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, ApiKeyStore.encode(ASSET_ALIAS));
      try {
        await asset.remove(query);
      } catch (_) {
      }
      if (value.length > 0) {
        const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
        attributes.set(asset.Tag.ALIAS, ApiKeyStore.encode(ASSET_ALIAS));
        attributes.set(asset.Tag.SECRET, ApiKeyStore.encode(value));
        await asset.add(attributes);
      }
      await this.prefs.delete(FALLBACK_KEY);
      await this.prefs.flush();
      return;
    } catch (_) {
      try {
        await this.prefs.put(FALLBACK_KEY, value);
        await this.prefs.flush();
      } catch (_) {
      }
    }
  }

  async clear(): Promise<void> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, ApiKeyStore.encode(ASSET_ALIAS));
      await asset.remove(query);
    } catch (_) {
    }
    try {
      await this.prefs.delete(FALLBACK_KEY);
      await this.prefs.flush();
    } catch (_) {
    }
  }

  private static encode(value: string): Uint8Array {
    return new util.TextEncoder('utf-8').encodeInto(value);
  }

  private static decode(value: Uint8Array): string {
    return new util.TextDecoder('utf-8').decodeToString(value);
  }
}
