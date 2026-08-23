import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProgressSource } from './ProgressTracker';

// 验证日志：任务书要求对 native 播放状态、时间单位（nativeMs → uiSeconds）、
// 退出清理链路给出可核对依据；真机可用 hilog 过滤 LiveOSPlayer 直接验证。
const DIAG_DOMAIN: number = 0x0503;
const DIAG_TAG: string = 'LiveOSPlayer';

function diag(message: string): void {
  hilog.info(DIAG_DOMAIN, DIAG_TAG, '%{public}s', message);
}

// 真机存在 pause/release Promise 悬挂的情况（TASK-4-fix-2 退出后音频继续的根因之一）：
// 关闭链路每一步都必须有上限时间，超时记录日志后继续走完，保证 stop/release 一定执行。
export function withTimeout<T>(task: Promise<T>, timeoutMs: number, label: string): Promise<T | null> {
  return new Promise<T | null>((resolve: (value: T | null) => void): void => {
    const timer: number = setTimeout((): void => {
      diag(`${label} timed out after ${timeoutMs}ms`);
      resolve(null);
    }, timeoutMs);
    task.then((value: T): void => {
      clearTimeout(timer);
      resolve(value);
    }).catch((error: Object): void => {
      clearTimeout(timer);
      diag(`${label} failed: ${error}`);
      resolve(null);
    });
  });
}

export type PlayerState = 'idle' | 'initialized' | 'prepared' | 'playing' | 'paused' | 'completed' |
  'stopped' | 'released' | 'error';
export type PlayerStateHandler = (state: PlayerState) => void;
export type PlayerErrorHandler = (code: number, message: string) => void;
export type PlayerNumberHandler = (value: number) => void;
export type PlayerVideoSizeHandler = (width: number, height: number) => void;
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
  onVideoSizeChange(handler: PlayerVideoSizeHandler): void;
  offVideoSizeChange(handler: PlayerVideoSizeHandler): void;
  onTimeUpdate(handler: PlayerNumberHandler): void;
  offTimeUpdate(handler: PlayerNumberHandler): void;
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
  private nativeVideoSizeHandler: ((width: number, height: number) => void) | null = null;
  private nativeTimeHandler: ((value: number) => void) | null = null;
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
      // SDK 定义：VIDEO_SCALE_TYPE_FIT（默认值）不保持宽高比，拉伸铺满 surface；
      // 等比留黑边的 SCALED_ASPECT 需 API 20。API 12 纪律下由页面按 videoSizeChange
      // 上报的宽高比布局 XComponent，surface 比例与视频一致时 FIT 拉伸无可感知形变。
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

  onVideoSizeChange(handler: PlayerVideoSizeHandler): void {
    this.nativeVideoSizeHandler = (width: number, height: number): void => handler(width, height);
    this.player.on('videoSizeChange', this.nativeVideoSizeHandler);
  }

  offVideoSizeChange(_handler: PlayerVideoSizeHandler): void {
    if (this.nativeVideoSizeHandler !== null) {
      this.player.off('videoSizeChange', this.nativeVideoSizeHandler);
      this.nativeVideoSizeHandler = null;
    }
  }

  onTimeUpdate(handler: PlayerNumberHandler): void {
    this.nativeTimeHandler = (value: number): void => handler(value);
    this.player.on('timeUpdate', this.nativeTimeHandler);
  }

  offTimeUpdate(_handler: PlayerNumberHandler): void {
    if (this.nativeTimeHandler !== null) {
      this.player.off('timeUpdate', this.nativeTimeHandler);
      this.nativeTimeHandler = null;
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
  onVideoSizeChange: PlayerVideoSizeHandler = (_width: number, _height: number): void => {};
  onTimeUpdate: PlayerNumberHandler = (_seconds: number): void => {};
  onSpeedChange: PlayerNumberHandler = (_rate: number): void => {};
  onBufferingUpdate: PlayerNumberHandler = (_percent: number): void => {};
  private readonly factory: PlayerAdapterFactory;
  private player: PlayerAdapter | null = null;
  private cachedState: PlayerState = 'idle';
  private cachedDurationMs: number = 0;
  private cachedCurrentTimeMs: number = 0;
  private hasCurrentTimeUpdate: boolean = false;
  private lastLoggedSecond: number = -1;
  private releaseTask: Promise<void> | null = null;
  private lifecycleToken: number = 0;
  private initializedWaitResolve: (() => void) | null = null;
  private initializedWaitReject: ((error: Error) => void) | null = null;

  constructor(factory: PlayerAdapterFactory = createHarmonyPlayerAdapter) {
    this.factory = factory;
  }

  get duration(): number {
    const nativeValue: number = this.player?.duration ?? 0;
    const value: number = this.cachedDurationMs > 0 ? this.cachedDurationMs : nativeValue;
    return Number.isFinite(value) && value > 0 ? value / 1000 : 0;
  }

  get currentTime(): number {
    const nativeValue: number = this.player?.currentTime ?? 0;
    const validNative: number = this.validNativeMilliseconds(nativeValue);
    const cachedValue: number = this.validNativeMilliseconds(this.cachedCurrentTimeMs);
    // API 12 真机可能只通过 timeUpdate 提供可靠时间；不要让 playing 状态下
    // 返回的 0/-1 覆盖已经收到的有效事件时间。
    const value: number = cachedValue > 0 ? cachedValue : validNative;
    return value / 1000;
  }

  refreshCurrentTime(): number {
    const nativeValue: number = this.player?.currentTime ?? 0;
    const validNative: number = this.validNativeMilliseconds(nativeValue);
    // 真机 timeUpdate 事件可能只上报一次后静默：轮询必须持续接受前进的 native 属性值，
    // 否则缓存停在最后一次事件值，进度条冻结。仅接受 >= 缓存的单调值：回退只可能来自
    // seek（由 seekDone/timeUpdate 事件更新缓存），过期属性值不允许覆盖事件时间。
    if (validNative > 0 && validNative >= this.cachedCurrentTimeMs) {
      this.cachedCurrentTimeMs = validNative;
      this.hasCurrentTimeUpdate = true;
    }
    return this.currentTime;
  }

  get state(): PlayerState {
    const nativeState: PlayerState | null = this.player?.state ?? null;
    return nativeState === null || nativeState === 'idle' ? this.cachedState : nativeState;
  }

  get isPlaying(): boolean {
    return this.state === 'playing';
  }

  async setup(url: string, surfaceId: string): Promise<void> {
    const token: number = this.lifecycleToken + 1;
    this.lifecycleToken = token;
    this.cachedDurationMs = 0;
    this.cachedCurrentTimeMs = 0;
    this.hasCurrentTimeUpdate = false;
    this.lastLoggedSecond = -1;
    diag(`setup url=${url.substring(0, 140)} surface=${surfaceId}`);
    if (url.length === 0 || surfaceId.length === 0) {
      this.reportError(-1, 'Missing playback URL or surface');
      return;
    }
    try {
      const player: PlayerAdapter = await this.factory();
      diag('factory done');
      if (token !== this.lifecycleToken) {
        try { await player.release(); } catch (_) {}
        return;
      }
      this.player = player;
      this.releaseTask = null;
      this.bindEvents(player);
      player.url = url;
      diag('url set');
      // url 赋值后进入 initialized 是异步事件：必须等状态就绪再设 surfaceId/prepare，
      // 否则真机会以 5400102（surfaceId 仅 initialized 态可设）拒绝并导致播放完全失败。
      await this.waitForInitialized(player, 10000);
      diag(`initialized ready, state=${player.state}`);
      player.surfaceId = surfaceId;
      diag(`surfaceId set, state=${player.state}`);
      await player.prepare();
      diag(`prepare done, state=${player.state}, durationMs=${player.duration}`);
      if (token !== this.lifecycleToken) {
        await this.release();
        return;
      }
      this.publishDuration(player.duration);
      await player.play();
      diag(`play done, state=${player.state}`);
      this.publishStateSnapshot(player, 'setup play promise');
    } catch (error) {
      diag(`setup failed: ${error}`);
      if (token === this.lifecycleToken) {
        this.reportOperationError(error);
        const failedPlayer: PlayerAdapter | null = this.player;
        if (failedPlayer !== null) {
          await this.release();
        }
      }
    }
  }

  async play(): Promise<void> {
    const player: PlayerAdapter | null = this.player;
    const state: PlayerState = player?.state ?? this.cachedState;
    diag(`play requested state=${state}`);
    if (player === null || (state !== 'prepared' && state !== 'paused' && state !== 'completed')) {
      diag(`play ignored state=${state}`);
      return;
    }
    try {
      await player.play();
      diag(`play completed state=${player.state}`);
      this.publishStateSnapshot(player, 'play promise');
    } catch (error) {
      this.reportOperationError(error);
    }
  }

  async pause(): Promise<void> {
    const player: PlayerAdapter | null = this.player;
    const state: PlayerState = player?.state ?? this.cachedState;
    diag(`pause requested state=${state}`);
    if (player === null || state !== 'playing') {
      diag(`pause ignored state=${state}`);
      return;
    }
    try {
      await player.pause();
      diag(`pause completed state=${player.state}`);
      this.publishStateSnapshot(player, 'pause promise');
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
    if (duration <= 0) {
      return;
    }
    const target: number = Math.min(Math.max(Number.isFinite(seconds) ? seconds : 0, 0), duration);
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
    if (player.state === 'playing') {
      diag('release pause begin');
      await withTimeout(player.pause(), 1500, 'release pause');
      diag(`release pause settled state=${player.state}`);
    }
    try {
      this.unbindEvents(player);
    } catch (error) {
      diag(`release unbind failed: ${error}`);
    }
    await withTimeout(player.stop(), 3000, 'release stop');
    await withTimeout(player.reset(), 3000, 'release reset');
    await withTimeout(player.release(), 3000, 'release native');
    diag(`release chain done finalState=${player.state}`);
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
    player.onVideoSizeChange(this.handleVideoSizeChange);
    player.onTimeUpdate(this.handleTimeUpdate);
    player.onSpeedDone(this.handleSpeedDone);
    player.onVolumeChange(this.handleVolumeChange);
    player.onBufferingUpdate(this.handleBufferingUpdate);
  }

  private unbindEvents(player: PlayerAdapter): void {
    player.offStateChange(this.handleStateChange);
    player.offError(this.handleError);
    player.offSeekDone(this.handleSeekDone);
    player.offDurationUpdate(this.handleDurationUpdate);
    player.offVideoSizeChange(this.handleVideoSizeChange);
    player.offTimeUpdate(this.handleTimeUpdate);
    player.offSpeedDone(this.handleSpeedDone);
    player.offVolumeChange(this.handleVolumeChange);
    player.offBufferingUpdate(this.handleBufferingUpdate);
  }

  private handleStateChange: PlayerStateHandler = (state: PlayerState): void => {
    diag(`state -> ${state}`);
    this.cachedState = state;
    if (state === 'initialized') {
      if (this.initializedWaitResolve !== null) {
        this.initializedWaitResolve();
      }
    } else if (state === 'error' && this.initializedWaitReject !== null) {
      this.initializedWaitReject(new Error('player entered error state while initializing'));
    }
    if (state === 'prepared' && this.player !== null) {
      this.publishDuration(this.player.duration);
    }
    this.onStateChange(state);
  };

  private handleError: PlayerErrorHandler = (code: number, message: string): void => {
    diag(`error code=${code} message=${message}`);
    this.cachedState = 'error';
    this.onStateChange('error');
    this.onError(code, message);
  };

  private handleSeekDone: PlayerNumberHandler = (milliseconds: number): void => {
    if (!Number.isFinite(milliseconds) || milliseconds < 0) {
      diag(`seek done ignored nativeMs=${milliseconds}`);
      return;
    }
    this.cachedCurrentTimeMs = milliseconds;
    this.hasCurrentTimeUpdate = true;
    this.onSeekDone(milliseconds / 1000);
  };

  private handleDurationUpdate: PlayerNumberHandler = (milliseconds: number): void => {
    this.publishDuration(milliseconds);
  };

  private handleVideoSizeChange: PlayerVideoSizeHandler = (width: number, height: number): void => {
    // width/height 带单位 px（HLS 切换分辨率时也会上报），页面只用其比例。
    diag(`video size ${width}x${height}`);
    this.onVideoSizeChange(width, height);
  };

  private handleTimeUpdate: PlayerNumberHandler = (milliseconds: number): void => {
    if (!Number.isFinite(milliseconds) || milliseconds < 0) {
      diag(`time update ignored nativeMs=${milliseconds}`);
      return;
    }
    this.cachedCurrentTimeMs = milliseconds;
    this.hasCurrentTimeUpdate = true;
    const uiSeconds: number = milliseconds / 1000;
    const wholeSecond: number = Math.floor(uiSeconds);
    if (wholeSecond !== this.lastLoggedSecond) {
      this.lastLoggedSecond = wholeSecond;
      diag(`time update nativeMs=${milliseconds} uiSeconds=${uiSeconds.toFixed(3)} durationSeconds=${this.duration.toFixed(3)}`);
    }
    this.onTimeUpdate(uiSeconds);
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

  private publishStateSnapshot(player: PlayerAdapter, source: string): void {
    const state: PlayerState = player.state;
    diag(`state snapshot source=${source} state=${state}`);
    if (state !== this.cachedState) {
      this.cachedState = state;
      this.onStateChange(state);
    }
  }

  private publishDuration(milliseconds: number): void {
    if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
      return;
    }
    this.cachedDurationMs = milliseconds;
    const uiSeconds: number = milliseconds / 1000;
    diag(`duration update nativeMs=${milliseconds} uiSeconds=${uiSeconds.toFixed(3)}`);
    this.onDurationReady(uiSeconds);
  }

  private validNativeMilliseconds(milliseconds: number): number {
    return Number.isFinite(milliseconds) && milliseconds > 0 ? milliseconds : 0;
  }

  private reportOperationError(error: Object): void {
    const businessError: BusinessError = error as BusinessError;
    const code: number = Number.isFinite(businessError.code) ? businessError.code : -1;
    const message: string = businessError.message?.length > 0 ? businessError.message : `${error}`;
    this.reportError(code, message);
  }

  private waitForInitialized(player: PlayerAdapter, timeoutMs: number): Promise<void> {
    if (player.state === 'initialized') {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      const timer: number = setTimeout((): void => {
        this.initializedWaitResolve = null;
        this.initializedWaitReject = null;
        reject(new Error(`timeout after ${timeoutMs}ms waiting for initialized state`));
      }, timeoutMs);
      this.initializedWaitResolve = (): void => {
        clearTimeout(timer);
        this.initializedWaitResolve = null;
        this.initializedWaitReject = null;
        resolve();
      };
      this.initializedWaitReject = (error: Error): void => {
        clearTimeout(timer);
        this.initializedWaitResolve = null;
        this.initializedWaitReject = null;
        reject(error);
      };
    });
  }

  private reportError(code: number, message: string): void {
    this.cachedState = 'error';
    this.onStateChange('error');
    this.onError(code, message);
  }
}
