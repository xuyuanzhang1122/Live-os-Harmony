export const PLAYER_PROGRESS_INTERVAL_MS: number = 250;

export interface ProgressSource {
  currentTime: number;
  isPlaying: boolean;
  play(): Promise<void>;
  pause(): Promise<void>;
  seek(seconds: number): void;
}

export class ProgressTracker {
  readonly source: ProgressSource;
  displayTime: number = 0;
  isInteracting: boolean = false;
  onTimeUpdate: (seconds: number) => void = (_seconds: number): void => {};
  private timer: number = -1;
  private resumeAfterSeek: boolean = false;
  private pauseTask: Promise<void> = Promise.resolve();
  private interactionToken: number = 0;
  private pendingSeekTarget: number | null = null;

  constructor(source: ProgressSource) {
    this.source = source;
  }

  start(): void {
    if (this.timer >= 0) {
      return;
    }
    this.sampleNow();
    this.timer = setInterval((): void => this.sampleNow(), PLAYER_PROGRESS_INTERVAL_MS);
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.interactionToken += 1;
    this.isInteracting = false;
    this.resumeAfterSeek = false;
    this.pauseTask = Promise.resolve();
    this.pendingSeekTarget = null;
  }

  sampleNow(): void {
    if (this.isInteracting) {
      return;
    }
    this.publish(this.source.currentTime);
  }

  beginInteracting(): void {
    if (this.isInteracting) {
      return;
    }
    this.interactionToken += 1;
    this.pendingSeekTarget = null;
    this.resumeAfterSeek = this.source.isPlaying;
    this.isInteracting = true;
    this.publish(this.source.currentTime);
    if (this.resumeAfterSeek) {
      this.pauseTask = this.source.pause().catch((): void => {});
    } else {
      this.pauseTask = Promise.resolve();
    }
  }

  updateInteracting(targetSeconds: number): void {
    if (!this.isInteracting) {
      return;
    }
    this.publish(targetSeconds);
  }

  endInteracting(targetSeconds: number): void {
    if (!this.isInteracting) {
      return;
    }
    this.publish(targetSeconds);
    this.pendingSeekTarget = targetSeconds;
    this.source.seek(targetSeconds);
  }

  async cancelInteracting(): Promise<void> {
    if (!this.isInteracting) {
      return;
    }
    const shouldResume: boolean = this.resumeAfterSeek;
    this.interactionToken += 1;
    const token: number = this.interactionToken;
    this.isInteracting = false;
    this.resumeAfterSeek = false;
    this.pendingSeekTarget = null;
    this.publish(this.source.currentTime);
    if (shouldResume) {
      await this.pauseTask;
      if (token !== this.interactionToken) {
        return;
      }
      await this.source.play();
    }
  }

  async handleSeekDone(seconds: number): Promise<void> {
    const pendingTarget: number | null = this.pendingSeekTarget;
    if (!this.isInteracting || pendingTarget === null || Math.abs(seconds - pendingTarget) > 0.05) {
      return;
    }
    const token: number = this.interactionToken;
    const shouldResume: boolean = this.isInteracting && this.resumeAfterSeek;
    this.publish(seconds);
    this.isInteracting = false;
    this.resumeAfterSeek = false;
    this.pendingSeekTarget = null;
    if (shouldResume) {
      await this.pauseTask;
      if (token !== this.interactionToken) {
        return;
      }
      await this.source.play();
    }
  }

  private publish(seconds: number): void {
    this.displayTime = Number.isFinite(seconds) && seconds > 0 ? seconds : 0;
    this.onTimeUpdate(this.displayTime);
  }
}
