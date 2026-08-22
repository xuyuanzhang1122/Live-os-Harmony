import { ApiError, ApiErrorType } from '../model/Common';

function isHTTPURL(value: string): boolean {
  return /^https?:\/\/[^\s]+$/i.test(value.trim());
}

export function validateNetworkConfig(autoSwitchNetwork: boolean, serverURL: string,
  lanURL: string, publicURL: string): string {
  const server: string = serverURL.trim();
  const lan: string = lanURL.trim();
  const remote: string = publicURL.trim();
  if (!autoSwitchNetwork) {
    if (server.length === 0) {
      return '请输入服务器地址';
    }
    return isHTTPURL(server) ? '' : '服务器地址必须以 http:// 或 https:// 开头';
  }
  if (lan.length === 0 && remote.length === 0) {
    return '局域网地址和公网地址至少填写一个';
  }
  if (lan.length > 0 && !isHTTPURL(lan)) {
    return '局域网地址必须以 http:// 或 https:// 开头';
  }
  if (remote.length > 0 && !isHTTPURL(remote)) {
    return '公网地址必须以 http:// 或 https:// 开头';
  }
  return '';
}

export function apiKeySummary(localKey: string, keySuffix: string | null): string {
  const key: string = localKey.trim();
  const suffix: string = (keySuffix ?? '').trim();
  if (key.length === 0 && suffix.length === 0) {
    return '未设置';
  }
  const tail: string = suffix.length > 0 ? suffix : key.slice(Math.max(0, key.length - 4));
  return `已配置（••••${tail}）`;
}

export function apiKeyValidationError(error: Object): string {
  if (error instanceof ApiError && (error.type === ApiErrorType.UNAUTHORIZED ||
    error.statusCode === 401 || error.statusCode === 403)) {
    return 'API Key 无效或未开启鉴权';
  }
  if (error instanceof Error) {
    return error.message;
  }
  return `${error}`;
}

export function totalCacheBytes(apiCacheBytes: number, thumbnailCacheBytes: number): number {
  return Math.max(0, apiCacheBytes) + Math.max(0, thumbnailCacheBytes);
}

export function cacheClearMessage(remainingBytes: number): string {
  return remainingBytes === 0 ? '已清除' : '部分缓存未能清除';
}
