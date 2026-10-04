import { hilog } from '@kit.PerformanceAnalysisKit';
import avcap from 'libavcap.so';
import { PlaybackCapabilities, VideoCapability, AudioCapability } from '../model/PlaybackV2';

interface NativeCapability {
  profiles?: string[];
  fps?: number;
  level?: number;
  aac?: boolean;
}

export class PlayerCapabilities {
  static detect(): PlaybackCapabilities {
    let value: NativeCapability = {};
    try {
      const queried: NativeCapability = JSON.parse(avcap.query()) as NativeCapability;
      if (queried !== null && typeof queried === 'object') value = queried;
      hilog.info(0x0503, 'LiveOSCapability', 'confirmed decoder query: %{public}s', JSON.stringify(value));
    } catch (_) {}
    const video: VideoCapability[] = [];
    const audio: AudioCapability[] = [];
    const profiles: string[] = Array.isArray(value.profiles) ? value.profiles.filter((profile: string): boolean =>
      ['baseline', 'main', 'high'].includes(profile)) : [];
    if (profiles.length > 0 && (value.fps === 30 || value.fps === 60) && (value.level === 40 || value.level === 42)) {
      video.push({ codec: 'h264', profiles: profiles, max_level: value.level, max_width: 1920, max_height: 1080,
        max_fps: value.fps, max_bit_depth: 8, hdr: false });
    }
    if (value.aac === true) {
      audio.push({ codec: 'aac', profiles: ['lc'], max_channels: 2, max_sample_rate: 48000 });
    }
    return { containers: ['mp4', 'hls'], protocols: ['file', 'hls'], video: video, audio: audio };
  }
}
