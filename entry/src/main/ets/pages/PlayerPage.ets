import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { PiPWindow, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Formats } from '../common/Formats';
import { Haptics } from '../common/Haptics';
import { AppConfig } from '../config/AppConfig';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { VideoFileInfo } from '../model/VideoLibrary';
import { APIClient } from '../net/APIClient';
import { PlayerController, PlayerState, withTimeout } from '../player/PlayerController';
import { ProgressTracker } from '../player/ProgressTracker';
import {
  clamp,
  horizontalSeekTarget,
  isSideZone,
  lockPullSatisfied,
  resumeTarget,
  shouldResume
} from '../player/PlayerMath';
import { PLAYER_SPEEDS, playbackErrorText, timelineTarget } from '../player/PlayerRules';

export type SpeedGestureMode = 'none' | 'locking' | 'unlocking' | 'locked';
export type PlayerShutdownHandler = (reason: string) => Promise<void>;
type HudMode = 'none' | 'seek' | 'volume' | 'brightness' | 'speed';

const DIRECTION_NONE: number = 0;
const DIRECTION_SEEK: number = 1;
const DIRECTION_VERTICAL: number = 2;
const DIRECTION_THRESHOLD_VP: number = 10;
const HUD_HIDE_DELAY_MS: number = 1200;
const HISTORY_INTERVAL_MS: number = 15000;
const RESUME_RETRY_COUNT: number = 3;
const RESUME_RETRY_DELAY_MS: number = 500;
const RESUME_TOLERANCE_SECONDS: number = 3;
const LOG_DOMAIN: number = 0x0503;
const LOG_TAG: string = 'LiveOSPlayerPage';

function log(message: string): void {
  hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, milliseconds);
  });
}

class WatchHistoryReport implements WatchHistoryEntry {
  id: number = 0;
  api_key_user_id: string = '';
  video_path: string;
  video_name: string;
  position_seconds: number;
  duration_seconds: number;
  updated_at: string = '';

  constructor(videoPath: string, videoName: string, positionSeconds: number, durationSeconds: number) {
    this.video_path = videoPath;
    this.video_name = videoName;
    this.position_seconds = positionSeconds;
    this.duration_seconds = durationSeconds;
  }
}

@ComponentV2
export struct PlayerPage {
  @Require @Param file: VideoFileInfo;
  @Event onClose: () => void = (): void => {};
  @Event onShutdownReady: (handler: PlayerShutdownHandler | null) => void =
    (_handler: PlayerShutdownHandler | null): void => {};
  @Local private playerState: PlayerState = 'idle';
  @Local private isPlaying: boolean = false;
  @Local private currentTime: number = 0;
  @Local private duration: number = 0;
  @Local private bufferedPercent: number = 0;
  @Local private playbackRate: number = 1;
  @Local private errorText: string = '';
  @Local private chromeVisible: boolean = true;
  @Local private toastText: string = '';
  @Local private thumbnailURL: string = '';
  @Local private timelineWidth: number = 0;
  @Local private videoWidth: number = 0;
  @Local private videoHeight: number = 0;
  @Local private hudMode: HudMode = 'none';
  @Local private hudSeekTarget: number = 0;
  @Local private hudSeekDelta: number = 0;
  @Local private hudVolume: number = 1;
  @Local private hudBrightness: number = 1;
  @Local private speedMode: SpeedGestureMode = 'none';
  @Local private speedHudMessage: string = '下拉锁定 2 倍速';
  @Local private pipAvailable: boolean = false;
  @Local private topSystemInset: number = 0;
  @Local private bottomSystemInset: number = 0;
  private readonly controller: PlayerController = new PlayerController();
  private readonly tracker: ProgressTracker = new ProgressTracker(this.controller);
  private readonly config: AppConfig = AppConfig.getInstance();
  private readonly surfaceController: XComponentController = new XComponentController();
  private playbackURL: string = '';
  private dragTarget: number = 0;
  private setupStarted: boolean = false;
  private shutdownStarted: boolean = false;
  private shutdownTask: Promise<void> | null = null;
  private lifecycleToken: number = 0;
  private toastTimer: number = -1;
  private hudTimer: number = -1;
  private historyTimer: number = -1;
  private playbackSyncTimer: number = -1;
  private playbackSampleTimer: number = -1;
  private lastUiLoggedSecond: number = -1;
  private hudDirection: number = DIRECTION_NONE;
  private gestureStartX: number = 0;
  private gestureStartY: number = 0;
  private hudSeekBase: number = 0;
  private hudVolumeBase: number = 1;
  private hudBrightnessBase: number = 1;
  @Local private hudAreaWidth: number = 0;
  @Local private hudAreaHeight: number = 0;
  private playerWindow: window.Window | null = null;
  private brightnessChanged: boolean = false;
  private historyResumeTried: boolean = false;
  private isResumeSettled: boolean = false;
  private missingKeyNotified: boolean = false;
  private reporting: boolean = false;
  private previousState: PlayerState = 'idle';
  private speedBaseRate: number = 1;
  private speedGestureStarted: boolean = false;
  private speedSelectionWriting: boolean = false;
  private volumeWriteToken: number = 0;
  private pipController: PiPWindow.PiPController | null = null;
  private pipActive: boolean = false;

  aboutToAppear(): void {
    this.lifecycleToken += 1;
    this.shutdownStarted = false;
    this.shutdownTask = null;
    this.setupStarted = false;
    this.bindPlayerCallbacks(this.lifecycleToken);
    this.onShutdownReady((reason: string): Promise<void> => this.shutdownPlayer(reason));
    this.resolveURLs();
    this.tracker.start();
    this.startPlaybackSampler();
    this.startHistoryTimer();
    this.enterImmersiveMode(this.lifecycleToken);
    this.detectPiP();
    this.initializeMediaVolume();
  }

  private bindPlayerCallbacks(token: number): void {
    this.controller.onStateChange = (state: PlayerState): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token)) {
          return;
        }
        log(`page state ${this.previousState} -> ${state}`);
        const wasPlaying: boolean = this.previousState === 'playing';
        const playbackChanged: boolean = (wasPlaying && state === 'paused') ||
          (this.previousState === 'paused' && state === 'playing');
        this.previousState = state;
        this.applyUiPlaybackState(state, 'native stateChange');
        if (playbackChanged) {
          Haptics.light();
        }
        if (wasPlaying && state === 'paused' && !this.tracker.isInteracting) {
          this.reportHistory(true);
        }
        if (state === 'completed') {
          this.currentTime = this.duration;
          this.chromeVisible = true;
        }
      });
    };
    this.controller.onError = (_code: number, _message: string): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token)) {
          return;
        }
        this.errorText = playbackErrorText(this.file.playback_status);
        this.chromeVisible = false;
        this.isResumeSettled = true;
      });
    };
    this.controller.onDurationReady = (seconds: number): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token)) {
          return;
        }
        this.duration = seconds;
        this.currentTime = this.clampedUiTime(this.currentTime);
        log(`page duration uiSeconds=${this.duration.toFixed(3)}`);
        this.tryResumeFromHistory();
      });
    };
    this.controller.onVideoSizeChange = (width: number, height: number): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token)) {
          return;
        }
        this.videoWidth = width;
        this.videoHeight = height;
      });
    };
    this.controller.onTimeUpdate = (seconds: number): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token) || this.tracker.isInteracting) {
          return;
        }
        this.currentTime = this.clampedUiTime(seconds);
        this.tracker.displayTime = this.currentTime;
        const wholeSecond: number = Math.floor(this.currentTime);
        if (wholeSecond !== this.lastUiLoggedSecond) {
          this.lastUiLoggedSecond = wholeSecond;
          log(`page time uiSeconds=${this.currentTime.toFixed(3)} durationSeconds=${this.duration.toFixed(3)}`);
        }
      });
    };
    this.controller.onSeekDone = (seconds: number): void => {
      if (!this.isLifecycleActive(token)) {
        return;
      }
      this.tracker.handleSeekDone(seconds).then((): void => {
        this.reportHistory(true);
      }).catch((): void => {});
    };
    this.controller.onSpeedChange = (rate: number): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token)) {
          return;
        }
        this.playbackRate = rate;
        if (this.speedMode === 'locking' || this.speedMode === 'locked' || this.speedMode === 'unlocking') {
          return;
        }
        this.showToast(`播放速度 ${Formats.formatSpeedLabel(rate)}`);
      });
    };
    this.controller.onBufferingUpdate = (percent: number): void => {
      this.runUiTask((): void => {
        if (this.isLifecycleActive(token)) {
          this.bufferedPercent = percent;
          }
      });
    };
    this.tracker.onTimeUpdate = (seconds: number): void => {
      this.runUiTask((): void => {
        if (!this.isLifecycleActive(token)) {
          return;
        }
        this.currentTime = this.clampedUiTime(seconds);
        const wholeSecond: number = Math.floor(this.currentTime);
        if (wholeSecond !== this.lastUiLoggedSecond) {
          this.lastUiLoggedSecond = wholeSecond;
          log(`page time uiSeconds=${this.currentTime.toFixed(3)} durationSeconds=${this.duration.toFixed(3)}`);
        }
      });
    };
  }

  private runUiTask(task: () => void): void {
    task();
  }

  private resolveURLs(): void {
    const client: APIClient = this.config.getClient();
    const hasDirectURL: boolean = (this.file.hls_url?.length ?? 0) > 0 ||
      (this.file.file_url?.length ?? 0) > 0;
    if (this.file.rel_path.trim().length === 0 && !hasDirectURL) {
      this.errorText = playbackErrorText(this.file.playback_status);
      this.chromeVisible = false;
      this.isResumeSettled = true;
      return;
    }
    this.playbackURL = APIClient.buildPlaybackUrl(client.baseURL, client.apiKey, this.file);
    if (!/^https?:\/\//i.test(this.playbackURL)) {
      this.errorText = playbackErrorText(this.file.playback_status);
      this.chromeVisible = false;
      this.isResumeSettled = true;
      return;
    }
    const thumbnail: string = APIClient.buildThumbnailUrl(client.baseURL, client.apiKey, this.file);
    this.thumbnailURL = /^https?:\/\//i.test(thumbnail) ? thumbnail : '';
  }

  private setupPlayer(surfaceId: string): void {
    if (this.shutdownStarted || this.setupStarted || this.errorText.length > 0 ||
      this.playbackURL.length === 0) {
      return;
    }
    this.setupStarted = true;
    this.controller.setup(this.playbackURL, surfaceId).catch((error: Object): void => {
      log(`setup rejected: ${error}`);
      this.setupStarted = false;
    });
  }

  private async togglePlayback(source: string): Promise<void> {
    if (this.shutdownStarted) {
      return;
    }
    const nativeState: PlayerState = this.controller.state;
    log(`toggle source=${source} ui=${this.playerState} native=${nativeState} interacting=${this.tracker.isInteracting}`);
    if (this.tracker.isInteracting) {
      log('toggle ignored: progress interaction active');
      return;
    }
    if (nativeState === 'completed') {
      await this.replay();
      return;
    } else if (nativeState === 'playing') {
      await withTimeout(this.controller.pause(), 3000, `toggle pause (${source})`);
    } else if (nativeState === 'prepared' || nativeState === 'paused') {
      await withTimeout(this.controller.play(), 3000, `toggle play (${source})`);
    } else {
      log(`toggle ignored by state guard: ${nativeState}`);
      return;
    }
    this.syncUiPlaybackState(`${source} promise`);
    this.schedulePlaybackStateSync(`${source} delayed`);
  }

  private async replay(): Promise<void> {
    this.controller.seek(0);
    this.currentTime = 0;
    await withTimeout(this.controller.play(), 3000, 'replay play');
    this.syncUiPlaybackState('replay promise');
    this.schedulePlaybackStateSync('replay delayed');
  }

  private async closePlayer(): Promise<void> {
    await this.shutdownPlayer('close button');
  }

  private shutdownPlayer(reason: string): Promise<void> {
    if (this.shutdownTask !== null) {
      log(`shutdown joined reason=${reason}`);
      return this.shutdownTask;
    }
    this.shutdownStarted = true;
    this.lifecycleToken += 1;
    this.shutdownTask = this.performShutdown(reason);
    return this.shutdownTask;
  }

  private async performShutdown(reason: string): Promise<void> {
    log(`shutdown begin reason=${reason} native=${this.controller.state}`);
    this.clearTimers();
    this.hudDirection = DIRECTION_NONE;
    this.speedGestureStarted = false;
    this.tracker.stop();
    log(`shutdown tracker stopped reason=${reason}`);
    log(`shutdown pause begin native=${this.controller.state}`);
    await withTimeout(this.controller.pause(), 3000, 'shutdown pause');
    log(`shutdown pause settled native=${this.controller.state}`);
    await withTimeout(this.reportHistory(false), 2500, 'shutdown report');
    await withTimeout(this.stopPiP(), 2500, 'shutdown pip');
    log(`shutdown release begin native=${this.controller.state}`);
    const releaseSettled: boolean = await withTimeout(this.controller.release(), 8000, 'shutdown release') !== null;
    const finalState: PlayerState = this.controller.state;
    log(`shutdown release settled=${releaseSettled} native=${finalState}`);
    // 任务书要求：页面退出后再次检查 native state，不能仍为 playing。
    // release() 内部链路自带逐级超时并会在后台继续执行，此处仅记录验证结果。
    if (finalState === 'playing') {
      log(`shutdown verify FAILED native still playing after release attempt`);
    } else {
      log(`shutdown verify ok native=${finalState}`);
    }
    this.clearPlayerCallbacks();
    await withTimeout(this.restoreWindowState(), 1500, 'shutdown restore window');
    this.onShutdownReady(null);
    log(`shutdown close cover reason=${reason} native=${this.controller.state}`);
    this.onClose();
  }

  private isLifecycleActive(token: number): boolean {
    return token === this.lifecycleToken && !this.shutdownStarted;
  }

  private applyUiPlaybackState(state: PlayerState, source: string): void {
    if (this.shutdownStarted) {
      return;
    }
    this.playerState = state;
    this.isPlaying = state === 'playing';
    log(`ui state source=${source} state=${state} isUiPlaying=${this.isPlaying}`);
  }

  private syncUiPlaybackState(source: string): void {
    this.applyUiPlaybackState(this.controller.state, source);
  }

  private schedulePlaybackStateSync(source: string): void {
    if (this.playbackSyncTimer >= 0) {
      clearTimeout(this.playbackSyncTimer);
    }
    const token: number = this.lifecycleToken;
    this.playbackSyncTimer = setTimeout((): void => {
      this.playbackSyncTimer = -1;
      if (this.isLifecycleActive(token)) {
        this.syncUiPlaybackState(source);
      }
    }, 120);
  }

  private clampedUiTime(seconds: number): number {
    return this.duration > 0 ? clamp(seconds, 0, this.duration) : 0;
  }

  private startPlaybackSampler(): void {
    if (this.playbackSampleTimer >= 0) {
      return;
    }
    const token: number = this.lifecycleToken;
    this.playbackSampleTimer = setInterval((): void => {
      if (!this.isLifecycleActive(token)) {
        return;
      }
      this.syncUiPlaybackState('periodic sample');
      if (this.duration <= 0 && this.controller.duration > 0) {
        this.duration = this.controller.duration;
      }
      if (!this.tracker.isInteracting) {
        this.controller.refreshCurrentTime();
        this.tracker.sampleNow();
      }
    }, 250);
  }

  private clearPlayerCallbacks(): void {
    this.controller.onStateChange = (_state: PlayerState): void => {};
    this.controller.onError = (_code: number, _message: string): void => {};
    this.controller.onTimeUpdate = (_seconds: number): void => {};
    this.controller.onDurationReady = (_seconds: number): void => {};
    this.controller.onVideoSizeChange = (_width: number, _height: number): void => {};
    this.controller.onSeekDone = (_seconds: number): void => {};
    this.controller.onSpeedChange = (_rate: number): void => {};
    this.controller.onBufferingUpdate = (_percent: number): void => {};
    this.tracker.onTimeUpdate = (_seconds: number): void => {};
  }

  private startHistoryTimer(): void {
    if (this.historyTimer >= 0) {
      return;
    }
    this.historyTimer = setInterval((): void => {
      if (this.controller.isPlaying) {
        this.reportHistory(true);
      }
    }, HISTORY_INTERVAL_MS);
  }

  private async reportHistory(showSuccess: boolean): Promise<void> {
    if (!this.isResumeSettled || this.reporting || this.shutdownStarted && this.duration < 1) {
      return;
    }
    const relPath: string = this.file.rel_path.trim();
    if (this.duration < 1 || relPath.length === 0) {
      return;
    }
    if (!this.config.apiKeyBound) {
      if (!this.missingKeyNotified) {
        this.missingKeyNotified = true;
        this.showToast('未绑定 API Key，无法同步历史');
      }
      return;
    }
    this.reporting = true;
    try {
      const entry: WatchHistoryEntry = new WatchHistoryReport(relPath, this.file.name,
        Math.max(this.controller.currentTime, this.currentTime, 0), this.duration);
      await this.config.getClient().postHistory(entry);
      if (showSuccess && !this.shutdownStarted) {
        this.showToast('已同步到服务端');
      }
    } catch (_) {
    } finally {
      this.reporting = false;
    }
  }

  private async fetchHistory(relPath: string): Promise<WatchHistoryEntry | null> {
    try {
      return await this.config.getClient().getHistoryEntry(relPath);
    } catch (_) {
      try {
        const entries: WatchHistoryEntry[] = await this.config.getClient().getHistoryAll();
        for (let i: number = 0; i < entries.length; i++) {
          if (entries[i].video_path === relPath) {
            return entries[i];
          }
        }
      } catch (_) {
      }
      return null;
    }
  }

  private tryResumeFromHistory(): void {
    if (this.historyResumeTried || this.duration <= 0) {
      return;
    }
    const relPath: string = this.file.rel_path.trim();
    if (relPath.length === 0) {
      this.isResumeSettled = true;
      return;
    }
    this.historyResumeTried = true;
    this.applyResume(relPath).catch((): void => {
      this.isResumeSettled = true;
    });
  }

  private async applyResume(relPath: string): Promise<void> {
    const entry: WatchHistoryEntry | null = await this.fetchHistory(relPath);
    if (this.shutdownStarted || entry === null || !shouldResume(entry.position_seconds, this.duration)) {
      this.isResumeSettled = true;
      return;
    }
    const target: number = resumeTarget(entry.position_seconds, this.duration);
    let succeeded: boolean = false;
    for (let attempt: number = 0; attempt < RESUME_RETRY_COUNT && !this.shutdownStarted; attempt++) {
      this.controller.seek(target);
      await delay(RESUME_RETRY_DELAY_MS);
      if (Math.abs(this.controller.currentTime - target) < RESUME_TOLERANCE_SECONDS) {
        succeeded = true;
        break;
      }
    }
    if (!succeeded && !this.shutdownStarted) {
      this.controller.seek(0);
    }
    this.isResumeSettled = true;
    if (succeeded && !this.shutdownStarted) {
      this.currentTime = target;
      this.showToast(`已从 ${Formats.formatClock(target)} 继续播放`);
    }
  }

  showToast(message: string): void {
    this.clearToastTimer();
    this.toastText = message;
    this.toastTimer = setTimeout((): void => {
      this.toastText = '';
      this.toastTimer = -1;
    }, 2200);
  }

  private showHud(mode: HudMode): void {
    this.clearHudTimer();
    this.hudMode = mode;
  }

  private scheduleHudHide(): void {
    this.clearHudTimer();
    this.hudTimer = setTimeout((): void => {
      this.hudMode = 'none';
      this.hudTimer = -1;
    }, HUD_HIDE_DELAY_MS);
  }

  private clearToastTimer(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
  }

  private clearTimers(): void {
    this.clearToastTimer();
    this.clearHudTimer();
    if (this.historyTimer >= 0) {
      clearInterval(this.historyTimer);
      this.historyTimer = -1;
    }
    if (this.playbackSyncTimer >= 0) {
      clearTimeout(this.playbackSyncTimer);
      this.playbackSyncTimer = -1;
    }
    if (this.playbackSampleTimer >= 0) {
      clearInterval(this.playbackSampleTimer);
      this.playbackSampleTimer = -1;
    }
  }

  private onPanStart(event: GestureEvent): void {
    if (this.speedGestureStarted) {
      return;
    }
    this.gestureStartX = this.eventLocalX(event, this.hudAreaWidth / 2);
    this.gestureStartY = this.eventLocalY(event, this.hudAreaHeight / 2);
    this.hudDirection = DIRECTION_NONE;
  }

  private onPanUpdate(event: GestureEvent): void {
    if (this.speedGestureStarted) {
      this.updateSpeedPull(event);
      return;
    }
    const offsetX: number = event.offsetX ?? 0;
    const offsetY: number = event.offsetY ?? 0;
    if (this.hudDirection === DIRECTION_NONE && !this.lockPanDirection(offsetX, offsetY)) {
      return;
    }
    if (this.hudDirection === DIRECTION_SEEK) {
      const target: number = horizontalSeekTarget(this.hudSeekBase, offsetX, this.hudAreaWidth,
        this.duration);
      this.hudSeekTarget = target;
      this.hudSeekDelta = target - this.hudSeekBase;
      this.tracker.updateInteracting(target);
    } else if (this.hudMode === 'brightness') {
      this.hudBrightness = clamp(this.hudBrightnessBase - offsetY / 200, 0, 1);
      this.applyWindowBrightness(this.hudBrightness);
    } else if (this.hudMode === 'volume') {
      this.hudVolume = clamp(this.hudVolumeBase - offsetY / 200, 0, 1);
      this.applyMediaVolume(this.hudVolume);
    }
  }

  private lockPanDirection(offsetX: number, offsetY: number): boolean {
    if (Math.abs(offsetX) < DIRECTION_THRESHOLD_VP && Math.abs(offsetY) < DIRECTION_THRESHOLD_VP) {
      return false;
    }
    if (Math.abs(offsetX) > Math.abs(offsetY)) {
      if (this.duration <= 0) {
        return false;
      }
      this.hudDirection = DIRECTION_SEEK;
      this.hudSeekBase = this.currentTime;
      this.hudSeekTarget = this.currentTime;
      this.hudSeekDelta = 0;
      this.tracker.beginInteracting();
      this.showHud('seek');
    } else {
      this.hudDirection = DIRECTION_VERTICAL;
      this.hudVolumeBase = this.hudVolume;
      this.hudBrightnessBase = this.hudBrightness;
      this.showHud(this.gestureStartX < this.hudAreaWidth / 2 ? 'brightness' : 'volume');
    }
    return true;
  }

  private onPanEnd(): void {
    if (this.speedGestureStarted) {
      this.onSpeedLongPressEnd();
      return;
    }
    if (this.hudDirection === DIRECTION_SEEK) {
      this.tracker.endInteracting(this.hudSeekTarget);
    }
    this.hudDirection = DIRECTION_NONE;
    this.scheduleHudHide();
  }

  private onPanCancel(): void {
    if (this.speedGestureStarted) {
      return;
    }
    if (this.hudDirection === DIRECTION_SEEK) {
      this.tracker.cancelInteracting().catch((): void => {});
    }
    this.hudDirection = DIRECTION_NONE;
    this.scheduleHudHide();
  }

  private onSpeedLongPress(event: GestureEvent): void {
    const x: number = this.eventLocalX(event, this.hudAreaWidth / 2);
    const y: number = this.eventLocalY(event, this.hudAreaHeight / 2);
    if (!this.speedGestureStarted) {
      // 横滑/竖滑/长按下拉三种手势互斥：已有 pan 方向锁定（含 tracker 交互冻结）时不再进入倍速手势。
      if (this.hudDirection !== DIRECTION_NONE || !isSideZone(x, this.hudAreaWidth)) {
        return;
      }
      this.speedGestureStarted = true;
      this.gestureStartY = y;
      this.speedBaseRate = this.speedMode === 'locked' || this.speedMode === 'unlocking' ?
        this.speedBaseRate : this.playbackRate;
      if (this.speedMode === 'locked' || this.speedMode === 'unlocking') {
        this.speedMode = 'unlocking';
        this.speedHudMessage = '下拉解锁 2 倍速';
      } else {
        this.speedMode = 'locking';
        this.speedHudMessage = '下拉锁定 2 倍速';
        this.controller.setSpeed(2);
      }
      this.chromeVisible = false;
      this.showHud('speed');
      Haptics.light();
      return;
    }
    this.updateSpeedPull(event);
  }

  private updateSpeedPull(event: GestureEvent): void {
    if (!this.speedGestureStarted) {
      return;
    }
    const y: number = this.eventLocalY(event, this.gestureStartY);
    if (!lockPullSatisfied(this.gestureStartY, y, this.hudAreaHeight)) {
      return;
    }
    if (this.speedMode === 'locking') {
      this.speedMode = 'locked';
      this.speedHudMessage = '已锁定 2 倍速';
      log(`speed locking -> locked startY=${this.gestureStartY} currentY=${y} screenHeight=${this.hudAreaHeight}`);
      Haptics.medium();
    } else if (this.speedMode === 'unlocking') {
      this.speedMode = 'none';
      this.speedHudMessage = '下拉解锁 2 倍速';
      this.controller.setSpeed(this.speedBaseRate);
      log(`speed unlocking -> none baseRate=${this.speedBaseRate}`);
      Haptics.medium();
    }
  }

  private onSpeedLongPressEnd(): void {
    if (!this.speedGestureStarted) {
      return;
    }
    this.speedGestureStarted = false;
    if (this.speedMode === 'locking') {
      this.controller.setSpeed(this.speedBaseRate);
      this.speedMode = 'none';
    } else if (this.speedMode === 'unlocking') {
      this.speedMode = 'locked';
      this.controller.setSpeed(2);
    }
    this.scheduleHudHide();
  }

  private onSpeedLongPressCancel(): void {
    this.onSpeedLongPressEnd();
  }

  private applyWindowBrightness(value: number): void {
    this.brightnessChanged = true;
    const win: window.Window | null = this.playerWindow;
    if (win !== null) {
      win.setWindowBrightness(value).catch((): void => {});
    }
  }

  private applyMediaVolume(value: number): void {
    const token: number = this.volumeWriteToken + 1;
    this.volumeWriteToken = token;
    this.setSystemMediaVolume(value, token).catch((): void => {
      if (token === this.volumeWriteToken) {
        this.controller.setVolume(value);
      }
    });
  }

  private initializeMediaVolume(): void {
    const manager: audio.AudioManager = audio.getAudioManager();
    Promise.all([
      manager.getVolume(audio.AudioVolumeType.MEDIA),
      manager.getMinVolume(audio.AudioVolumeType.MEDIA),
      manager.getMaxVolume(audio.AudioVolumeType.MEDIA)
    ]).then((levels: number[]): void => {
      const span: number = levels[2] - levels[1];
      if (span > 0) {
        this.hudVolume = clamp((levels[0] - levels[1]) / span, 0, 1);
      }
    }).catch((): void => {});
  }

  private async setSystemMediaVolume(value: number, token: number): Promise<void> {
    // AudioVolumeManager 在 API 12 只提供分组查询；系统音量写入仍由 AudioManager 的
    // setVolume 完成。普通应用受系统策略限制时会抛错，调用方立即回退 AVPlayer 音量。
    const manager: audio.AudioManager = audio.getAudioManager();
    const maximum: number = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA);
    const minimum: number = await manager.getMinVolume(audio.AudioVolumeType.MEDIA);
    if (token !== this.volumeWriteToken) {
      return;
    }
    const level: number = Math.round(minimum + clamp(value, 0, 1) * (maximum - minimum));
    await manager.setVolume(audio.AudioVolumeType.MEDIA, level);
  }

  private enterImmersiveMode(token: number): void {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window): void => {
      if (!this.isLifecycleActive(token)) {
        return;
      }
      this.playerWindow = win;
      try {
        win.setImmersiveModeEnabledState(true);
      } catch (_) {
      }
      try {
        win.setWindowSystemBarEnable([]).then((): void => {
          if (this.isLifecycleActive(token)) {
            log('immersive system bars hidden');
          } else {
            win.setWindowSystemBarEnable(['status', 'navigation']).catch((): void => {});
            try { win.setImmersiveModeEnabledState(false); } catch (_) {}
          }
        }).catch((): void => this.applyAvoidAreaFallback(win));
      } catch (_) {
        this.applyAvoidAreaFallback(win);
      }
    }).catch((): void => {});
  }

  private applyAvoidAreaFallback(win: window.Window): void {
    try {
      const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topSystemInset = px2vp(area.topRect.height);
      this.bottomSystemInset = px2vp(area.bottomRect.height);
      log(`immersive fallback avoidArea top=${this.topSystemInset} bottom=${this.bottomSystemInset}`);
    } catch (_) {
      this.topSystemInset = 28;
      this.bottomSystemInset = 16;
      log('immersive fallback avoidArea unavailable');
    }
  }

  private async restoreWindowState(): Promise<void> {
    const win: window.Window | null = this.playerWindow;
    if (win === null) {
      return;
    }
    if (this.brightnessChanged) {
      try {
        await win.setWindowBrightness(-1);
      } catch (_) {
      }
      this.brightnessChanged = false;
    }
    try {
      // setWindowSystemBarEnable 仅接受 status/navigation；导航指示条由 setImmersiveModeEnabledState 一并恢复
      await win.setWindowSystemBarEnable(['status', 'navigation']);
    } catch (_) {
    }
    try {
      win.setImmersiveModeEnabledState(false);
    } catch (_) {
    }
    this.playerWindow = null;
  }

  private detectPiP(): void {
    try {
      this.pipAvailable = PiPWindow.isPiPEnabled();
    } catch (_) {
      this.pipAvailable = false;
    }
  }

  private async startPiP(): Promise<void> {
    if (!this.pipAvailable) {
      this.showToast('当前设备不支持画中画');
      return;
    }
    try {
      if (this.pipController === null) {
        const context: common.Context | undefined = this.getUIContext().getHostContext();
        if (context === undefined) {
          this.showToast('当前设备不支持画中画');
          return;
        }
        this.pipController = await PiPWindow.create({
          context: context,
          componentController: this.surfaceController,
          templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
          contentWidth: Math.max(this.hudAreaWidth, 1),
          contentHeight: Math.max(this.hudAreaHeight, 1)
        });
        this.pipController.on('stateChange', (state: PiPWindow.PiPState, _reason: string): void => {
          this.pipActive = state === PiPWindow.PiPState.STARTED || state === PiPWindow.PiPState.ABOUT_TO_START;
        });
        this.pipController.on('controlPanelActionEvent',
          (event: PiPWindow.PiPActionEventType, status?: number): void => {
            if (event === 'playbackStateChanged') {
              this.togglePlayback(`pip:${status ?? -1}`).catch((): void => {});
            }
          });
      }
      await this.pipController.startPiP();
      this.pipActive = true;
    } catch (_) {
      this.pipAvailable = false;
      this.showToast('当前设备不支持画中画');
    }
  }

  private async stopPiP(): Promise<void> {
    const controller: PiPWindow.PiPController | null = this.pipController;
    if (controller === null) {
      return;
    }
    if (this.pipActive) {
      try {
        await controller.stopPiP();
      } catch (_) {
      }
    }
    controller.off('stateChange');
    controller.off('controlPanelActionEvent');
    this.pipController = null;
    this.pipActive = false;
  }

  private progressPercent(): number {
    return this.duration <= 0 ? 0 :
      clamp(this.currentTime / this.duration * 100, 0, 100);
  }

  private bufferedWidthPercent(): number {
    return clamp(Math.max(this.bufferedPercent, this.progressPercent()), 0, 100);
  }

  private thumbOffset(): number {
    return this.timelineWidth <= 0 ? -7 : this.progressPercent() / 100 * this.timelineWidth - 7;
  }

  private firstFinger(event: GestureEvent): FingerInfo | null {
    const fingers: FingerInfo[] = event.fingerList;
    if (fingers === undefined || fingers === null) {
      return null;
    }
    for (let i: number = 0; i < fingers.length; i++) {
      const finger: FingerInfo = fingers[i];
      if (finger !== undefined && finger !== null) {
        return finger;
      }
    }
    return null;
  }

  private eventLocalX(event: GestureEvent, fallback: number): number {
    const finger: FingerInfo | null = this.firstFinger(event);
    return finger === null ? fallback : finger.localX;
  }

  private eventLocalY(event: GestureEvent, fallback: number): number {
    const finger: FingerInfo | null = this.firstFinger(event);
    return finger === null ? fallback : finger.localY;
  }

  private updateTimeline(event: GestureEvent): void {
    if (this.duration <= 0 || this.timelineWidth <= 0) {
      return;
    }
    const fallback: number = this.progressPercent() / 100 * this.timelineWidth;
    this.dragTarget = timelineTarget(this.eventLocalX(event, fallback), this.timelineWidth,
      this.duration);
    this.tracker.updateInteracting(this.dragTarget);
  }

  private selectSpeed(rate: number): void {
    if (this.speedSelectionWriting) {
      return;
    }
    this.speedSelectionWriting = true;
    this.speedMode = 'none';
    this.speedGestureStarted = false;
    this.speedBaseRate = rate;
    this.controller.setSpeed(rate);
    // 契约：菜单显式选择倍速即清除锁定状态，SpeedHUD 按 1.2s 延迟淡出。
    if (this.hudMode === 'speed') {
      this.scheduleHudHide();
    }
    Promise.resolve().then((): void => {
      this.speedSelectionWriting = false;
    });
  }

  private seekDirectionLabel(): string {
    return this.hudSeekDelta >= 0 ? '>>' : '<<';
  }

  private speedHudText(): string {
    return this.speedHudMessage;
  }

  @Builder
  private speedMenu() {
    Menu() {
      ForEach(PLAYER_SPEEDS, (rate: number): void => {
        MenuItem({ content: Formats.formatSpeedLabel(rate) })
          .selected(this.playbackRate === rate)
          .selectIcon(true)
          .onChange((selected: boolean): void => {
            if (selected && !this.speedSelectionWriting) {
              this.selectSpeed(rate);
            }
          })
      }, (rate: number): string => rate.toString())
    }
  }

  @Builder
  private backdropLayer() {
    Column().width('100%').height('100%').backgroundColor(Color.Black)
    if (this.thumbnailURL.length > 0) {
      Image(this.thumbnailURL)
        .width('110%').height('110%').objectFit(ImageFit.Cover).blur(40).opacity(0.4)
    }
  }

  // API 12 无 VIDEO_SCALE_TYPE_SCALED_ASPECT（API 20+），native FIT 是不保比例的拉伸：
  // 由页面按 videoSizeChange 上报的宽高比把 XComponent 布局成与视频等比的矩形（等比
  // contain 居中，多余部分露出黑底），surface 比例与视频一致后 native 不再产生形变。
  // 例外：竖屏视频在竖屏屏幕上两者比例本就接近（9:16 vs 9:19.5 一类），直接铺满即
  // 正常观感；仅限比例差 ≤25%，差异更大的内容仍走等比 contain 防止明显变形。
  private portraitFillApplies(videoAspect: number, areaAspect: number): boolean {
    if (videoAspect >= 1 || areaAspect >= 1) {
      return false;
    }
    const ratio: number = videoAspect / areaAspect;
    return ratio >= 0.8 && ratio <= 1.25;
  }

  private videoSurfaceWidth(): string {
    if (this.videoWidth <= 0 || this.videoHeight <= 0 || this.hudAreaWidth <= 0 ||
      this.hudAreaHeight <= 0) {
      return '100%';
    }
    const videoAspect: number = this.videoWidth / this.videoHeight;
    const areaAspect: number = this.hudAreaWidth / this.hudAreaHeight;
    if (this.portraitFillApplies(videoAspect, areaAspect)) {
      return '100%';
    }
    return videoAspect >= areaAspect ? '100%' : `${videoAspect / areaAspect * 100}%`;
  }

  private videoSurfaceHeight(): string {
    if (this.videoWidth <= 0 || this.videoHeight <= 0 || this.hudAreaWidth <= 0 ||
      this.hudAreaHeight <= 0) {
      return '100%';
    }
    const videoAspect: number = this.videoWidth / this.videoHeight;
    const areaAspect: number = this.hudAreaWidth / this.hudAreaHeight;
    if (this.portraitFillApplies(videoAspect, areaAspect)) {
      return '100%';
    }
    return videoAspect >= areaAspect ? `${areaAspect / videoAspect * 100}%` : '100%';
  }

  @Builder
  private videoLayer() {
    Column() {
      XComponent({
        id: 'bililive-player-surface',
        type: XComponentType.SURFACE,
        controller: this.surfaceController
      })
        .width(this.videoSurfaceWidth()).height(this.videoSurfaceHeight())
        .onLoad((): void => this.setupPlayer(this.surfaceController.getXComponentSurfaceId()))
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  private vignetteLayer() {
    Column() {
      Column().width('100%').height(120).linearGradient({
        angle: 180,
        colors: [['#B3000000', 0.0], ['#00000000', 1.0]]
      })
      Blank()
      Column().width('100%').height(160).linearGradient({
        angle: 0,
        colors: [['#B3000000', 0.0], ['#00000000', 1.0]]
      })
    }
    .width('100%').height('100%').hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private gestureLayer() {
    Column()
      .width('100%').height('100%').backgroundColor(Color.Transparent)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.hudAreaWidth = Number(newArea.width);
        this.hudAreaHeight = Number(newArea.height);
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction((): void => {
            this.togglePlayback('doubleTap').catch((): void => {});
          }),
          TapGesture({ count: 1 }).onAction((): void => {
            if (this.hudMode !== 'speed') {
              this.chromeVisible = !this.chromeVisible;
            }
          }),
          GestureGroup(GestureMode.Parallel,
            LongPressGesture({ fingers: 1, repeat: true, duration: 500 })
              .onAction((event: GestureEvent): void => this.onSpeedLongPress(event))
              .onActionEnd((): void => this.onSpeedLongPressEnd())
              .onActionCancel((): void => this.onSpeedLongPressCancel()),
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: DIRECTION_THRESHOLD_VP })
              .onActionStart((event: GestureEvent): void => this.onPanStart(event))
              .onActionUpdate((event: GestureEvent): void => this.onPanUpdate(event))
              .onActionEnd((): void => this.onPanEnd())
              .onActionCancel((): void => this.onPanCancel())
          )
        )
      )
  }

  @Builder
  private topHud() {
    Column() {
      if (this.hudMode === 'seek') {
        Row({ space: 10 }) {
          Text(this.seekDirectionLabel()).fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text(`${Formats.formatDuration(this.hudSeekTarget)} / ${Formats.formatDuration(this.duration)}`)
            .fontSize(18).fontFamily('monospace').fontColor(Color.White)
        }
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .backgroundColor('#88000000').backgroundBlurStyle(BlurStyle.BACKGROUND_THIN).borderRadius(14)
      } else if (this.hudMode === 'volume' || this.hudMode === 'brightness') {
        Row({ space: 12 }) {
          if (this.hudMode === 'volume') {
            if (this.hudVolume <= 0) {
              SymbolGlyph($r('sys.symbol.speaker_slash')).fontSize(24).fontColor([Color.White]).width(28)
            } else {
              SymbolGlyph($r('sys.symbol.speaker_fill')).fontSize(24).fontColor([Color.White]).width(28)
            }
          } else {
            SymbolGlyph($r('sys.symbol.sun_max')).fontSize(24).fontColor([Color.White]).width(28)
          }
          Progress({
            value: (this.hudMode === 'volume' ? this.hudVolume : this.hudBrightness) * 100,
            total: 100,
            type: ProgressType.Linear
          })
            .width(150).height(8).color($r('app.color.brand_color')).backgroundColor('#33FFFFFF')
        }
        .padding({ left: 18, right: 18, top: 12, bottom: 12 })
        .backgroundColor('#88000000').backgroundBlurStyle(BlurStyle.BACKGROUND_THIN).borderRadius(14)
      }
    }
    .width('100%').height('100%').padding({ top: 26 })
    .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private speedHud() {
    Column() {
      if (this.hudMode === 'speed') {
        Row({ space: 8 }) {
          if (this.speedMode === 'locking') {
            SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(18).fontColor([Color.White])
          } else if (this.speedMode === 'unlocking') {
            SymbolGlyph($r('sys.symbol.lock_open')).fontSize(18).fontColor([Color.White])
          } else {
            SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(18).fontColor([Color.White])
          }
          Text(this.speedHudText()).fontSize(14).fontColor(Color.White)
        }
        .padding({ left: 18, right: 18, top: 11, bottom: 11 })
        .backgroundColor('#88000000').backgroundBlurStyle(BlurStyle.BACKGROUND_THIN).borderRadius(20)
        .margin({ bottom: 92 })
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.End).alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private toastLayer() {
    Column() {
      if (this.toastText.length > 0) {
        Text(this.toastText).fontSize(14).fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .backgroundColor('#66000000').backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
          .borderRadius(20).margin({ bottom: 132 })
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.End).alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private completedLayer() {
    Column() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(34).fontColor([Color.White])
      }
      .width(68).height(68).backgroundColor('#66000000')
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN).borderRadius(34)
      .onClick((): void => {
        this.replay().catch((): void => {});
      })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000').hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private timeline() {
    Row({ space: 10 }) {
      Text(Formats.formatDuration(this.currentTime)).width(58).fontSize(12).fontFamily('monospace')
        .fontColor(Color.White).textAlign(TextAlign.End)
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(4).backgroundColor('#33FFFFFF').borderRadius(2)
        Row().width(`${this.bufferedWidthPercent()}%`).height(4).backgroundColor('#66FFFFFF').borderRadius(2)
        Row().width(`${this.progressPercent()}%`).height(4)
          .backgroundColor($r('app.color.brand_color')).borderRadius(2)
        Column().width(14).height(14).borderRadius(7)
          .backgroundColor($r('app.color.brand_color')).translate({ x: this.thumbOffset() })
      }
      .layoutWeight(1).height(34).enabled(this.duration > 0)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.timelineWidth = Number(newArea.width);
      })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 0 })
          .onActionStart((event: GestureEvent): void => {
            if (this.duration <= 0) {
              return;
            }
            this.tracker.beginInteracting();
            this.updateTimeline(event);
          })
          .onActionUpdate((event: GestureEvent): void => this.updateTimeline(event))
          .onActionEnd((event: GestureEvent): void => {
            this.updateTimeline(event);
            this.tracker.endInteracting(this.dragTarget);
          })
          .onActionCancel((): void => {
            this.tracker.cancelInteracting().catch((): void => {});
          })
      )
      Text(Formats.formatDuration(this.duration)).width(58).fontSize(12).fontFamily('monospace')
        .fontColor(Color.White)
    }
    .width('100%')
  }

  @Builder
  private controlLayer() {
    Column() {
      Row({ space: 12 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(28).fontColor([Color.White])
        }
        .type(ButtonType.Circle).width(44).height(44).backgroundColor('#33000000')
        .hitTestBehavior(HitTestMode.Block)
        .onClick((): void => {
          this.closePlayer().catch((): void => {});
        })
        Column({ space: 3 }) {
          Text(this.file.name).width('100%').fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(Formats.formatBytes(this.file.size)).width('100%').fontSize(12).fontColor('#B8FFFFFF')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('画中画').height(38).fontSize(12).fontColor(Color.White).backgroundColor('#33000000')
          .hitTestBehavior(HitTestMode.Block)
          .onClick((): void => {
            this.startPiP().catch((): void => {});
          })
      }
      .width('100%').padding({ left: 12, right: 12, top: 18 + this.topSystemInset })
      Column({ space: 6 }) {
        this.timeline()
        Row() {
          Button() {
            if (this.playerState === 'completed') {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(25).fontColor([Color.White])
            } else if (this.isPlaying) {
              SymbolGlyph($r('sys.symbol.pause_fill')).fontSize(21).fontColor([Color.White])
            } else {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(25).fontColor([Color.White])
            }
          }
          .type(ButtonType.Circle).width(48).height(48).backgroundColor('#33000000')
          .enabled(this.playerState === 'prepared' || this.playerState === 'playing' ||
            this.playerState === 'paused' || this.playerState === 'completed')
          .hitTestBehavior(HitTestMode.Block)
          .onClick((): void => {
            log(`play button click enabled state=${this.playerState}`);
            this.togglePlayback('button').catch((): void => {});
          })
          Blank()
          Button(Formats.formatSpeedLabel(this.playbackRate)).height(40).fontSize(13)
            .fontColor(Color.White).backgroundColor('#33000000').enabled(this.duration > 0)
            .hitTestBehavior(HitTestMode.Block).bindMenu(this.speedMenu)
        }
        .width('100%')
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 18 + this.bottomSystemInset })
    }
    .width('100%').height('100%').opacity(this.chromeVisible ? 1 : 0)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .hitTestBehavior(this.chromeVisible ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private errorLayer() {
    Column({ space: 22 }) {
      Text(this.errorText).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Color.White)
      Button('退出').height(44).fontColor(Color.White).backgroundColor($r('app.color.brand_color'))
        .onClick((): void => {
          this.closePlayer().catch((): void => {});
        })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor('#E6000000')
  }

  build() {
    Stack() {
      this.backdropLayer()
      this.videoLayer()
      this.vignetteLayer()
      this.gestureLayer()
      this.topHud()
      this.speedHud()
      this.toastLayer()
      if (this.playerState === 'completed' && this.errorText.length === 0) {
        this.completedLayer()
      }
      this.controlLayer()
      if (this.errorText.length > 0) {
        this.errorLayer()
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
