export enum ApiErrorType {
  UNAUTHORIZED = 'unauthorized',
  INVALID_URL = 'invalidURL',
  NETWORK = 'network',
  DECODING = 'decoding',
  SERVER = 'server',
  UNSUPPORTED = 'unsupported'
}

export class ApiError extends Error {
  readonly type: ApiErrorType;
  readonly statusCode: number;

  constructor(type: ApiErrorType, detail: string = '', statusCode: number = 0) {
    super(ApiError.messageFor(type, detail, statusCode));
    this.name = 'ApiError';
    this.type = type;
    this.statusCode = statusCode;
  }

  static unauthorized(): ApiError {
    return new ApiError(ApiErrorType.UNAUTHORIZED);
  }

  static invalidURL(): ApiError {
    return new ApiError(ApiErrorType.INVALID_URL);
  }

  static network(detail: string = ''): ApiError {
    return new ApiError(ApiErrorType.NETWORK, detail);
  }

  static decoding(detail: string = ''): ApiError {
    return new ApiError(ApiErrorType.DECODING, detail);
  }

  static server(code: number, detail: string = ''): ApiError {
    return new ApiError(ApiErrorType.SERVER, detail, code);
  }

  static unsupported(detail: string = ''): ApiError {
    return new ApiError(ApiErrorType.UNSUPPORTED, detail);
  }

  private static messageFor(type: ApiErrorType, detail: string, statusCode: number): string {
    switch (type) {
      case ApiErrorType.UNAUTHORIZED:
        return 'API Key 错误，请在设置中检查';
      case ApiErrorType.INVALID_URL:
        return '无效的服务器地址';
      case ApiErrorType.NETWORK:
        return detail.length > 0 ? `网络错误: ${detail}` : '网络错误';
      case ApiErrorType.DECODING:
        return detail.length > 0 ? `数据解析失败: ${detail}` : '数据解析失败';
      case ApiErrorType.SERVER:
        return `服务器错误 ${statusCode}: ${detail.length > 0 ? detail : '请求失败'}`;
      case ApiErrorType.UNSUPPORTED:
        return detail.length > 0 ? `暂不支持: ${detail}` : '暂不支持此操作';
      default:
        return '未知错误';
    }
  }
}

export interface APIResponse<T> {
  err_no: number;
  err_msg: string;
  data: T | null;
}

export interface ServerInfo {
  app_name: string;
  app_version: string;
  build_time: string;
  git_hash: string;
  pid: number;
  platform: string;
  go_version: string;
}

export interface APIKeyUser {
  id: string;
  name: string;
  key_suffix: string | null;
  enabled: boolean | null;
  created_at: string | null;
  last_used_at: string | null;
  revoked_at: string | null;
}

export interface ResolveURLResult {
  url: string;
}

export interface PlaybackResolveResult {
  status: string;
  protocol?: string;
  mime_type?: string;
  url?: string;
  expires_at?: number;
  error?: string;
  retry_after_seconds?: number;
}
