export type PlaybackStatus = 'ready' | 'recording' | 'processing' | 'unsupported';

export interface VideoRoomInfoInit {
  host_name: string;
  platform: string;
  folder_path: string;
  video_count: number;
  total_size: number;
  latest_video_at: number;
  latest_video: string | null;
  recording: boolean;
  url: string | null;
}

export class VideoRoomInfo implements VideoRoomInfoInit {
  host_name: string;
  platform: string;
  folder_path: string;
  video_count: number;
  total_size: number;
  latest_video_at: number;
  latest_video: string | null;
  recording: boolean;
  url: string | null;

  constructor(value: VideoRoomInfoInit) {
    this.host_name = value.host_name;
    this.platform = value.platform;
    this.folder_path = value.folder_path;
    this.video_count = value.video_count;
    this.total_size = value.total_size;
    this.latest_video_at = value.latest_video_at;
    this.latest_video = value.latest_video;
    this.recording = value.recording;
    this.url = value.url;
  }

  roomId(): string {
    return this.folder_path;
  }
}

export interface VideoFileInfoInit {
  name: string;
  rel_path: string;
  size: number;
  mod_time: number | string;
  file_url: string | null;
  thumbnail_url: string | null;
  hls_url: string | null;
  recording: boolean | null;
  playback_status: PlaybackStatus | null;
}

export class VideoFileInfo implements VideoFileInfoInit {
  name: string;
  rel_path: string;
  size: number;
  mod_time: number | string;
  file_url: string | null;
  thumbnail_url: string | null;
  hls_url: string | null;
  recording: boolean | null;
  playback_status: PlaybackStatus | null;

  constructor(value: VideoFileInfoInit) {
    this.name = value.name;
    this.rel_path = value.rel_path;
    this.size = value.size;
    this.mod_time = value.mod_time;
    this.file_url = value.file_url;
    this.thumbnail_url = value.thumbnail_url;
    this.hls_url = value.hls_url;
    this.recording = value.recording;
    this.playback_status = value.playback_status;
  }

  isNativePlayable(): boolean {
    return VideoFileInfo.isNativePlayable(this.name) || VideoFileInfo.isNativePlayable(this.rel_path);
  }

  static isNativePlayable(path: string): boolean {
    const normalized: string = path.toLowerCase();
    return normalized.endsWith('.mp4') || normalized.endsWith('.m4v') || normalized.endsWith('.mov') ||
      normalized.endsWith('.ts');
  }
}
