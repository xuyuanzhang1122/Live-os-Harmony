import { PlaybackStatus } from '../model/VideoLibrary';

export const PLAYER_SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

export function timelineTarget(localX: number, width: number, duration: number): number {
  if (!Number.isFinite(localX) || !Number.isFinite(width) || width <= 0 ||
    !Number.isFinite(duration) || duration <= 0) {
    return 0;
  }
  const fraction: number = Math.min(Math.max(localX / width, 0), 1);
  return fraction * duration;
}

export function playbackErrorText(status: PlaybackStatus | null): string {
  if (status === 'recording') {
    return '正在录制，请稍后';
  }
  if (status === 'processing') {
    return '正在处理，请稍后';
  }
  return '视频暂时无法播放';
}
