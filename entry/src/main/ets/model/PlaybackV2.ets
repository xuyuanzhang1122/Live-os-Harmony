import { ApiError, ApiErrorType } from './Common';

export interface V2Error {
  code: string;
  message: string;
  retryable: boolean;
  retry_after_seconds?: number;
}

export class V2ApiError extends ApiError {
  readonly code: string;
  readonly retryable: boolean;
  readonly retryAfterSeconds: number;
  readonly requestId: string;

  constructor(status: number, error: V2Error, requestId: string) {
    super(status === 401 || status === 403 ? ApiErrorType.UNAUTHORIZED : ApiErrorType.SERVER, error.message, status);
    this.code = error.code;
    this.retryable = error.retryable;
    this.retryAfterSeconds = error.retry_after_seconds ?? 2;
    this.requestId = requestId;
  }
}

export interface V2Envelope<T> {
  data: T | null;
  error: V2Error | null;
  request_id: string;
}

export interface RecordingIdentity {
  recording_id: string;
  source_version: string;
}

export interface V2Recording extends RecordingIdentity {
  path: string;
  room: string;
  size_bytes: number;
  size_text: string;
}

export interface V2Recordings {
  items: V2Recording[];
  next_cursor: string;
  catalog_status: string;
}

export interface VideoCapability {
  codec: string;
  profiles: string[];
  max_level: number;
  max_width: number;
  max_height: number;
  max_fps: number;
  max_bit_depth: number;
  hdr: boolean;
}

export interface AudioCapability {
  codec: string;
  profiles: string[];
  max_channels: number;
  max_sample_rate: number;
}

export interface PlaybackCapabilities {
  containers: string[];
  protocols: string[];
  video: VideoCapability[];
  audio: AudioCapability[];
}

export interface CreatePlaybackSession extends RecordingIdentity {
  capabilities: PlaybackCapabilities;
}

export interface PlaybackSession extends RecordingIdentity {
  id: string;
  asset_version: string;
  status: string;
  decision: string;
  protocol?: string;
  url?: string;
  expires_at: number;
  token_expires_at?: number;
  refresh_after_seconds?: number;
  retry_after_seconds: number;
  error: V2Error | null;
}

export interface V2DeleteResult {
  recording_id: string;
  status: string;
  deleted_files: number;
  error: V2Error | null;
}

export interface V2BatchResult {
  items: V2DeleteResult[];
}

export interface V2BatchRequest {
  items: RecordingIdentity[];
}

export function validV2Error(error: V2Error | null): boolean {
  return error !== null && typeof error === 'object' && typeof error.code === 'string' &&
    error.code.length > 0 && typeof error.message === 'string' && typeof error.retryable === 'boolean' &&
    (error.retry_after_seconds === undefined || (Number.isFinite(error.retry_after_seconds) && error.retry_after_seconds > 0));
}

export function validRecordingIdentity(value: RecordingIdentity): boolean {
  return value !== null && typeof value === 'object' && typeof value.recording_id === 'string' &&
    value.recording_id.length > 0 && typeof value.source_version === 'string' && value.source_version.length > 0;
}

export function validateSession(session: PlaybackSession): void {
  if (!validRecordingIdentity(session) || typeof session.id !== 'string' || session.id.length === 0 ||
    typeof session.asset_version !== 'string' || !Number.isFinite(session.expires_at) || session.expires_at <= 0 ||
    !['ready', 'processing', 'paused', 'failed', 'cancelled'].includes(session.status) ||
    !['direct', 'remux', 'audio-transcode', 'video-transcode'].includes(session.decision) ||
    !Number.isFinite(session.retry_after_seconds) || session.retry_after_seconds < 0 ||
    (session.error !== null && !validV2Error(session.error))) {
    throw ApiError.decoding('播放会话字段或状态无效');
  }
  if (session.status === 'ready') {
    if (typeof session.url !== 'string' || session.url.length === 0 || session.asset_version.length === 0 ||
      !['file', 'hls'].includes(session.protocol ?? '') || session.error !== null ||
      !Number.isFinite(session.token_expires_at) || (session.token_expires_at ?? 0) <= 0 ||
      !Number.isFinite(session.refresh_after_seconds) || (session.refresh_after_seconds ?? -1) < 0) {
      throw ApiError.decoding('ready 会话缺少媒体或刷新信息');
    }
  } else if (session.url !== undefined || (session.status === 'failed' && session.error === null)) {
    throw ApiError.decoding('未就绪会话不能提供播放地址');
  }
}
