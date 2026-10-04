import { ApiError, ApiErrorType } from '../model/Common';
import { CreatePlaybackSession, PlaybackCapabilities, PlaybackSession, RecordingIdentity, V2ApiError } from '../model/PlaybackV2';
import { APIClient } from '../net/APIClient';

export class PlayerViewModel {
  onReady: (session: PlaybackSession) => Promise<void> = async (_session: PlaybackSession): Promise<void> => {};
  onError: (error: Error) => void = (_error: Error): void => {};
  private generation: number = 0;
  private session: PlaybackSession | null = null;
  private playedAsset: string = '';
  private timer: number = -1;
  private wake: (() => void) | null = null;
  private body: CreatePlaybackSession | null = null;
  private refreshing: boolean = false;
  private refreshFailures: number = 0;
  private readonly client: APIClient;

  constructor(client: APIClient) { this.client = client; }

  async open(identity: RecordingIdentity, capabilities: PlaybackCapabilities): Promise<void> {
    const closing: Promise<void> = this.close();
    const token: number = this.generation;
    await closing;
    if (token !== this.generation) return;
    this.body = { recording_id: identity.recording_id, source_version: identity.source_version, capabilities: capabilities };
    this.refreshFailures = 0;
    try {
      const session: PlaybackSession = await this.client.createPlaybackSession(this.body);
      if (token !== this.generation) { await this.cancelQuietly(session.id); return; }
      this.session = session;
      await this.waitUntilReady(session, token);
    } catch (error) { this.fail(error, token); }
  }

  async close(): Promise<void> {
    ++this.generation;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    const wake: (() => void) | null = this.wake;
    this.wake = null;
    if (wake !== null) wake();
    const session: PlaybackSession | null = this.session;
    this.session = null;
    this.body = null;
    this.playedAsset = '';
    this.refreshing = false;
    if (session !== null) await this.cancelQuietly(session.id);
  }

  private async waitUntilReady(initial: PlaybackSession, token: number): Promise<void> {
    let session: PlaybackSession = initial;
    while (token === this.generation) {
      this.checkIdentity(session);
      this.session = session;
      if (session.status === 'ready') {
        if (this.playedAsset.length > 0 && this.playedAsset !== session.asset_version) {
          await this.cancelQuietly(session.id); this.session = null;
          throw ApiError.decoding('播放资产版本已变化，请重新打开');
        }
        this.playedAsset = session.asset_version;
        await this.onReady(session);
        if (token === this.generation) this.scheduleRefresh(session.refresh_after_seconds ?? 1, token);
        return;
      }
      if (session.status !== 'processing' && session.status !== 'paused') {
        throw ApiError.server(409, session.error?.message ?? '播放会话已取消');
      }
      await this.delay(this.retrySeconds(session.retry_after_seconds), token);
      if (token !== this.generation) return;
      session = await this.client.getPlaybackSession(session.id);
    }
  }

  private scheduleRefresh(seconds: number, token: number): void {
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.refresh(token).catch((error: Object): void => this.fail(error, token));
    }, Math.max(1, seconds) * 1000);
  }

  private async refresh(token: number): Promise<void> {
    if (token !== this.generation || this.session === null || this.body === null || this.refreshing) return;
    this.refreshing = true;
    const previous: PlaybackSession = this.session;
    const body: CreatePlaybackSession = this.body;
    try {
      let session: PlaybackSession;
      try { session = await this.client.getPlaybackSession(previous.id); } catch (error) {
        if (!(error instanceof V2ApiError) || error.code !== 'session_expired' || token !== this.generation) throw error instanceof Error ? error : new Error(`${error}`);
        session = await this.client.createPlaybackSession(body);
        if (token !== this.generation) { await this.cancelQuietly(session.id); return; }
        // 旧实例已失效；新会话仍必须绑定同一个来源身份。
        this.session = session;
      }
      if (token !== this.generation) return;
      this.checkIdentity(session);
      if (session.status === 'ready' && session.refresh_after_seconds === 0) {
        const renewed: PlaybackSession = await this.client.createPlaybackSession(body);
        if (token !== this.generation) { await this.cancelQuietly(renewed.id); return; }
        this.session = renewed;
        this.checkIdentity(renewed);
        await this.cancelQuietly(session.id);
        if (token !== this.generation) return;
        session = renewed;
      }
      this.refreshFailures = 0;
      await this.waitUntilReady(session, token);
    } catch (error) {
      if (token !== this.generation) return;
      const retryable: boolean = error instanceof V2ApiError ? error.retryable :
        error instanceof ApiError && error.type === ApiErrorType.NETWORK;
      if (retryable && ++this.refreshFailures <= 3) {
        this.scheduleRefresh(error instanceof V2ApiError ? this.retrySeconds(error.retryAfterSeconds) : 2, token);
      } else { this.fail(error, token); }
    } finally {
      if (token === this.generation) this.refreshing = false;
    }
  }

  private checkIdentity(session: PlaybackSession): void {
    if (this.body === null || session.recording_id !== this.body.recording_id ||
      session.source_version !== this.body.source_version ||
      (this.session !== null && session.id !== this.session.id)) {
      throw ApiError.decoding('播放会话身份不匹配');
    }
  }

  private retrySeconds(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.min(60, Math.max(1, value)) : 2;
  }

  private delay(seconds: number, token: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      if (token !== this.generation) { resolve(); return; }
      this.wake = resolve;
      this.timer = setTimeout((): void => { this.timer = -1; this.wake = null; resolve(); }, seconds * 1000);
    });
  }

  private fail(error: Object, token: number): void {
    if (token !== this.generation) return;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    this.onError(error instanceof Error ? error : new Error(`${error}`));
  }

  private async cancelQuietly(id: string): Promise<void> {
    try { await this.client.cancelPlaybackSession(id); } catch (_) {}
  }
}
