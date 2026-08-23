import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Formats } from '../common/Formats';
import { AppConfig } from '../config/AppConfig';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { VideoFileInfo } from '../model/VideoLibrary';
import { APIClient } from '../net/APIClient';
import { PlayerController, PlayerState } from '../player/PlayerController';
import { ProgressTracker } from '../player/ProgressTracker';
import { clamp, horizontalSeekTarget } from '../player/PlayerMath';
import { PLAYER_SPEEDS, playbackErrorText, timelineTarget } from '../player/PlayerRules';

// HUD 展示模式：seek 快进快退 / volume 音量 / brightness 亮度。
type HudMode = 'seek' | 'volume' | 'brightness';

// HUD 手势方向状态：0 未判定、1 水平拖动（seek）、2 垂直拖动（亮度或音量）。
const HUD_DIRECTION_NONE: number = 0;
const HUD_DIRECTION_SEEK: number = 1;
const HUD_DIRECTION_VERTICAL: number = 2;

// HUD 无操作自动隐藏延时（毫秒）。
const HUD_HIDE_DELAY_MS: number = 2000;

// 垂直拖动灵敏度：拖满播放区高度的 60% 即完成 0~100% 调节。
const HUD_VERTICAL_FULL_FRACTION: number = 0.6;

// 历史进度上报体：服务端字段（id、api_key_user_id、updated_at）由服务端生成，
// 本地只用 class 构造需要上报的业务字段（ArkTS 不允许对象字面量直接赋给接口类型）。
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
  @Local private chromeVisible: boolean = true;
  @Local private playerState: PlayerState = 'idle';
  @Local private currentTime: number = 0;
  @Local private duration: number = 0;
  @Local private bufferedPercent: number = 0;
  @Local private playbackRate: number = 1.0;
  @Local private errorText: string = '';
  @Local private toastText: string = '';
  @Local private thumbnailURL: string = '';
  @Local private timelineWidth: number = 0;
  @Local private hudVisible: boolean = false;
  @Local private hudMode: HudMode = 'seek';
  @Local private hudSeekTarget: number = 0;
  @Local private hudSeekDelta: number = 0;
  @Local private hudVolume: number = 1;
  @Local private hudBrightness: number = 1;
  private readonly config: AppConfig = AppConfig.getInstance();
  private readonly controller: PlayerController = new PlayerController();
  private readonly tracker: ProgressTracker = new ProgressTracker(this.controller);
  private readonly surfaceController: XComponentController = new XComponentController();
  private playbackURL: string = '';
  private dragTarget: number = 0;
  private setupStarted: boolean = false;
  private closing: boolean = false;
  private toastTimer: number = -1;
  private hudTimer: number = -1;
  private hudDirection: number = HUD_DIRECTION_NONE;
  private hudStartX: number = 0;
  private hudSeekBase: number = 0;
  private hudVolumeBase: number = 1;
  private hudBrightnessBase: number = 1;
  private hudAreaWidth: number = 0;
  private hudAreaHeight: number = 0;
  private brightnessWindow: window.Window | null = null;
  private brightnessWindowQueried: boolean = false;
  private historyResumeTried: boolean = false;
  private historyReported: boolean = false;

  aboutToAppear(): void {
    this.bindPlayerCallbacks();
    this.resolveURLs();
    this.tracker.start();
  }

  aboutToDisappear(): void {
    this.clearToastTimer();
    this.clearHudTimer();
    this.restoreWindowBrightness();
    // 兜底上报：覆盖不经 closePlayer 的退出路径（如系统直接销毁页面）。
    this.onBeforeClose();
    this.tracker.stop();
    this.controller.pause()
      .then((): Promise<void> => this.controller.release())
      .catch((): void => {});
  }

  private bindPlayerCallbacks(): void {
    this.controller.onStateChange = (state: PlayerState): void => {
      this.playerState = state;
      if (state === 'completed') {
        this.currentTime = this.duration;
        this.chromeVisible = true;
      }
    };
    this.controller.onError = (_code: number, _message: string): void => {
      this.errorText = playbackErrorText(this.file.playback_status);
      this.chromeVisible = false;
    };
    this.controller.onDurationReady = (seconds: number): void => {
      this.duration = seconds;
      // 时长就绪后尝试从服务端历史进度续播。
      this.tryResumeFromHistory();
    };
    this.controller.onSeekDone = (seconds: number): void => {
      this.tracker.handleSeekDone(seconds).catch((): void => {});
    };
    this.controller.onSpeedChange = (rate: number): void => {
      this.playbackRate = rate;
      this.showToast(`播放速度 ${Formats.formatSpeedLabel(rate)}`);
    };
    this.controller.onBufferingUpdate = (percent: number): void => {
      this.bufferedPercent = percent;
    };
    this.tracker.onTimeUpdate = (seconds: number): void => {
      this.currentTime = seconds;
    };
  }

  private resolveURLs(): void {
    const client = this.config.getClient();
    const hasDirectURL: boolean = (this.file.hls_url?.length ?? 0) > 0 ||
      (this.file.file_url?.length ?? 0) > 0;
    if (this.file.rel_path.trim().length === 0 && !hasDirectURL) {
      this.errorText = playbackErrorText(this.file.playback_status);
      this.chromeVisible = false;
      return;
    }
    this.playbackURL = APIClient.buildPlaybackUrl(client.baseURL, client.apiKey, this.file);
    if (!/^https?:\/\//i.test(this.playbackURL)) {
      this.errorText = playbackErrorText(this.file.playback_status);
      this.chromeVisible = false;
      return;
    }
    const thumbnail: string = APIClient.buildThumbnailUrl(client.baseURL, client.apiKey, this.file);
    this.thumbnailURL = /^https?:\/\//i.test(thumbnail) ? thumbnail : '';
  }

  private setupPlayer(surfaceId: string): void {
    if (this.setupStarted || this.errorText.length > 0 || this.playbackURL.length === 0) {
      return;
    }
    this.setupStarted = true;
    this.controller.setup(this.playbackURL, surfaceId).catch((): void => {});
  }

  private togglePlayback(): void {
    if (this.playerState === 'completed') {
      this.replay();
    } else if (this.controller.isPlaying) {
      this.controller.pause().catch((): void => {});
    } else {
      this.controller.play().catch((): void => {});
    }
  }

  private replay(): void {
    this.controller.seek(0);
    this.currentTime = 0;
    this.controller.play().catch((): void => {});
  }

  private async closePlayer(): Promise<void> {
    if (this.closing) {
      return;
    }
    this.closing = true;
    this.clearToastTimer();
    await this.controller.pause();
    this.onBeforeClose();
    this.tracker.stop();
    await this.controller.release();
    this.onClose();
  }

  // TASK-4 续播进度上报：fire-and-forget 异步上报，失败静默忽略，不阻塞关闭流程。
  private onBeforeClose(): void {
    if (this.historyReported) {
      return;
    }
    // 播放失败或从未就绪（duration 为 0）时不上报，避免把服务端已有进度覆盖为 0。
    const relPath: string = this.file.rel_path.trim();
    if (this.duration <= 0 || relPath.length === 0) {
      return;
    }
    this.historyReported = true;
    try {
      const entry: WatchHistoryEntry = new WatchHistoryReport(relPath, this.file.name,
        Math.max(this.currentTime, 0), this.duration);
      this.config.getClient().postHistory(entry).catch((): void => {});
    } catch (_) {
      // 上报失败静默忽略，不影响关闭。
    }
  }

  // TASK-4 续播恢复：时长就绪后拉取服务端历史进度，明显未看完则跳转继续播放。
  private tryResumeFromHistory(): void {
    // durationUpdate 可能多次回调，只尝试一次。
    if (this.historyResumeTried) {
      return;
    }
    const relPath: string = this.file.rel_path.trim();
    if (relPath.length === 0 || this.duration <= 0) {
      return;
    }
    this.historyResumeTried = true;
    this.config.getClient().getHistoryEntry(relPath)
      .then((entry: WatchHistoryEntry | null): void => {
        if (this.closing || entry === null) {
          return;
        }
        const position: number = entry.position_seconds;
        // 仅恢复明显未看完的进度：接近片尾（95%）视为已看完，从头播放。
        if (position > 0 && position < this.duration * 0.95) {
          this.controller.seek(position);
          this.currentTime = position;
          this.showToast(`已恢复到上次进度 ${Formats.formatClock(position)}`);
        }
      })
      .catch((): void => {});
  }

  showToast(message: string): void {
    this.clearToastTimer();
    this.toastText = message;
    this.toastTimer = setTimeout((): void => {
      this.toastText = '';
      this.toastTimer = -1;
    }, 2200);
  }

  private clearToastTimer(): void {
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
  }

  // HUD 显示 2 秒内无操作自动隐藏（写法参考 showToast 的 timer）。
  private scheduleHudHide(): void {
    this.clearHudTimer();
    this.hudTimer = setTimeout((): void => {
      this.hudVisible = false;
      this.hudTimer = -1;
    }, HUD_HIDE_DELAY_MS);
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
  }

  private onHudPanStart(event: GestureEvent): void {
    // 记录起始横坐标：垂直拖动按左半屏/右半屏区分亮度与音量。
    this.hudStartX = this.eventLocalX(event);
    this.hudDirection = HUD_DIRECTION_NONE;
  }

  private onHudPanUpdate(event: GestureEvent): void {
    const offsetX: number = event.offsetX ?? 0;
    const offsetY: number = event.offsetY ?? 0;
    if (this.hudDirection === HUD_DIRECTION_NONE && !this.lockHudDirection(offsetX, offsetY)) {
      return;
    }
    if (this.hudDirection === HUD_DIRECTION_SEEK) {
      // 水平拖动 = 快进快退，复用进度条拖动的交互模式（暂停采样，松手恢复）。
      const target: number = horizontalSeekTarget(this.hudSeekBase, offsetX, this.hudAreaWidth, this.duration);
      this.hudSeekTarget = target;
      this.hudSeekDelta = target - this.hudSeekBase;
      this.tracker.updateInteracting(target);
      this.scheduleHudHide();
    } else if (this.hudDirection === HUD_DIRECTION_VERTICAL) {
      // 垂直拖动：offsetY 向上为负，转换为 0~1 的调节量。
      const span: number = Math.max(this.hudAreaHeight * HUD_VERTICAL_FULL_FRACTION, 1);
      const delta: number = -offsetY / span;
      if (this.hudMode === 'brightness') {
        this.hudBrightness = clamp(this.hudBrightnessBase + delta, 0, 1);
        this.applyWindowBrightness(this.hudBrightness);
      } else {
        this.hudVolume = clamp(this.hudVolumeBase + delta, 0, 1);
        this.controller.setVolume(this.hudVolume);
      }
      this.scheduleHudHide();
    }
  }

  // 首次明显位移后锁定手势方向：水平为 seek，垂直为亮度（左）/音量（右）。
  private lockHudDirection(offsetX: number, offsetY: number): boolean {
    if (Math.abs(offsetX) < 12 && Math.abs(offsetY) < 12) {
      return false;
    }
    if (Math.abs(offsetX) > Math.abs(offsetY)) {
      // 时长未知时无法 seek，忽略水平拖动。
      if (this.duration <= 0) {
        return false;
      }
      this.hudDirection = HUD_DIRECTION_SEEK;
      this.hudMode = 'seek';
      this.hudSeekBase = this.currentTime;
      this.hudSeekTarget = this.currentTime;
      this.hudSeekDelta = 0;
      this.tracker.beginInteracting();
    } else {
      this.hudDirection = HUD_DIRECTION_VERTICAL;
      this.hudMode = this.hudStartX < this.hudAreaWidth / 2 ? 'brightness' : 'volume';
      this.hudVolumeBase = this.hudVolume;
      this.hudBrightnessBase = this.hudBrightness;
    }
    this.hudVisible = true;
    this.scheduleHudHide();
    return true;
  }

  private onHudPanEnd(): void {
    if (this.hudDirection === HUD_DIRECTION_SEEK) {
      // 松手后执行 seek，并交给 ProgressTracker 在 seek 完成后按需恢复播放。
      this.tracker.endInteracting(this.hudSeekTarget);
    }
    this.hudDirection = HUD_DIRECTION_NONE;
    this.scheduleHudHide();
  }

  private onHudPanCancel(): void {
    if (this.hudDirection === HUD_DIRECTION_SEEK) {
      this.tracker.cancelInteracting().catch((): void => {});
    }
    this.hudDirection = HUD_DIRECTION_NONE;
    this.scheduleHudHide();
  }

  // 亮度说明：HarmonyOS 未提供应用内读取窗口亮度的接口，HUD 以 100% 作为初始显示值。
  // 这里调用 window.setWindowBrightness(0~1) 只调节当前窗口亮度，不修改系统全局亮度；
  // 窗口获取失败时自动降级为仅 HUD 显示百分比，不真正改变亮度。
  private applyWindowBrightness(value: number): void {
    if (!this.brightnessWindowQueried) {
      this.brightnessWindowQueried = true;
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      window.getLastWindow(context)
        .then((win: window.Window): void => {
          this.brightnessWindow = win;
          win.setWindowBrightness(value).catch((): void => {});
        })
        .catch((): void => {});
      return;
    }
    const win: window.Window | null = this.brightnessWindow;
    if (win !== null) {
      win.setWindowBrightness(value).catch((): void => {});
    }
  }

  // 退出播放器时恢复窗口亮度跟随系统（-1 表示恢复默认），仅在实际调节过亮度时执行。
  private restoreWindowBrightness(): void {
    const win: window.Window | null = this.brightnessWindow;
    if (win !== null) {
      win.setWindowBrightness(-1).catch((): void => {});
    }
  }

  private hudSeekDeltaLabel(): string {
    const deltaSeconds: number = Math.round(this.hudSeekDelta);
    return deltaSeconds >= 0 ? `快进 ${deltaSeconds} 秒` : `快退 ${-deltaSeconds} 秒`;
  }

  private hudVolumePercent(): number {
    return Math.round(this.hudVolume * 100);
  }

  private hudBrightnessPercent(): number {
    return Math.round(this.hudBrightness * 100);
  }

  private progressPercent(): number {
    if (this.duration <= 0) {
      return 0;
    }
    return Math.min(Math.max(this.currentTime / this.duration * 100, 0), 100);
  }

  private bufferedWidthPercent(): number {
    return Math.min(Math.max(this.bufferedPercent, this.progressPercent()), 100);
  }

  private thumbOffset(): number {
    if (this.timelineWidth <= 0) {
      return -7;
    }
    return this.progressPercent() / 100 * this.timelineWidth - 7;
  }

  private eventLocalX(event: GestureEvent): number {
    const fallback: number = this.progressPercent() / 100 * this.timelineWidth;
    const fingers: FingerInfo[] = event.fingerList;
    if (fingers === undefined || fingers === null) {
      return fallback;
    }
    // 多指触摸时 fingerList 可能是稀疏数组（按下手指 id 1、2 时下标 0 为空洞），
    // 直接取 [0] 会得到 undefined 并导致 JS 崩溃，必须逐个取第一个有效手指。
    for (let i: number = 0; i < fingers.length; i++) {
      const finger: FingerInfo = fingers[i];
      if (finger !== undefined && finger !== null) {
        return finger.localX;
      }
    }
    return fallback;
  }

  private updateTimeline(event: GestureEvent): void {
    this.dragTarget = timelineTarget(this.eventLocalX(event), this.timelineWidth, this.duration);
    this.tracker.updateInteracting(this.dragTarget);
  }

  private selectSpeed(rate: number): void {
    this.controller.setSpeed(rate);
  }

  @Builder
  private speedMenu() {
    Menu() {
      ForEach(PLAYER_SPEEDS, (rate: number): void => {
        MenuItem({ content: Formats.formatSpeedLabel(rate) })
          .selected(this.playbackRate === rate)
          .selectIcon(true)
          .onChange((selected: boolean): void => {
            if (selected) {
              this.selectSpeed(rate);
            }
          })
      }, (rate: number): string => rate.toString())
    }
  }

  @Builder
  private backdropLayer() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)

    if (this.thumbnailURL.length > 0) {
      Image(this.thumbnailURL)
        .width('110%')
        .height('110%')
        .objectFit(ImageFit.Cover)
        .blur(40)
        .opacity(0.4)
    }
  }

  @Builder
  private videoLayer() {
    XComponent({
      id: 'bililive-player-surface',
      type: XComponentType.SURFACE,
      controller: this.surfaceController
    })
      .width('100%')
      .height('100%')
      .onLoad((): void => {
        this.setupPlayer(this.surfaceController.getXComponentSurfaceId());
      })
  }

  @Builder
  private vignetteLayer() {
    Column() {
      Column()
        .width('100%')
        .height(120)
        .linearGradient({
          angle: 180,
          colors: [['#B3000000', 0.0], ['#00000000', 1.0]]
        })
      Blank()
      Column()
        .width('100%')
        .height(160)
        .linearGradient({
          angle: 0,
          colors: [['#B3000000', 0.0], ['#00000000', 1.0]]
        })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private gestureLayer() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        // 记录播放区尺寸，供手势方向判定（左右半屏）与拖动灵敏度计算使用。
        this.hudAreaWidth = Number(newArea.width);
        this.hudAreaHeight = Number(newArea.height);
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction((): void => this.togglePlayback()),
          TapGesture({ count: 1 }).onAction((): void => {
            this.chromeVisible = !this.chromeVisible;
          }),
          // TASK-4 播放区手势：水平拖动 = 快进快退，左侧竖直拖动 = 亮度，右侧竖直拖动 = 音量。
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 12 })
            .onActionStart((event: GestureEvent): void => this.onHudPanStart(event))
            .onActionUpdate((event: GestureEvent): void => this.onHudPanUpdate(event))
            .onActionEnd((_event: GestureEvent): void => this.onHudPanEnd())
            .onActionCancel((): void => this.onHudPanCancel())
        )
      )
  }

  @Builder
  private hudLayer() {
    // TASK-4 手势 HUD：seek 显示目标时间与快进快退秒数，音量/亮度显示百分比进度条。
    Column() {
      if (this.hudVisible) {
        Column({ space: 8 }) {
          if (this.hudMode === 'seek') {
            Text(this.hudSeekDeltaLabel())
              .fontSize(13)
              .fontColor('#CCFFFFFF')
            Text(`${Formats.formatClock(this.hudSeekTarget)} / ${Formats.formatClock(this.duration)}`)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontFamily('monospace')
              .fontColor(Color.White)
          } else if (this.hudMode === 'volume') {
            Text(`音量 ${this.hudVolumePercent()}%`)
              .fontSize(14)
              .fontColor(Color.White)
            Progress({ value: this.hudVolume * 100, total: 100, type: ProgressType.Linear })
              .width(140)
              .color(Color.White)
              .backgroundColor('#33FFFFFF')
          } else {
            Text(`亮度 ${this.hudBrightnessPercent()}%`)
              .fontSize(14)
              .fontColor(Color.White)
            Progress({ value: this.hudBrightness * 100, total: 100, type: ProgressType.Linear })
              .width(140)
              .color(Color.White)
              .backgroundColor('#33FFFFFF')
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 26, right: 26, top: 16, bottom: 16 })
        .backgroundColor('#99000000')
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .borderRadius(14)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private toastLayer() {
    Column() {
      if (this.toastText.length > 0) {
        Text(this.toastText)
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .backgroundColor('#66000000')
          .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
          .borderRadius(20)
          .margin({ bottom: 132 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private completedLayer() {
    Column() {
      Button('↻')
        .width(68)
        .height(68)
        .fontSize(36)
        .fontColor(Color.White)
        .backgroundColor('#66000000')
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
        .borderRadius(34)
        .onClick((): void => this.replay())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private timeline() {
    Row({ space: 10 }) {
      Text(Formats.formatClock(this.currentTime))
        .width(58)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(Color.White)
        .textAlign(TextAlign.End)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(4)
          .backgroundColor('#33FFFFFF')
          .borderRadius(2)
        Row()
          .width(`${this.bufferedWidthPercent()}%`)
          .height(4)
          .backgroundColor('#66FFFFFF')
          .borderRadius(2)
        Row()
          .width(`${this.progressPercent()}%`)
          .height(4)
          .backgroundColor($r('app.color.brand_color'))
          .borderRadius(2)
        Column()
          .width(14)
          .height(14)
          .borderRadius(7)
          .backgroundColor($r('app.color.brand_color'))
          .translate({ x: this.thumbOffset() })
      }
      .layoutWeight(1)
      .height(34)
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

      Text(Formats.formatClock(this.duration))
        .width(58)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(Color.White)
    }
    .width('100%')
  }

  @Builder
  private controlLayer() {
    Column() {
      Row({ space: 12 }) {
        Button('‹')
          .type(ButtonType.Circle)
          .width(44)
          .height(44)
          .fontSize(34)
          .fontColor(Color.White)
          .backgroundColor('#33000000')
          .onClick((): void => {
            this.closePlayer().catch((): void => {});
          })

        Column({ space: 3 }) {
          Text(this.file.name)
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(Formats.formatBytes(this.file.size))
            .width('100%')
            .fontSize(12)
            .fontColor('#B8FFFFFF')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('画中画')
          .height(38)
          .fontSize(12)
          .fontColor('#80FFFFFF')
          .backgroundColor('#22000000')
          .enabled(false)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10 })

      Blank()

      Column({ space: 6 }) {
        this.timeline()

        Row() {
          Button(this.playerState === 'completed' ? '↻' : (this.controller.isPlaying ? '❚❚' : '▶'))
            .type(ButtonType.Circle)
            .width(48)
            .height(48)
            .fontSize(this.controller.isPlaying ? 19 : 24)
            .fontColor(Color.White)
            .backgroundColor('#33000000')
            .enabled(this.playerState === 'prepared' || this.playerState === 'playing' ||
              this.playerState === 'paused' || this.playerState === 'completed')
            .onClick((): void => this.togglePlayback())

          Blank()

          Button(Formats.formatSpeedLabel(this.playbackRate))
            .height(40)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#33000000')
            .enabled(this.duration > 0)
            .bindMenu(this.speedMenu)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('100%')
    .height('100%')
    .opacity(this.chromeVisible ? 1 : 0)
    .hitTestBehavior(this.chromeVisible ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private errorLayer() {
    Column({ space: 22 }) {
      Text(this.errorText)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
      Button('退出')
        .height(44)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand_color'))
        .onClick((): void => {
          this.closePlayer().catch((): void => {});
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#E6000000')
  }

  build() {
    Stack() {
      this.backdropLayer()
      this.videoLayer()
      this.vignetteLayer()
      this.gestureLayer()
      this.hudLayer()
      this.toastLayer()
      if (this.playerState === 'completed' && this.errorText.length === 0) {
        this.completedLayer()
      }
      this.controlLayer()
      if (this.errorText.length > 0) {
        this.errorLayer()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
