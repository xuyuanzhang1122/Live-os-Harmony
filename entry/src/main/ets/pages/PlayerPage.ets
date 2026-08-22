import { Formats } from '../common/Formats';
import { AppConfig } from '../config/AppConfig';
import { VideoFileInfo } from '../model/VideoLibrary';
import { APIClient } from '../net/APIClient';
import { PlayerController, PlayerState } from '../player/PlayerController';
import { ProgressTracker } from '../player/ProgressTracker';
import { PLAYER_SPEEDS, playbackErrorText, timelineTarget } from '../player/PlayerRules';

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
  private readonly config: AppConfig = AppConfig.getInstance();
  private readonly controller: PlayerController = new PlayerController();
  private readonly tracker: ProgressTracker = new ProgressTracker(this.controller);
  private readonly surfaceController: XComponentController = new XComponentController();
  private playbackURL: string = '';
  private dragTarget: number = 0;
  private setupStarted: boolean = false;
  private closing: boolean = false;
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.bindPlayerCallbacks();
    this.resolveURLs();
    this.tracker.start();
  }

  aboutToDisappear(): void {
    this.clearToastTimer();
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

  // TASK-4 在此接入续播进度上报。
  private onBeforeClose(): void {
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
    if (event.fingerList.length === 0) {
      return this.progressPercent() / 100 * this.timelineWidth;
    }
    return event.fingerList[0].localX;
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
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction((): void => this.togglePlayback()),
          TapGesture({ count: 1 }).onAction((): void => {
            this.chromeVisible = !this.chromeVisible;
          })
        )
      )
  }

  @Builder
  private hudLayer() {
    // TASK-4 填充 seek、音量和亮度 HUD。
    Column()
      .width('100%')
      .height('100%')
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
