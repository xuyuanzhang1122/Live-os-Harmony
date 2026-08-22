import { media } from '@kit.MediaKit';
import { ProgressSource } from './ProgressTracker';

export type PlayerState = 'idle' | 'initialized' | 'prepared' | 'playing' | 'paused' | 'completed' |
  'stopped' | 'released' | 'error';
export type PlayerStateHandler = (state: PlayerState) => void;
export type PlayerErrorHandler = (code: number, message: string) => void;
export type PlayerNumberHandler = (value: number) => void;
export type BufferingUpdateHandler = (infoType: number, value: number) => void;

export class PlayerOperationError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

function toPlayerOperationError(error: Object): PlayerOperationError {
  const businessError: BusinessError = error as BusinessError;
  const code: number = Number.isFinite(businessError.code) ? businessError.code : -1;
  const message: string = businessError.message?.length > 0 ? businessError.message : `${error}`;
  return new PlayerOperationError(code, message);
}

function playbackRateFromNativeSpeed(speed: number): number {
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_0_50_X) {
    return 0.5;
  }
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_0_75_X) {
    return 0.75;
  }
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_1_25_X) {
    return 1.25;
  }
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_1_50_X) {
    return 1.5;
  }
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_2_00_X) {
    return 2.0;
  }
  if (speed === media.PlaybackSpeed.SPEED_FORWARD_3_00_X) {
    return 3.0;
  }
  return 1.0;
}

export interface PlayerAdapter {
  url: string;
  surfaceId: string;
  readonly duration: number;
  readonly currentTime: number;
  readonly state: PlayerState;
  prepare(): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  stop(): Promise<void>;
  reset(): Promise<void>;
  release(): Promise<void>;
  seek(timeMs: number): void;
  setSpeed(rate: number): void;
  setVolume(volume: number): void;
  onStateChange(handler: PlayerStateHandler): void;
  offStateChange(handler: PlayerStateHandler): void;
  onError(handler: PlayerErrorHandler): void;
  offError(handler: PlayerErrorHandler): void;
  onSeekDone(handler: PlayerNumberHandler): void;
  offSeekDone(handler: PlayerNumberHandler): void;
  onDurationUpdate(handler: PlayerNumberHandler): void;
  offDurationUpdate(handler: PlayerNumberHandler): void;
  onSpeedDone(handler: PlayerNumberHandler): void;
  offSpeedDone(handler: PlayerNumberHandler): void;
  onVolumeChange(handler: PlayerNumberHandler): void;
  offVolumeChange(handler: PlayerNumberHandler): void;
  onBufferingUpdate(handler: BufferingUpdateHandler): void;
  offBufferingUpdate(handler: BufferingUpdateHandler): void;
}

export type PlayerAdapterFactory = () => Promise<PlayerAdapter>;

class HarmonyPlayerAdapter implements PlayerAdapter {
  private readonly player: media.AVPlayer;
  private nativeStateHandler: ((state: media.AVPlayerState, reason: media.StateChangeReason) => void) | null = null;
  private nativeErrorHandler: ((error: BusinessError) => void) | null = null;
  private nativeSeekHandler: ((value: number) => void) | null = null;
  private nativeDurationHandler: ((value: number) => void) | null = null;
  private nativeSpeedHandler: ((value: number) => void) | null = null;
  private nativeVolumeHandler: ((value: number) => void) | null = null;
  private nativeBufferingHandler: ((infoType: media.BufferingInfoType, value: number) => void) | null = null;

  constructor(player: media.AVPlayer) {
    this.player = player;
  }

  get url(): string { return this.player.url ?? ''; }
  set url(value: string) { this.player.url = value; }
  get surfaceId(): string { return this.player.surfaceId ?? ''; }
  set surfaceId(value: string) { this.player.surfaceId = value; }
  get duration(): number { return this.player.duration; }
  get currentTime(): number { return this.player.currentTime; }
  get state(): PlayerState { return this.player.state; }

  async prepare(): Promise<void> {
    try {
      await this.player.prepare();
      this.player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
    } catch (error) {
      throw toPlayerOperationError(error);
    }
  }
  async play(): Promise<void> {
    try { await this.player.play(); } catch (error) { throw toPlayerOperationError(error); }
  }
  async pause(): Promise<void> {
    try { await this.player.pause(); } catch (error) { throw toPlayerOperationError(error); }
  }
  async stop(): Promise<void> {
    try { await this.player.stop(); } catch (error) { throw toPlayerOperationError(error); }
  }
  async reset(): Promise<void> {
    try { await this.player.reset(); } catch (error) { throw toPlayerOperationError(error); }
  }
  async release(): Promise<void> {
    try { await this.player.release(); } catch (error) { throw toPlayerOperationError(error); }
  }
  seek(timeMs: number): void { this.player.seek(timeMs, media.SeekMode.SEEK_CLOSEST); }
  setVolume(volume: number): void { this.player.setVolume(volume); }

  setSpeed(rate: number): void {
    let speed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    if (rate === 0.5) {
      speed = media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    } else if (rate === 0.75) {
      speed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    } else if (rate === 1.25) {
      speed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    } else if (rate === 1.5) {
      speed = media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    } else if (rate === 2.0) {
      speed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    } else if (rate === 3.0) {
      // 3x 自 API 13 起可用；目标设备支持，API 12 设备由异常路径降级为 2x。
      try {
        this.player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_3_00_X);
        return;
      } catch (_) {
        speed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
      }
    }
    this.player.setSpeed(speed);
  }

  onStateChange(handler: PlayerStateHandler): void {
    this.nativeStateHandler = (state: media.AVPlayerState, _reason: media.StateChangeReason): void => handler(state);
    this.player.on('stateChange', this.nativeStateHandler);
  }

  offStateChange(_handler: PlayerStateHandler): void {
    if (this.nativeStateHandler !== null) {
      this.player.off('stateChange', this.nativeStateHandler);
      this.nativeStateHandler = null;
    }
  }

  onError(handler: PlayerErrorHandler): void {
    this.nativeErrorHandler = (error: BusinessError): void => handler(error.code, error.message);
    this.player.on('error', this.nativeErrorHandler);
  }

  offError(_handler: PlayerErrorHandler): void {
    if (this.nativeErrorHandler !== null) {
      this.player.off('error', this.nativeErrorHandler);
      this.nativeErrorHandler = null;
    }
  }

  onSeekDone(handler: PlayerNumberHandler): void {
    this.nativeSeekHandler = (value: number): void => handler(value);
    this.player.on('seekDone', this.nativeSeekHandler);
  }

  offSeekDone(_handler: PlayerNumberHandler): void {
    if (this.nativeSeekHandler !== null) {
      this.player.off('seekDone', this.nativeSeekHandler);
      this.nativeSeekHandler = null;
    }
  }

  onDurationUpdate(handler: PlayerNumberHandler): void {
    this.nativeDurationHandler = (value: number): void => handler(value);
    this.player.on('durationUpdate', this.nativeDurationHandler);
  }

  offDurationUpdate(_handler: PlayerNumberHandler): void {
    if (this.nativeDurationHandler !== null) {
      this.player.off('durationUpdate', this.nativeDurationHandler);
      this.nativeDurationHandler = null;
    }
  }

  onSpeedDone(handler: PlayerNumberHandler): void {
    this.nativeSpeedHandler = (value: number): void => handler(playbackRateFromNativeSpeed(value));
    this.player.on('speedDone', this.nativeSpeedHandler);
  }

  offSpeedDone(_handler: PlayerNumberHandler): void {
    if (this.nativeSpeedHandler !== null) {
      this.player.off('speedDone', this.nativeSpeedHandler);
      this.nativeSpeedHandler = null;
    }
  }

  onVolumeChange(handler: PlayerNumberHandler): void {
    this.nativeVolumeHandler = (value: number): void => handler(value);
    this.player.on('volumeChange', this.nativeVolumeHandler);
  }

  offVolumeChange(_handler: PlayerNumberHandler): void {
    if (this.nativeVolumeHandler !== null) {
      this.player.off('volumeChange', this.nativeVolumeHandler);
      this.nativeVolumeHandler = null;
    }
  }

  onBufferingUpdate(handler: BufferingUpdateHandler): void {
    this.nativeBufferingHandler = (infoType: media.BufferingInfoType, value: number): void =>
      handler(infoType, value);
    this.player.on('bufferingUpdate', this.nativeBufferingHandler);
  }

  offBufferingUpdate(_handler: BufferingUpdateHandler): void {
    if (this.nativeBufferingHandler !== null) {
      this.player.off('bufferingUpdate', this.nativeBufferingHandler);
      this.nativeBufferingHandler = null;
    }
  }
}

async function createHarmonyPlayerAdapter(): Promise<PlayerAdapter> {
  try {
    return new HarmonyPlayerAdapter(await media.createAVPlayer());
  } catch (error) {
    throw toPlayerOperationError(error);
  }
}

export class PlayerController implements ProgressSource {
  onStateChange: PlayerStateHandler = (_state: PlayerState): void => {};
  onError: PlayerErrorHandler = (_code: number, _message: string): void => {};
  onSeekDone: PlayerNumberHandler = (_seconds: number): void => {};
  onDurationReady: PlayerNumberHandler = (_seconds: number): void => {};
  onSpeedChange: PlayerNumberHandler = (_rate: number): void => {};
  onBufferingUpdate: PlayerNumberHandler = (_percent: number): void => {};
  private readonly factory: PlayerAdapterFactory;
  private player: PlayerAdapter | null = null;
  private cachedState: PlayerState = 'idle';
  private cachedDurationMs: number = 0;
  private releaseTask: Promise<void> | null = null;
  private lifecycleToken: number = 0;

  constructor(factory: PlayerAdapterFactory = createHarmonyPlayerAdapter) {
    this.factory = factory;
  }

  get duration(): number {
    const value: number = this.player?.duration ?? this.cachedDurationMs;
    return Number.isFinite(value) && value > 0 ? value / 1000 : 0;
  }

  get currentTime(): number {
    const value: number = this.player?.currentTime ?? 0;
    return Number.isFinite(value) && value > 0 ? value / 1000 : 0;
  }

  get state(): PlayerState {
    return this.player?.state ?? this.cachedState;
  }

  get isPlaying(): boolean {
    return this.state === 'playing';
  }

  async setup(url: string, surfaceId: string): Promise<void> {
    const token: number = this.lifecycleToken + 1;
    this.lifecycleToken = token;
    if (url.length === 0 || surfaceId.length === 0) {
      this.reportError(-1, 'Missing playback URL or surface');
      return;
    }
    try {
      const player: PlayerAdapter = await this.factory();
      if (token !== this.lifecycleToken) {
        try { await player.release(); } catch (_) {}
        return;
      }
      this.player = player;
      this.releaseTask = null;
      this.bindEvents(player);
      player.url = url;
      player.surfaceId = surfaceId;
      await player.prepare();
      if (token !== this.lifecycleToken) {
        return;
      }
      this.publishDuration(player.duration);
      await player.play();
    } catch (error) {
      if (token === this.lifecycleToken) {
        this.reportOperationError(error);
      }
    }
  }

  async play(): Promise<void> {
    const player: PlayerAdapter | null = this.player;
    if (player === null || (player.state !== 'prepared' && player.state !== 'paused' &&
      player.state !== 'completed')) {
      return;
    }
    try {
      await player.play();
    } catch (error) {
      this.reportOperationError(error);
    }
  }

  async pause(): Promise<void> {
    const player: PlayerAdapter | null = this.player;
    if (player === null || player.state !== 'playing') {
      return;
    }
    try {
      await player.pause();
    } catch (error) {
      this.reportOperationError(error);
    }
  }

  seek(seconds: number): void {
    const player: PlayerAdapter | null = this.player;
    if (player === null || (player.state !== 'prepared' && player.state !== 'playing' &&
      player.state !== 'paused' && player.state !== 'completed')) {
      return;
    }
    const duration: number = this.duration;
    const target: number = Math.min(Math.max(Number.isFinite(seconds) ? seconds : 0, 0),
      duration > 0 ? duration : Number.MAX_VALUE);
    try {
      player.seek(Math.round(target * 1000));
    } catch (error) {
      this.reportOperationError(error);
    }
  }

  setSpeed(rate: number): void {
    const player: PlayerAdapter | null = this.player;
    if (player === null || (player.state !== 'prepared' && player.state !== 'playing' &&
      player.state !== 'paused' && player.state !== 'completed')) {
      return;
    }
    try {
      player.setSpeed(rate);
    } catch (error) {
      this.reportOperationError(error);
    }
  }

  setVolume(volume: number): void {
    const player: PlayerAdapter | null = this.player;
    if (player === null || (player.state !== 'prepared' && player.state !== 'playing' &&
      player.state !== 'paused' && player.state !== 'completed')) {
      return;
    }
    try {
      player.setVolume(Math.min(Math.max(Number.isFinite(volume) ? volume : 0, 0), 1));
    } catch (error) {
      this.reportOperationError(error);
    }
  }

  release(): Promise<void> {
    this.lifecycleToken += 1;
    if (this.releaseTask !== null) {
      return this.releaseTask;
    }
    const player: PlayerAdapter | null = this.player;
    if (player === null) {
      this.cachedState = 'released';
      this.releaseTask = Promise.resolve();
      return this.releaseTask;
    }
    this.releaseTask = this.performRelease(player);
    return this.releaseTask;
  }

  private async performRelease(player: PlayerAdapter): Promise<void> {
    try { await player.stop(); } catch (_) {}
    try { await player.reset(); } catch (_) {}
    this.unbindEvents(player);
    try { await player.release(); } catch (_) {}
    if (this.player === player) {
      this.player = null;
    }
    this.cachedState = 'released';
  }

  private bindEvents(player: PlayerAdapter): void {
    player.onStateChange(this.handleStateChange);
    player.onError(this.handleError);
    player.onSeekDone(this.handleSeekDone);
    player.onDurationUpdate(this.handleDurationUpdate);
    player.onSpeedDone(this.handleSpeedDone);
    player.onVolumeChange(this.handleVolumeChange);
    player.onBufferingUpdate(this.handleBufferingUpdate);
  }

  private unbindEvents(player: PlayerAdapter): void {
    player.offStateChange(this.handleStateChange);
    player.offError(this.handleError);
    player.offSeekDone(this.handleSeekDone);
    player.offDurationUpdate(this.handleDurationUpdate);
    player.offSpeedDone(this.handleSpeedDone);
    player.offVolumeChange(this.handleVolumeChange);
    player.offBufferingUpdate(this.handleBufferingUpdate);
  }

  private handleStateChange: PlayerStateHandler = (state: PlayerState): void => {
    this.cachedState = state;
    if (state === 'prepared' && this.player !== null) {
      this.publishDuration(this.player.duration);
    }
    this.onStateChange(state);
  };

  private handleError: PlayerErrorHandler = (code: number, message: string): void => {
    this.cachedState = 'error';
    this.onStateChange('error');
    this.onError(code, message);
  };

  private handleSeekDone: PlayerNumberHandler = (milliseconds: number): void => {
    this.onSeekDone(milliseconds / 1000);
  };

  private handleDurationUpdate: PlayerNumberHandler = (milliseconds: number): void => {
    this.publishDuration(milliseconds);
  };

  private handleSpeedDone: PlayerNumberHandler = (rate: number): void => {
    this.onSpeedChange(rate);
  };
  private handleVolumeChange: PlayerNumberHandler = (_volume: number): void => {};

  private handleBufferingUpdate: BufferingUpdateHandler = (infoType: number, value: number): void => {
    if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
      this.onBufferingUpdate(Math.min(Math.max(value, 0), 100));
    }
  };

  private publishDuration(milliseconds: number): void {
    if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
      return;
    }
    this.cachedDurationMs = milliseconds;
    this.onDurationReady(milliseconds / 1000);
  }

  private reportOperationError(error: Object): void {
    const businessError: BusinessError = error as BusinessError;
    const code: number = Number.isFinite(businessError.code) ? businessError.code : -1;
    const message: string = businessError.message?.length > 0 ? businessError.message : `${error}`;
    this.reportError(code, message);
  }

  private reportError(code: number, message: string): void {
    this.cachedState = 'error';
    this.onStateChange('error');
    this.onError(code, message);
  }
}
