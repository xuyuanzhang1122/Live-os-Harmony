import { describe, expect, it } from '@ohos/hypium';
import {
  PLAYER_SPEEDS,
  playbackErrorText,
  timelineTarget
} from '../main/ets/player/PlayerRules';
import {
  PLAYER_PROGRESS_INTERVAL_MS,
  ProgressSource,
  ProgressTracker
} from '../main/ets/player/ProgressTracker';
import {
  BufferingUpdateHandler,
  PlayerAdapter,
  PlayerController,
  PlayerErrorHandler,
  PlayerNumberHandler,
  PlayerOperationError,
  PlayerState,
  PlayerStateHandler,
  PlayerVideoSizeHandler,
  withTimeout
} from '../main/ets/player/PlayerController';

class FakeProgressSource implements ProgressSource {
  currentTime: number = 12;
  isPlaying: boolean = true;
  pauseCount: number = 0;
  playCount: number = 0;
  seekTarget: number = -1;
  pauseCompleted: boolean = false;
  playedBeforePauseCompleted: boolean = false;

  async pause(): Promise<void> {
    this.pauseCount += 1;
    await Promise.resolve();
    this.pauseCompleted = true;
    this.isPlaying = false;
  }

  async play(): Promise<void> {
    if (this.pauseCount > 0 && !this.pauseCompleted) {
      this.playedBeforePauseCompleted = true;
    }
    this.playCount += 1;
    this.isPlaying = true;
  }

  seek(seconds: number): void {
    this.seekTarget = seconds;
  }
}

class FakePlayerAdapter implements PlayerAdapter {
  // 忠实模拟真机 AVPlayer：url 赋值后异步进入 initialized（可用 delayInitializedMs 模拟延迟）。
  private urlValue: string = '';
  delayInitializedMs: number = 0;
  surfaceId: string = '';
  duration: number = 120000;
  currentTime: number = 5000;
  state: PlayerState = 'idle';
  calls: string[] = [];
  boundCount: number = 0;
  unboundCount: number = 0;
  speedDoneHandler: PlayerNumberHandler = (_rate: number): void => {};
  timeUpdateHandler: PlayerNumberHandler = (_milliseconds: number): void => {};
  durationUpdateHandler: PlayerNumberHandler = (_milliseconds: number): void => {};
  videoSizeChangeHandler: PlayerVideoSizeHandler = (_width: number, _height: number): void => {};
  private stateHandler: PlayerStateHandler = (_state: PlayerState): void => {};

  get url(): string {
    return this.urlValue;
  }

  set url(value: string) {
    this.urlValue = value;
    const handler: PlayerStateHandler = this.stateHandler;
    if (this.delayInitializedMs > 0) {
      setTimeout((): void => {
        this.state = 'initialized';
        handler('initialized');
      }, this.delayInitializedMs);
    } else {
      this.state = 'initialized';
      handler('initialized');
    }
  }

  private become(state: PlayerState): void {
    this.state = state;
    this.stateHandler(state);
  }

  async prepare(): Promise<void> {
    this.calls.push('prepare');
    this.become('prepared');
  }

  async play(): Promise<void> {
    this.calls.push('play');
    this.become('playing');
  }

  async pause(): Promise<void> {
    this.calls.push('pause');
    this.become('paused');
  }

  async stop(): Promise<void> {
    this.calls.push('stop');
    this.become('stopped');
  }

  async reset(): Promise<void> {
    this.calls.push('reset');
    this.become('idle');
  }

  async release(): Promise<void> {
    this.calls.push('release');
    this.become('released');
  }

  seek(timeMs: number): void {
    this.calls.push(`seek:${timeMs}`);
  }

  setSpeed(rate: number): void {
    this.calls.push(`speed:${rate}`);
  }

  setVolume(volume: number): void {
    this.calls.push(`volume:${volume}`);
  }

  onStateChange(handler: PlayerStateHandler): void {
    this.stateHandler = handler;
    this.boundCount += 1;
  }
  offStateChange(_handler: PlayerStateHandler): void {
    this.stateHandler = (_state: PlayerState): void => {};
    this.unboundCount += 1;
  }
  onError(_handler: PlayerErrorHandler): void { this.boundCount += 1; }
  offError(_handler: PlayerErrorHandler): void { this.unboundCount += 1; }
  onSeekDone(_handler: PlayerNumberHandler): void { this.boundCount += 1; }
  offSeekDone(_handler: PlayerNumberHandler): void { this.unboundCount += 1; }
  onDurationUpdate(handler: PlayerNumberHandler): void {
    this.durationUpdateHandler = handler;
    this.boundCount += 1;
  }
  offDurationUpdate(_handler: PlayerNumberHandler): void { this.unboundCount += 1; }
  onVideoSizeChange(handler: PlayerVideoSizeHandler): void {
    this.videoSizeChangeHandler = handler;
    this.boundCount += 1;
  }
  offVideoSizeChange(_handler: PlayerVideoSizeHandler): void {
    this.videoSizeChangeHandler = (_width: number, _height: number): void => {};
    this.unboundCount += 1;
  }
  onTimeUpdate(handler: PlayerNumberHandler): void {
    this.timeUpdateHandler = handler;
    this.boundCount += 1;
  }
  offTimeUpdate(_handler: PlayerNumberHandler): void {
    this.timeUpdateHandler = (_milliseconds: number): void => {};
    this.unboundCount += 1;
  }
  onSpeedDone(handler: PlayerNumberHandler): void {
    this.speedDoneHandler = handler;
    this.boundCount += 1;
  }
  offSpeedDone(_handler: PlayerNumberHandler): void { this.unboundCount += 1; }
  onVolumeChange(_handler: PlayerNumberHandler): void { this.boundCount += 1; }
  offVolumeChange(_handler: PlayerNumberHandler): void { this.unboundCount += 1; }
  onBufferingUpdate(_handler: BufferingUpdateHandler): void { this.boundCount += 1; }
  offBufferingUpdate(_handler: BufferingUpdateHandler): void { this.unboundCount += 1; }

  emitSpeedDone(rate: number): void {
    this.speedDoneHandler(rate);
  }

  emitTimeUpdate(milliseconds: number): void {
    this.timeUpdateHandler(milliseconds);
  }

  emitDurationUpdate(milliseconds: number): void {
    this.durationUpdateHandler(milliseconds);
  }

  emitVideoSizeChange(width: number, height: number): void {
    this.videoSizeChangeHandler(width, height);
  }
}

class FailingPreparePlayerAdapter extends FakePlayerAdapter {
  async prepare(): Promise<void> {
    throw new PlayerOperationError(5400106, 'unsupported format');
  }
}

class SilentPlaybackStateAdapter extends FakePlayerAdapter {
  async play(): Promise<void> {
    this.calls.push('play');
    this.state = 'playing';
  }

  async pause(): Promise<void> {
    this.calls.push('pause');
    this.state = 'paused';
  }
}

class HangingPausePlayerAdapter extends FakePlayerAdapter {
  async pause(): Promise<void> {
    this.calls.push('pause');
    await new Promise<void>((_resolve: () => void): void => {});
  }
}

class NativeLikeBusinessError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

class FailingSeekPlayerAdapter extends FakePlayerAdapter {
  seek(_timeMs: number): void {
    throw new NativeLikeBusinessError(5400103, 'invalid state');
  }
}

export default function task3PlayerTest(): void {
  describe('Task3 player presentation rules', (): void => {
    it('maps timeline input and exposes the seven specified speeds', 0, (): void => {
      expect(timelineTarget(-10, 200, 100)).assertEqual(0);
      expect(timelineTarget(50, 200, 100)).assertEqual(25);
      expect(timelineTarget(300, 200, 100)).assertEqual(100);
      expect(timelineTarget(10, 0, 100)).assertEqual(0);
      expect(PLAYER_SPEEDS.join(',')).assertEqual('0.5,0.75,1,1.25,1.5,2,3');
    });

    it('uses the iOS-aligned playback error copy', 0, (): void => {
      expect(playbackErrorText('recording')).assertEqual('正在录制，请稍后');
      expect(playbackErrorText('processing')).assertEqual('正在处理，请稍后');
      expect(playbackErrorText('ready')).assertEqual('视频暂时无法播放');
      expect(playbackErrorText(null)).assertEqual('视频暂时无法播放');
    });
  });

  describe('Task3 ProgressTracker interaction semantics', (): void => {
    it('freezes while interacting and resumes only after seekDone', 0, async (): Promise<void> => {
      const source: FakeProgressSource = new FakeProgressSource();
      const tracker: ProgressTracker = new ProgressTracker(source);
      expect(PLAYER_PROGRESS_INTERVAL_MS).assertEqual(250);

      tracker.sampleNow();
      tracker.beginInteracting();
      expect(tracker.isInteracting).assertTrue();
      expect(tracker.displayTime).assertEqual(12);
      expect(source.pauseCount).assertEqual(1);

      source.currentTime = 30;
      tracker.sampleNow();
      expect(tracker.displayTime).assertEqual(12);
      tracker.updateInteracting(42);
      expect(tracker.displayTime).assertEqual(42);

      tracker.endInteracting(42);
      expect(source.seekTarget).assertEqual(42);
      expect(tracker.isInteracting).assertTrue();
      expect(source.playCount).assertEqual(0);

      await tracker.handleSeekDone(42);
      expect(tracker.isInteracting).assertFalse();
      expect(source.playCount).assertEqual(1);
      expect(source.playedBeforePauseCompleted).assertFalse();
    });

    it('does not resume a player that was paused before interaction', 0, async (): Promise<void> => {
      const source: FakeProgressSource = new FakeProgressSource();
      source.isPlaying = false;
      const tracker: ProgressTracker = new ProgressTracker(source);
      tracker.beginInteracting();
      tracker.updateInteracting(20);
      tracker.endInteracting(20);
      await tracker.handleSeekDone(20);
      expect(source.pauseCount).assertEqual(0);
      expect(source.playCount).assertEqual(0);
    });

    it('ignores stale seekDone callbacks from another seek', 0, async (): Promise<void> => {
      const source: FakeProgressSource = new FakeProgressSource();
      const tracker: ProgressTracker = new ProgressTracker(source);
      tracker.beginInteracting();
      tracker.updateInteracting(40);
      await tracker.handleSeekDone(0);
      expect(tracker.isInteracting).assertTrue();
      expect(source.playCount).assertEqual(0);
      tracker.endInteracting(40);
      await tracker.handleSeekDone(40);
      expect(tracker.isInteracting).assertFalse();
      expect(source.playCount).assertEqual(1);
    });

    it('accepts the native seekDone position from SEEK_CLOSEST and leaves interaction mode', 0,
      async (): Promise<void> => {
        const source: FakeProgressSource = new FakeProgressSource();
        const tracker: ProgressTracker = new ProgressTracker(source);
        tracker.beginInteracting();
        tracker.updateInteracting(42);
        tracker.endInteracting(42);

        await tracker.handleSeekDone(40.5);

        expect(tracker.isInteracting).assertFalse();
        expect(tracker.displayTime).assertEqual(40.5);
        expect(source.playCount).assertEqual(1);
      });

    it('never resumes after the tracker is stopped while pause is pending', 0, async (): Promise<void> => {
      const source: FakeProgressSource = new FakeProgressSource();
      const tracker: ProgressTracker = new ProgressTracker(source);
      tracker.beginInteracting();
      tracker.endInteracting(30);
      const seekDoneTask: Promise<void> = tracker.handleSeekDone(30);
      tracker.stop();
      await seekDoneTask;
      expect(source.playCount).assertEqual(0);
    });

    it('leaves interaction mode and restores prior playback when drag is cancelled', 0, async (): Promise<void> => {
      const source: FakeProgressSource = new FakeProgressSource();
      const tracker: ProgressTracker = new ProgressTracker(source);
      tracker.beginInteracting();
      tracker.updateInteracting(24);
      await tracker.cancelInteracting();
      expect(tracker.isInteracting).assertFalse();
      expect(source.playCount).assertEqual(1);
      expect(source.playedBeforePauseCompleted).assertFalse();
    });
  });

  describe('Task3 PlayerController lifecycle', (): void => {
    it('sets up playback and releases every event exactly once', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      await controller.setup('https://server/video.mp4', 'surface-1');
      expect(adapter.url).assertEqual('https://server/video.mp4');
      expect(adapter.surfaceId).assertEqual('surface-1');
      expect(adapter.calls.join(',')).assertEqual('prepare,play');
      expect(adapter.boundCount).assertEqual(9);
      expect(controller.duration).assertEqual(120);
      expect(controller.currentTime).assertEqual(5);
      expect(controller.isPlaying).assertTrue();

      controller.seek(12.5);
      controller.setVolume(2);
      expect(adapter.calls.slice(2).join(',')).assertEqual('seek:12500,volume:1');

      await controller.release();
      await controller.release();
      expect(adapter.calls.slice(4).join(',')).assertEqual('pause,stop,reset,release');
      expect(adapter.unboundCount).assertEqual(9);
    });

    it('refreshes native currentTime when timeUpdate is silent', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      await controller.setup('https://server/video.mp4', 'surface-1');

      adapter.currentTime = 37500;
      expect(controller.refreshCurrentTime()).assertEqual(37.5);
      expect(controller.currentTime).assertEqual(37.5);
      await controller.release();
    });

    it('keeps advancing from native polling after timeUpdate fired once and went silent', 0,
      async (): Promise<void> => {
        const adapter: FakePlayerAdapter = new FakePlayerAdapter();
        const controller: PlayerController =
          new PlayerController(async (): Promise<PlayerAdapter> => adapter);
        await controller.setup('https://server/video.mp4', 'surface-1');

        adapter.emitTimeUpdate(5000);
        expect(controller.currentTime).assertEqual(5);
        adapter.currentTime = 37500;
        expect(controller.refreshCurrentTime()).assertEqual(37.5);
        expect(controller.currentTime).assertEqual(37.5);
        await controller.release();
      });

    it('never lets a stale native currentTime regress the event-driven cache', 0,
      async (): Promise<void> => {
        const adapter: FakePlayerAdapter = new FakePlayerAdapter();
        const controller: PlayerController =
          new PlayerController(async (): Promise<PlayerAdapter> => adapter);
        await controller.setup('https://server/video.mp4', 'surface-1');

        adapter.emitTimeUpdate(60000);
        expect(controller.currentTime).assertEqual(60);
        adapter.currentTime = 5000;
        expect(controller.refreshCurrentTime()).assertEqual(60);
        expect(controller.currentTime).assertEqual(60);
        await controller.release();
      });

    it('forwards native videoSizeChange so the page can keep the surface aspect-correct', 0,
      async (): Promise<void> => {
        const adapter: FakePlayerAdapter = new FakePlayerAdapter();
        const controller: PlayerController =
          new PlayerController(async (): Promise<PlayerAdapter> => adapter);
        let reportedWidth: number = 0;
        let reportedHeight: number = 0;
        controller.onVideoSizeChange = (width: number, height: number): void => {
          reportedWidth = width;
          reportedHeight = height;
        };
        await controller.setup('https://server/video.mp4', 'surface-1');

        adapter.emitVideoSizeChange(1080, 1920);
        expect(reportedWidth).assertEqual(1080);
        expect(reportedHeight).assertEqual(1920);

        await controller.release();
        adapter.emitVideoSizeChange(720, 1280);
        expect(reportedHeight).assertEqual(1920);
      });
    it('converts native timeUpdate milliseconds to observable UI seconds', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      let observedSeconds: number = -1;
      controller.onTimeUpdate = (seconds: number): void => {
        observedSeconds = seconds;
      };
      await controller.setup('https://server/video.mp4', 'surface-1');

      adapter.emitTimeUpdate(6250);

      expect(controller.currentTime).assertEqual(6.25);
      expect(observedSeconds).assertEqual(6.25);
      await controller.release();
    });

    it('uses durationUpdate when the native duration property is still zero', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      adapter.duration = 0;
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      await controller.setup('https://server/video.mp4', 'surface-1');

      adapter.emitDurationUpdate(90000);

      expect(controller.duration).assertEqual(90);
      await controller.release();
    });

    it('does not seek while duration is not ready', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      adapter.duration = 0;
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      await controller.setup('https://server/video.mp4', 'surface-1');

      controller.seek(10);

      expect(adapter.calls.join(',')).assertEqual('prepare,play');
      await controller.release();
    });

    it('publishes native state after play and pause promises even when stateChange is delayed', 0,
      async (): Promise<void> => {
        const adapter: SilentPlaybackStateAdapter = new SilentPlaybackStateAdapter();
        const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
        let observedState: PlayerState = 'idle';
        controller.onStateChange = (state: PlayerState): void => {
          observedState = state;
        };

        await controller.setup('https://server/video.mp4', 'surface-1');
        expect(observedState).assertEqual('playing');

        await controller.pause();
        expect(observedState).assertEqual('paused');
        await controller.release();
      });

    it('still stops and releases the native player when pause never settles', 0, async (): Promise<void> => {
      const adapter: HangingPausePlayerAdapter = new HangingPausePlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      await controller.setup('https://server/video.mp4', 'surface-1');
      expect(adapter.state).assertEqual('playing');

      await controller.release();

      expect(adapter.calls.join(',')).assertEqual('prepare,play,pause,stop,reset,release');
      expect(controller.state).assertEqual('released');
    });

    it('withTimeout keeps the settled value of a task that finishes in time', 0, async (): Promise<void> => {
      const result: string | null = await withTimeout(Promise.resolve('ok'), 1000, 'fast task');
      expect(result).assertEqual('ok');
    });

    it('withTimeout resolves null instead of hanging forever on a stuck task', 0, async (): Promise<void> => {
      const hanging: Promise<string> = new Promise<string>((_resolve: (value: string) => void): void => {});
      const startedAt: number = Date.now();
      const result: string | null = await withTimeout(hanging, 30, 'stuck task');
      expect(result === null).assertTrue();
      expect(Date.now() - startedAt >= 25).assertTrue();
    });

    it('waits for the async initialized event before setting surfaceId', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      adapter.delayInitializedMs = 20;
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      await controller.setup('https://server/video.mp4', 'surface-1');
      expect(adapter.surfaceId).assertEqual('surface-1');
      expect(adapter.calls.join(',')).assertEqual('prepare,play');
      expect(controller.isPlaying).assertTrue();
      await controller.release();
    });

    it('releases a late-created player instead of playing after close', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      let finishCreating: (value: PlayerAdapter) => void = (_value: PlayerAdapter): void => {};
      const factoryResult: Promise<PlayerAdapter> = new Promise<PlayerAdapter>(
        (resolve: (value: PlayerAdapter) => void): void => {
          finishCreating = resolve;
        });
      const controller: PlayerController = new PlayerController((): Promise<PlayerAdapter> => factoryResult);
      const setupTask: Promise<void> = controller.setup('https://server/video.mp4', 'surface-1');
      await controller.release();
      finishCreating(adapter);
      await setupTask;
      expect(adapter.calls.join(',')).assertEqual('release');
      expect(adapter.boundCount).assertEqual(0);
    });

    it('publishes the effective speed reported by the native player', 0, async (): Promise<void> => {
      const adapter: FakePlayerAdapter = new FakePlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      let effectiveRate: number = 1;
      controller.onSpeedChange = (rate: number): void => {
        effectiveRate = rate;
      };
      await controller.setup('https://server/video.mp4', 'surface-1');
      adapter.emitSpeedDone(2);
      expect(effectiveRate).assertEqual(2);
    });

    it('preserves operation error codes for the error presentation path', 0, async (): Promise<void> => {
      const adapter: FailingPreparePlayerAdapter = new FailingPreparePlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      let errorCode: number = 0;
      let errorMessage: string = '';
      controller.onError = (code: number, message: string): void => {
        errorCode = code;
        errorMessage = message;
      };
      await controller.setup('https://server/video.mp4', 'surface-1');
      expect(errorCode).assertEqual(5400106);
      expect(errorMessage).assertEqual('unsupported format');
    });

    it('preserves native-like error codes from synchronous player calls', 0, async (): Promise<void> => {
      const adapter: FailingSeekPlayerAdapter = new FailingSeekPlayerAdapter();
      const controller: PlayerController = new PlayerController(async (): Promise<PlayerAdapter> => adapter);
      let errorCode: number = 0;
      controller.onError = (code: number, _message: string): void => {
        errorCode = code;
      };
      await controller.setup('https://server/video.mp4', 'surface-1');
      controller.seek(10);
      expect(errorCode).assertEqual(5400103);
    });
  });
}
