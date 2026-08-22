export interface AvailableStreamInfo {
  format: string;
  quality: string;
  quality_name: string | null;
  description: string | null;
  width: number | null;
  height: number | null;
  bitrate: number | null;
  frame_rate: number | null;
  codec: string | null;
  audio_codec: string | null;
  attributes_for_stream_select: Object | null;
}

export interface LiveInfo {
  id: string;
  live_url: string | null;
  platform_cn_name: string | null;
  host_name: string | null;
  room_name: string | null;
  status: boolean | null;
  listening: boolean | null;
  recording: boolean | null;
  recording_preparing: boolean | null;
  initializing: boolean | null;
  last_start_time: string | null;
  last_start_time_unix: number | null;
  audio_only: boolean | null;
  nick_name: string | null;
  last_error: string | null;
  available_streams: AvailableStreamInfo[] | null;
  available_streams_updated_at: number | string | null;
}

export class AddLiveRequest {
  url: string;
  listen: boolean;

  constructor(url: string, listen: boolean = true) {
    this.url = url;
    this.listen = listen;
  }
}
