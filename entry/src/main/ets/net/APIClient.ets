import { http } from '@kit.NetworkKit';
import { ApiError, APIKeyUser, ResolveURLResult, ServerInfo } from '../model/Common';
import { AddLiveRequest, LiveInfo } from '../model/LiveRoom';
import { VideoFileInfo, VideoFileInfoInit, VideoRoomInfo, VideoRoomInfoInit } from '../model/VideoLibrary';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { BackupIdResult, BackupPackage, RestoreRequestBody, RestoreResult } from '../model/BackupModels';

export type BackupTarget = 'main' | 'backup';

export interface APIRequestOptions {
  baseURL?: string;
  rawBody?: string;
  authorize?: boolean;
}

interface ResponseEnvelope {
  err_no?: number;
  err_msg?: string;
  data?: Object | null;
}

interface SourceErrorEnvelope {
  error?: string;
  code?: number;
}

interface RequestHeaders {
  Authorization?: string;
  'Content-Type'?: string;
}

class EmptyResponse {
}

class DeleteLiveBody {
  delete_files: boolean;

  constructor(deleteFiles: boolean) {
    this.delete_files = deleteFiles;
  }
}

class BatchDeleteBody {
  paths: string[];

  constructor(paths: string[]) {
    this.paths = paths;
  }
}

class HistoryPostBody {
  video_path: string;
  video_name: string;
  position_seconds: number;
  duration_seconds: number;

  constructor(entry: WatchHistoryEntry) {
    this.video_path = entry.video_path;
    this.video_name = entry.video_name;
    this.position_seconds = entry.position_seconds;
    this.duration_seconds = entry.duration_seconds;
  }
}

export class APIClient {
  private static backupBaseURLProvider: (() => string) | null = null;
  readonly baseURL: string;
  readonly apiKey: string;

  constructor(baseURL: string, apiKey: string = '') {
    this.baseURL = APIClient.trimBase(baseURL);
    this.apiKey = apiKey;
  }

  static configureBackupBaseURLProvider(provider: () => string): void {
    APIClient.backupBaseURLProvider = provider;
  }

  static encodePathSegments(path: string): string {
    return path.split('/').map((segment: string): string => encodeURIComponent(segment)).join('/');
  }

  static appendKeyIfUnsigned(url: string, apiKey: string): string {
    if (apiKey.length === 0) {
      return url;
    }
    const hasExpires: boolean = /(?:\?|&)expires=/.test(url);
    const hasSignature: boolean = /(?:\?|&)sig=/.test(url);
    if ((hasExpires && hasSignature) || /(?:\?|&)_key=/.test(url)) {
      return url;
    }
    const separator: string = url.indexOf('?') >= 0 ? '&' : '?';
    return `${url}${separator}_key=${encodeURIComponent(apiKey)}`;
  }

  static buildThumbnailUrl(base: string, apiKey: string, file: VideoFileInfo): string {
    const relative: string = file.thumbnail_url !== null && file.thumbnail_url.length > 0 ? file.thumbnail_url :
      `/api/thumbnail/${APIClient.encodePathSegments(file.rel_path)}`;
    return APIClient.appendKeyIfUnsigned(APIClient.absoluteURL(base, relative), apiKey);
  }

  static buildPlaybackUrl(base: string, apiKey: string, file: VideoFileInfo): string {
    let relative: string;
    if (file.hls_url !== null && file.hls_url.length > 0) {
      relative = file.hls_url;
    } else if (file.file_url !== null && file.file_url.length > 0) {
      relative = file.file_url;
    } else {
      const encoded: string = APIClient.encodePathSegments(file.rel_path);
      relative = VideoFileInfo.isNativePlayable(file.name.length > 0 ? file.name : file.rel_path) ?
        `/files/${encoded}` : `/api/stream/hls/${encoded}`;
    }
    return APIClient.appendKeyIfUnsigned(APIClient.absoluteURL(base, relative), apiKey);
  }

  async request<T>(method: string, path: string, body?: Object, opts: APIRequestOptions = {}): Promise<T> {
    const rawBody: string | undefined = opts.rawBody ?? (body === undefined ? undefined : JSON.stringify(body));
    const base: string = APIClient.trimBase(opts.baseURL ?? this.baseURL);
    if (!APIClient.isValidBase(base)) {
      throw ApiError.invalidURL();
    }
    const url: string = APIClient.absoluteURL(base, path);
    const request: http.HttpRequest = http.createHttp();
    const authorization: string | undefined = (opts.authorize ?? true) && this.apiKey.length > 0 ?
      `Bearer ${this.apiKey}` : undefined;
    let headers: RequestHeaders;
    if (authorization !== undefined && rawBody !== undefined) {
      headers = { Authorization: authorization, 'Content-Type': 'application/json' };
    } else if (authorization !== undefined) {
      headers = { Authorization: authorization };
    } else if (rawBody !== undefined) {
      headers = { 'Content-Type': 'application/json' };
    } else {
      headers = {};
    }
    const requestOptions: http.HttpRequestOptions = {
      method: APIClient.toRequestMethod(method),
      header: headers,
      extraData: rawBody,
      readTimeout: 15000,
      connectTimeout: 15000,
      usingCache: false
    };
    let response: http.HttpResponse;
    try {
      response = await request.request(url, requestOptions);
    } catch (error) {
      request.destroy();
      throw ApiError.network(`${error}`);
    }
    request.destroy();
    const responseText: string = APIClient.responseText(response.result);
    if (response.responseCode === 401 || response.responseCode === 403) {
      throw ApiError.unauthorized();
    }
    if (response.responseCode >= 400) {
      throw APIClient.serverError(response.responseCode, responseText);
    }
    if (responseText.length === 0) {
      return new EmptyResponse() as T;
    }
    try {
      const parsed: Object = JSON.parse(responseText) as Object;
      const envelope: ResponseEnvelope = parsed as ResponseEnvelope;
      if (envelope.err_no !== undefined && envelope.err_no !== 0) {
        throw ApiError.server(envelope.err_no, envelope.err_msg ?? '请求失败');
      }
      return parsed as T;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw ApiError.decoding(`${error}`);
    }
  }

  async getServerInfo(): Promise<ServerInfo> {
    return this.request<ServerInfo>('GET', '/api/info');
  }

  async getAuthMe(): Promise<APIKeyUser> {
    return this.request<APIKeyUser>('GET', '/api/auth/me');
  }

  async getLives(): Promise<LiveInfo[]> {
    return this.request<LiveInfo[]>('GET', '/api/lives');
  }

  async addLives(reqs: AddLiveRequest[]): Promise<LiveInfo[]> {
    return this.request<LiveInfo[]>('POST', '/api/lives', reqs);
  }

  async deleteLive(id: string, deleteFiles: boolean): Promise<void> {
    await this.request<Object>('DELETE', `/api/lives/${APIClient.encodePathSegments(id)}`,
      new DeleteLiveBody(deleteFiles));
  }

  async startListen(id: string): Promise<LiveInfo> {
    return this.request<LiveInfo>('GET', `/api/lives/${APIClient.encodePathSegments(id)}/start`);
  }

  async stopListen(id: string): Promise<LiveInfo> {
    return this.request<LiveInfo>('GET', `/api/lives/${APIClient.encodePathSegments(id)}/stop`);
  }

  async resolveUrl(raw: string): Promise<string> {
    const result: ResolveURLResult = await this.request<ResolveURLResult>('GET',
      `/api/resolve-url?url=${encodeURIComponent(raw)}`);
    return result.url;
  }

  async getVideoLibrary(): Promise<VideoRoomInfo[]> {
    const values: VideoRoomInfoInit[] = await this.request<VideoRoomInfoInit[]>('GET', '/api/video-library');
    return values.map((value: VideoRoomInfoInit): VideoRoomInfo => new VideoRoomInfo(value));
  }

  async getVideoFiles(folderPath: string): Promise<VideoFileInfo[]> {
    const values: VideoFileInfoInit[] = await this.request<VideoFileInfoInit[]>('GET',
      `/api/video-files/${APIClient.encodePathSegments(folderPath)}`);
    return values.map((value: VideoFileInfoInit): VideoFileInfo => new VideoFileInfo(value));
  }

  async getHistoryAll(): Promise<WatchHistoryEntry[]> {
    return this.request<WatchHistoryEntry[]>('GET', '/api/history');
  }

  async getHistoryEntry(videoPath: string): Promise<WatchHistoryEntry | null> {
    try {
      return await this.request<WatchHistoryEntry>('GET',
        `/api/history/${APIClient.encodePathSegments(videoPath)}`);
    } catch (error) {
      if (error instanceof ApiError && error.statusCode === 404) {
        return null;
      }
      throw error instanceof Error ? error : new Error(`${error}`);
    }
  }

  async postHistory(entry: WatchHistoryEntry): Promise<void> {
    await this.request<Object>('POST', '/api/history', new HistoryPostBody(entry));
  }

  async deleteHistoryEntry(videoPath: string): Promise<void> {
    await this.request<Object>('DELETE', `/api/history/${APIClient.encodePathSegments(videoPath)}`);
  }

  async deleteFile(relPath: string): Promise<void> {
    await this.request<Object>('DELETE', `/api/file/${APIClient.encodePathSegments(relPath)}`);
  }

  async batchDeleteFiles(paths: string[]): Promise<void> {
    await this.request<Object>('POST', '/api/batch/file/delete', new BatchDeleteBody(paths));
  }

  async getServerConfig(): Promise<Object> {
    return this.request<Object>('GET', '/api/config');
  }

  async uploadBackup(target: BackupTarget, pkg: BackupPackage): Promise<BackupIdResult> {
    return this.request<BackupIdResult>('POST', '/api/backups', undefined,
      { baseURL: this.baseForTarget(target), rawBody: pkg.toJson(), authorize: target === 'main' });
  }

  async fetchBackupPackage(target: BackupTarget, id: string): Promise<BackupPackage> {
    const raw: Object = await this.request<Object>('GET', `/api/backups/${APIClient.encodePathSegments(id)}`,
      undefined, { baseURL: this.baseForTarget(target), authorize: target === 'main' });
    return BackupPackage.fromJson(JSON.stringify(raw));
  }

  async restoreBackup(body: RestoreRequestBody): Promise<RestoreResult> {
    return this.request<RestoreResult>('POST', '/api/backups/restore', body);
  }

  async getRestoreStatus(jobId: string): Promise<RestoreResult | null> {
    try {
      return await this.request<RestoreResult>('GET',
        `/api/backups/restore/status/${APIClient.encodePathSegments(jobId)}`);
    } catch (error) {
      if (error instanceof ApiError && error.statusCode === 404) {
        return null;
      }
      throw error instanceof Error ? error : new Error(`${error}`);
    }
  }

  private baseForTarget(target: BackupTarget): string {
    if (target === 'main') {
      return this.baseURL;
    }
    const provider: (() => string) | null = APIClient.backupBaseURLProvider;
    if (provider === null) {
      throw ApiError.invalidURL();
    }
    return APIClient.trimBase(provider());
  }

  private static trimBase(base: string): string {
    return base.trim().replace(/\/+$/, '');
  }

  private static isValidBase(base: string): boolean {
    return /^https?:\/\/[^\s/$.?#].*$/i.test(base);
  }

  private static absoluteURL(base: string, relative: string): string {
    if (/^https?:\/\//i.test(relative)) {
      return relative;
    }
    const normalizedBase: string = APIClient.trimBase(base);
    return `${normalizedBase}${relative.startsWith('/') ? '' : '/'}${relative}`;
  }

  private static responseText(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return '';
    }
    return JSON.stringify(result);
  }

  private static serverError(statusCode: number, responseText: string): ApiError {
    if (responseText.length > 0) {
      try {
        const parsed: Object = JSON.parse(responseText) as Object;
        const envelope: ResponseEnvelope = parsed as ResponseEnvelope;
        if (envelope.err_no !== undefined) {
          return ApiError.server(envelope.err_no === 0 ? statusCode : envelope.err_no,
            envelope.err_msg ?? '请求失败');
        }
        const sourceError: SourceErrorEnvelope = parsed as SourceErrorEnvelope;
        if (sourceError.error !== undefined) {
          return ApiError.server(sourceError.code ?? statusCode, sourceError.error);
        }
      } catch (_) {
      }
    }
    return ApiError.server(statusCode, responseText.trim().length > 0 ? responseText.trim() : '请求失败');
  }

  private static toRequestMethod(method: string): http.RequestMethod {
    switch (method.toUpperCase()) {
      case 'POST':
        return http.RequestMethod.POST;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      case 'HEAD':
        return http.RequestMethod.HEAD;
      case 'PUT':
        return http.RequestMethod.PUT;
      default:
        return http.RequestMethod.GET;
    }
  }
}
