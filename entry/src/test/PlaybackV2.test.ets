import { describe, expect, it } from '@ohos/hypium';
import { APIClient, APIRequestOptions } from '../main/ets/net/APIClient';
import { CreatePlaybackSession, PlaybackSession, validateSession, V2ApiError } from '../main/ets/model/PlaybackV2';
import { PlayerViewModel } from '../main/ets/viewmodel/PlayerViewModel';
import { V2SessionReady, V2SessionProcessing, V2SessionPaused, V2SessionFailed, V2SessionCancelled } from './V2Fixtures';
import { V2Envelope } from '../main/ets/model/PlaybackV2';

class SessionClient extends APIClient {
  value: string = V2SessionReady;
  creates: number = 0;
  cancels: number = 0;
  constructor() { super('https://server/proxy', 'management-key', 'v2'); }
  async request<T>(_method: string, _path: string, _body?: Object, _opts: APIRequestOptions = {}): Promise<T> {
    const envelope: V2Envelope<T> = JSON.parse(this.value) as V2Envelope<T>;
    return envelope.data as T;
  }
  async createPlaybackSession(_body: CreatePlaybackSession): Promise<PlaybackSession> { this.creates++; return this.getPlaybackSession('session'); }
  async cancelPlaybackSession(_id: string): Promise<void> { this.cancels++; }
}

export default function playbackV2Test(): void {
  describe('T6 v2 playback contract', (): void => {
    it('shared ready uses short media token without management key', 0, async (): Promise<void> => {
      const client: SessionClient = new SessionClient();
      const session: PlaybackSession = await client.getPlaybackSession('session');
      expect(session.status).assertEqual('ready');
      expect((session.url ?? '').startsWith('https://server/proxy/api/v2/media/')).assertTrue();
      expect((session.url ?? '').includes('play_token=')).assertTrue();
      expect((session.url ?? '').includes('_key=')).assertFalse();
    });
    it('shared nonready states remain distinct and never have media URLs', 0, async (): Promise<void> => {
      const client: SessionClient = new SessionClient();
      for (const value of [V2SessionProcessing, V2SessionPaused, V2SessionFailed, V2SessionCancelled]) {
        client.value = value;
        const session: PlaybackSession = await client.getPlaybackSession('session');
        expect(session.url === undefined).assertTrue();
      }
    });
    it('normalizes omitted zero refresh only near hard expiry', 0, async (): Promise<void> => {
      const client: SessionClient = new SessionClient();
      const envelope: V2Envelope<PlaybackSession> = JSON.parse(V2SessionReady) as V2Envelope<PlaybackSession>;
      const value: PlaybackSession = envelope.data as PlaybackSession;
      value.refresh_after_seconds = undefined;
      value.expires_at = Math.floor(Date.now() / 1000) + 30;
      value.token_expires_at = value.expires_at;
      client.value = JSON.stringify(envelope);
      expect((await client.getPlaybackSession('session')).refresh_after_seconds).assertEqual(0);
    });
    it('unknown state fails closed' , 0, (): void => {
      const envelope: V2Envelope<PlaybackSession> = JSON.parse(V2SessionReady) as V2Envelope<PlaybackSession>;
      const value: PlaybackSession = envelope.data as PlaybackSession;
      value.status = 'unknown';
      let failed: boolean = false;
      try { validateSession(value); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
    it('native error code and request identity stay available', 0, (): void => {
      const error: V2ApiError = new V2ApiError(410, { code: 'session_expired', message: '已过期', retryable: false }, 'trace');
      expect(error.code).assertEqual('session_expired');
      expect(error.retryable).assertFalse();
      expect(error.requestId).assertEqual('trace');
    });
    it('open and close cancel the actual server session once', 0, async (): Promise<void> => {
      const client: SessionClient = new SessionClient();
      const model: PlayerViewModel = new PlayerViewModel(client);
      const envelope: V2Envelope<PlaybackSession> = JSON.parse(V2SessionReady) as V2Envelope<PlaybackSession>;
      const value: PlaybackSession = envelope.data as PlaybackSession;
      let ready: number = 0;
      model.onReady = async (_session: PlaybackSession): Promise<void> => { ready++; };
      await model.open({ recording_id: value.recording_id, source_version: value.source_version },
        { containers: ['mp4'], protocols: ['file'], video: [], audio: [] });
      await model.close();
      await model.close();
      expect(ready).assertEqual(1);
      expect(client.creates).assertEqual(1);
      expect(client.cancels).assertEqual(1);
    });
    it('immediate exit prevents a late creation continuation', 0, async (): Promise<void> => {
      const client: SessionClient = new SessionClient();
      const model: PlayerViewModel = new PlayerViewModel(client);
      const opening: Promise<void> = model.open({ recording_id: 'r', source_version: 'v' },
        { containers: ['mp4'], protocols: ['file'], video: [], audio: [] });
      await model.close();
      await opening;
      expect(client.creates).assertEqual(0);
    });
  });
}
