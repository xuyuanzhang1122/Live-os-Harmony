import { http } from '@kit.NetworkKit';
import { ApiError, ApiErrorType, APIKeyUser, APIResponse, BatchDeleteResult, PlaybackResolveResult, ResolveURLResult, ServerInfo } from '../model/Common';
import { AddLiveRequest, LiveInfo } from '../model/LiveRoom';
import { VideoFileInfo, VideoFileInfoInit, VideoRoomInfo, VideoRoomInfoInit } from '../model/VideoLibrary';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { BackupIdResult, BackupPackage, RestoreRequestBody, RestoreResult } from '../model/BackupModels';

import { CreatePlaybackSession, PlaybackSession, RecordingIdentity, V2ApiError, V2BatchRequest, V2BatchResult, V2Envelope, V2Error, V2Recording, V2Recordings, validRecordingIdentity, validV2Error, validateSession } from '../model/PlaybackV2';

export type BackupTarget = 'main' | 'backup';

export interface APIRequestOptions {
  baseURL?: string;
  rawBody?: string;
  authorize?: boolean;
  v2?: boolean;
  timeout?: number;
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
  recording_id?: string;
  source_version?: string;
  video_path: string;
  video_name: string;
  position_seconds: number;
  duration_seconds: number;

  constructor(entry: WatchHistoryEntry) {
    this.recording_id = entry.recording_id;
    this.source_version = entry.source_version;
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
  private playbackAPI: 'auto' | 'v2' | 'legacy';

  constructor(baseURL: string, apiKey: string = '', playbackAPI: 'auto' | 'v2' | 'legacy' = 'auto') {
    this.baseURL = APIClient.trimBase(baseURL);
    this.apiKey = apiKey;
    this.playbackAPI = playbackAPI;
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
    if ((hasExpires && hasSignature) || /(?:\?|&)(?:_key|play_token)=/.test(url)) {
      return url;
    }
    const separator: string = url.indexOf('?') >= 0 ? '&' : '?';
    return `${url}${separator}_key=${encodeURIComponent(apiKey)}`;
  }

  static buildMediaUrl(base: string, apiKey: string, url: string): string {
    if (url.trim().length === 0 || !APIClient.isValidBase(base)) {
      throw ApiError.invalidURL();
    }
    const absolute: string = APIClient.absoluteURL(base, url);
    return APIClient.appendKeyIfUnsigned(absolute, APIClient.sameOrigin(base, absolute) ? apiKey : '');
  }

  static playbackRetrySeconds(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value)
      ? Math.min(10, Math.max(1, value)) : 2;
  }

  static canFallbackPlayback(error: Object): boolean {
    // 新服务端文件不存在的 JSON 404 不代表端点缺失。
    return error instanceof ApiError && error.type === ApiErrorType.SERVER &&
      (error.statusCode === 405 ||
        (error.statusCode === 404 && error.message.indexOf('404 page not found') >= 0));
  }

  static buildThumbnailUrl(base: string, apiKey: string, file: VideoFileInfo): string {
    const relative: string = file.thumbnail_url !== null && file.thumbnail_url.length > 0 ? file.thumbnail_url :
      `/api/thumbnail/${APIClient.encodePathSegments(file.rel_path)}`;
    return APIClient.buildMediaUrl(base, apiKey, relative);
  }

  static buildPlaybackUrl(base: string, apiKey: string, file: VideoFileInfo): string {
    // 鸿蒙 AVPlayer 依据 URI 后缀选择解封装器：HLS 地址必须以 .m3u8 结尾，
    // 否则以 .flv 等结尾的播放列表地址会被判为 5400106（不支持的封装格式）。
    let relative: string;
    if (file.hls_url !== null && file.hls_url.length > 0 &&
      APIClient.urlPathEndsWith(file.hls_url, '.m3u8')) {
      relative = file.hls_url;
    } else if (VideoFileInfo.isNativePlayable(file.name.length > 0 ? file.name : file.rel_path)) {
      relative = file.file_url !== null && file.file_url.length > 0 ? file.file_url :
        `/files/${APIClient.encodePathSegments(file.rel_path)}`;
    } else {
      relative = `/api/stream/hls/${APIClient.encodePathSegments(file.rel_path)}/playlist.m3u8`;
    }
    return APIClient.buildMediaUrl(base, apiKey, relative);
  }

  static urlPathEndsWith(url: string, suffix: string): boolean {
    const path: string = url.split(/[?#]/, 1)[0];
    return path.length > 0 && path.endsWith(suffix);
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
      readTimeout: opts.timeout ?? 15000,
      connectTimeout: opts.timeout ?? 15000,
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
    if (opts.v2 === true && !(response.responseCode === 404 && responseText.trim() === '404 page not found') &&
      response.responseCode !== 405) {
      let envelope: V2Envelope<T>;
      try { envelope = JSON.parse(responseText) as V2Envelope<T>; } catch (_) { throw ApiError.decoding('v2 响应不是 JSON'); }
      if (envelope === null || typeof envelope !== 'object' || typeof envelope.request_id !== 'string' ||
        envelope.request_id.length === 0 || envelope.error === undefined || envelope.data === undefined) {
        throw ApiError.decoding('v2 响应缺少 envelope 字段');
      }
      if (envelope.error !== null) {
        if (!validV2Error(envelope.error) || envelope.data !== null) throw ApiError.decoding('v2 错误结构无效');
        throw new V2ApiError(response.responseCode, envelope.error, envelope.request_id);
      }
      if (response.responseCode < 200 || response.responseCode >= 300 || envelope.data === null) {
        throw ApiError.decoding('v2 成功响应无效');
      }
      return envelope.data;
    }
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
        throw error instanceof Error ? error : new Error(`${error}`);
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

  async resolvePlayback(relPath: string): Promise<PlaybackResolveResult> {
    const response: APIResponse<PlaybackResolveResult> = await this.request<APIResponse<PlaybackResolveResult>>('GET',
      `/api/playback/resolve/${APIClient.encodePathSegments(relPath)}`);
    if (response === null || typeof response !== 'object' || response.data === null ||
      typeof response.data !== 'object' || typeof response.data.status !== 'string') {
      throw ApiError.decoding('播放解析响应缺少 data.status');
    }
    const result: PlaybackResolveResult = response.data;
    if (result.status !== 'ready' && result.status !== 'processing' &&
      result.status !== 'recording' && result.status !== 'failed') {
      throw ApiError.decoding(`未知播放解析状态: ${result.status}`);
    }
    if (result.status === 'ready') {
      if (typeof result.url !== 'string' || result.url.trim().length === 0) {
        throw ApiError.decoding('播放解析 ready 响应缺少 URL');
      }
      result.url = APIClient.buildMediaUrl(this.baseURL, this.apiKey, result.url);
    } else if (result.status === 'processing') {
      result.retry_after_seconds = APIClient.playbackRetrySeconds(result.retry_after_seconds);
    }
    return result;
  }

  async getVideoLibrary(): Promise<VideoRoomInfo[]> {
    const values: VideoRoomInfoInit[] = await this.request<VideoRoomInfoInit[]>('GET', '/api/video-library');
    return values.map((value: VideoRoomInfoInit): VideoRoomInfo => new VideoRoomInfo(value));
  }

  private async getLegacyVideoFiles(folderPath: string): Promise<VideoFileInfo[]> {
    const values: VideoFileInfoInit[] = await this.request<VideoFileInfoInit[]>('GET',
      `/api/video-files/${APIClient.encodePathSegments(folderPath)}`);
    return values.map((value: VideoFileInfoInit): VideoFileInfo => new VideoFileInfo(value));
  }

  async getRecordings(after: string = ''): Promise<V2Recordings> {
    const result: V2Recordings = await this.request<V2Recordings>('GET',
      `/api/v2/recordings?limit=100&after=${encodeURIComponent(after)}`, undefined, { v2: true });
    if (result === null || !Array.isArray(result.items) || result.catalog_status !== 'verified' ||
      typeof result.next_cursor !== 'string') throw ApiError.decoding('v2 录播目录未核验');
    const ids: string[] = [];
    for (const item of result.items) {
      if (!validRecordingIdentity(item) || typeof item.path !== 'string' || typeof item.room !== 'string' ||
        !Number.isSafeInteger(item.size_bytes) || item.size_bytes < 0 || typeof item.size_text !== 'string' ||
        item.size_text.length === 0 || ids.includes(item.recording_id)) throw ApiError.decoding('v2 录播条目无效');
      ids.push(item.recording_id);
    }
    return result;
  }

  async getVideoFiles(folderPath: string): Promise<VideoFileInfo[]> {
    if (this.playbackAPI === 'legacy') return this.getLegacyVideoFiles(folderPath);
    const records: V2Recording[] = [];
    const cursors: string[] = [];
    let cursor: string = '';
    try {
      do {
        const page: V2Recordings = await this.getRecordings(cursor);
        for (const record of page.items) {
          if (records.some((old: V2Recording): boolean => old.recording_id === record.recording_id)) {
            throw ApiError.decoding('v2 录播分页重复');
          }
          records.push(record);
        }
        cursor = page.next_cursor;
        if (cursor.length > 0 && cursors.includes(cursor)) throw ApiError.decoding('v2 录播分页游标重复');
        cursors.push(cursor);
      } while (cursor.length > 0);
      this.playbackAPI = 'v2';
    } catch (error) {
      if (this.playbackAPI === 'auto' && APIClient.canFallbackPlayback(error)) {
        this.playbackAPI = 'legacy';
        return this.getLegacyVideoFiles(folderPath);
      }
      throw error instanceof Error ? error : new Error(`${error}`);
    }
    // v2 稳定身份是权威；旧清单只补充缩略图与时间等展示元数据。
    let legacy: VideoFileInfo[] = [];
    try { legacy = await this.getLegacyVideoFiles(folderPath); } catch (_) {}
    return records.filter((record: V2Recording): boolean => record.room === folderPath).map((record: V2Recording): VideoFileInfo => {
      const previous: VideoFileInfo | undefined = legacy.find((file: VideoFileInfo): boolean => file.rel_path === record.path);
      return new VideoFileInfo({ name: previous?.name ?? record.path.split('/').pop() ?? record.path,
        rel_path: record.path, size: record.size_bytes, size_text: record.size_text,
        recording_id: record.recording_id, source_version: record.source_version,
        mod_time: previous?.mod_time ?? '', thumbnail_url: previous?.thumbnail_url ?? null,
        file_url: null, hls_url: null, recording: previous?.recording ?? null, playback_status: null });
    });
  }

  async createPlaybackSession(body: CreatePlaybackSession): Promise<PlaybackSession> {
    const session: PlaybackSession = await this.request<PlaybackSession>('POST', '/api/v2/playback-sessions', body, { v2: true });
    return this.normalizeSession(session);
  }

  async getPlaybackSession(id: string): Promise<PlaybackSession> {
    const session: PlaybackSession = await this.request<PlaybackSession>('GET',
      `/api/v2/playback-sessions/${encodeURIComponent(id)}`, undefined, { v2: true });
    return this.normalizeSession(session);
  }

  async cancelPlaybackSession(id: string): Promise<void> {
    const session: PlaybackSession = await this.request<PlaybackSession>('DELETE',
      `/api/v2/playback-sessions/${encodeURIComponent(id)}`, undefined, { v2: true });
    validateSession(session);
    if (session.status !== 'cancelled') throw ApiError.decoding('会话未取消');
  }

  private normalizeSession(session: PlaybackSession): PlaybackSession {
    // Go 的 omitempty 会省略临近硬过期边界的 0；其他缺失字段仍是契约错误。
    if (session !== null && session.status === 'ready' && session.refresh_after_seconds === undefined &&
      Number.isFinite(session.token_expires_at) && session.token_expires_at === session.expires_at &&
      session.expires_at <= Math.floor(Date.now() / 1000) + 60) {
      session.refresh_after_seconds = 0;
    }
    validateSession(session);
    if (session.status === 'ready') {
      const url: string = APIClient.absoluteURL(this.baseURL, session.url ?? '');
      if (!APIClient.sameOrigin(this.baseURL, url) || !/(?:\?|&)play_token=[^&#]+/.test(url) ||
        /(?:\?|&)_key=/.test(url) || url.includes('#')) throw ApiError.decoding('v2 媒体地址或授权无效');
      session.url = url;
    }
    return session;
  }

  async batchDeleteRecordings(files: VideoFileInfo[]): Promise<BatchDeleteResult[]> {
    if (files.length === 0 || files.length > 100) throw ApiError.decoding('批量删除数量必须为 1–100');
    const items: RecordingIdentity[] = files.map((file: VideoFileInfo): RecordingIdentity =>
      ({ recording_id: file.recording_id, source_version: file.source_version }));
    if (items.some((item: RecordingIdentity): boolean => !validRecordingIdentity(item)) ||
      new Set<string>(items.map((item: RecordingIdentity): string => item.recording_id)).size !== items.length) {
      throw ApiError.decoding('删除缺少或重复录播身份');
    }
    const body: V2BatchRequest = { items: items };
    const response: V2BatchResult = await this.request<V2BatchResult>('POST', '/api/v2/recordings/batch-delete', body, { v2: true });
    if (!Array.isArray(response.items)) throw ApiError.decoding('删除缺少逐项结果');
    const seen: string[] = [];
    for (const item of response.items) {
      if (item === null || !items.some((identity: RecordingIdentity): boolean => identity.recording_id === item.recording_id) ||
        seen.includes(item.recording_id) || !['deleted', 'failed'].includes(item.status) ||
        !Number.isSafeInteger(item.deleted_files) || item.deleted_files < 0 ||
        (item.status === 'deleted' ? item.error !== null : !validV2Error(item.error))) {
        throw ApiError.decoding('批量删除结果无效');
      }
      seen.push(item.recording_id);
    }
    return files.map((file: VideoFileInfo): BatchDeleteResult => {
      const item = response.items.find((value): boolean => value.recording_id === file.recording_id);
      return { path: file.rel_path, success: item?.status === 'deleted',
        message: item?.error?.message ?? (item === undefined ? '服务端未返回该录播的删除结果' : '') };
    });
  }

  usesLegacyPlayback(): boolean { return this.playbackAPI === 'legacy'; }

  async downloadThumbnail(url: string): Promise<ArrayBuffer | null> {
    let target: string = APIClient.buildMediaUrl(this.baseURL, this.apiKey, url);
    for (let attempt: number = 0; attempt < 2; attempt++) {
      const request: http.HttpRequest = http.createHttp();
      let response: http.HttpResponse;
      try {
        const headers: RequestHeaders = APIClient.sameOrigin(this.baseURL, target) && this.apiKey.length > 0 ?
          { Authorization: `Bearer ${this.apiKey}` } : {};
        response = await request.request(target, { method: http.RequestMethod.GET, header: headers,
          expectDataType: http.HttpDataType.ARRAY_BUFFER, readTimeout: 15000, connectTimeout: 15000, usingCache: false });
      } catch (_) { return null; } finally { request.destroy(); }
      if (response.responseCode === 200 && response.result instanceof ArrayBuffer) return response.result;
      if (attempt !== 0 || response.responseCode !== 401 || !APIClient.sameOrigin(this.baseURL, target)) return null;
      const match: RegExpMatchArray | null = target.match(/\/api\/thumbnail\/([^?#]+)/);
      if (match === null || !/(?:\?|&)sig=/.test(target)) return null;
      try {
        const path: string = match[1].split('/').map((part: string): string => decodeURIComponent(part)).join('/');
        const result: APIResponse<ResolveURLResult> = await this.request<APIResponse<ResolveURLResult>>('GET',
          `/api/signed-url?kind=thumbnail&path=${encodeURIComponent(path)}&expires_in=3600`);
        if (typeof result.data?.url !== 'string') return null;
        target = APIClient.buildMediaUrl(this.baseURL, this.apiKey, result.data.url);
      } catch (_) { return null; }
    }
    return null;
  }

  async probeServer(): Promise<boolean> {
    try {
      const info: ServerInfo = await this.request<ServerInfo>('GET', '/api/info', undefined, { timeout: 2000 });
      return typeof info.app_name === 'string' && info.app_name.toLowerCase().includes('bililive') &&
        typeof info.app_version === 'string' && info.app_version.length > 0;
    } catch (_) { return false; }
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

  async batchDeleteFiles(paths: string[]): Promise<BatchDeleteResult[]> {
    const response = await this.request<APIResponse<BatchDeleteResult[]>>(
      'POST', '/api/batch/file/delete', new BatchDeleteBody(paths));
    if (response === null || !Array.isArray(response.data)) {
      throw ApiError.decoding('批量删除响应缺少逐项结果');
    }
    const seen: string[] = [];
    for (const result of response.data) {
      if (result === null || typeof result.path !== 'string' || typeof result.success !== 'boolean' ||
        (result.message !== undefined && typeof result.message !== 'string') || seen.indexOf(result.path) >= 0) {
        throw ApiError.decoding('批量删除逐项结果无效');
      }
      seen.push(result.path);
    }
    return response.data;
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

  static sameOrigin(base: string, url: string): boolean {
    const baseOrigin: string = base.match(/^https?:\/\/[^/?#]+/i)?.[0].toLowerCase() ?? '';
    return baseOrigin.length > 0 && baseOrigin === (url.match(/^https?:\/\/[^/?#]+/i)?.[0].toLowerCase() ?? '');
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
