import { describe, expect, it } from '@ohos/hypium';
import { APIClient, APIRequestOptions } from '../main/ets/net/APIClient';
import { ApiError, ApiErrorType } from '../main/ets/model/Common';

class PlaybackResponseClient extends APIClient {
  response: string = '';
  constructor() { super('https://server/proxy', 'test key'); }
  async request<T>(_method: string, _path: string, _body?: Object,
    _opts: APIRequestOptions = {}): Promise<T> {
    return JSON.parse(this.response) as T;
  }
}

export default function playbackContractTest(): void {
  describe('Playback resolver contract', (): void => {
    it('unwraps data and normalizes a ready media URL with key fallback', 0, async (): Promise<void> => {
      const client: PlaybackResponseClient = new PlaybackResponseClient();
      client.response = '{"err_no":0,"data":{"status":"ready","url":"/files/clip.mp4"}}';
      const result = await client.resolvePlayback('clip.mp4');
      expect(result.status).assertEqual('ready');
      expect(result.url).assertEqual('https://server/proxy/files/clip.mp4?_key=test%20key');
    });
    it('preserves signed HLS queries and existing absolute media URLs', 0, (): void => {
      expect(APIClient.buildMediaUrl('https://server', 'key', '/hls/playlist.m3u8?expires=123&sig=abc'))
        .assertEqual('https://server/hls/playlist.m3u8?expires=123&sig=abc');
      expect(APIClient.buildMediaUrl('https://server', '', 'https://media/clip.mp4?a=1'))
        .assertEqual('https://media/clip.mp4?a=1');
    });
    it('rejects unknown states missing data and ready without URL', 0, async (): Promise<void> => {
      const client: PlaybackResponseClient = new PlaybackResponseClient();
      for (const response of ['{"data":{"status":"unknown"}}', '{"data":null}',
        '{"data":{"status":"ready"}}']) {
        client.response = response;
        let rejected: boolean = false;
        try { await client.resolvePlayback('clip.mp4'); } catch (error) {
          rejected = error instanceof ApiError && error.type === ApiErrorType.DECODING;
        }
        expect(rejected).assertTrue();
      }
    });
    it('defaults malformed retry values and clamps finite intervals', 0, async (): Promise<void> => {
      const client: PlaybackResponseClient = new PlaybackResponseClient();
      client.response = '{"data":{"status":"processing","retry_after_seconds":"bad"}}';
      expect((await client.resolvePlayback('clip.flv')).retry_after_seconds).assertEqual(2);
      expect(APIClient.playbackRetrySeconds(undefined)).assertEqual(2);
      expect(APIClient.playbackRetrySeconds(Number.NaN)).assertEqual(2);
      expect(APIClient.playbackRetrySeconds(Number.POSITIVE_INFINITY)).assertEqual(2);
      expect(APIClient.playbackRetrySeconds(-10)).assertEqual(1);
      expect(APIClient.playbackRetrySeconds(100)).assertEqual(10);
    });
    it('allows old endpoint fallback but keeps file and authentication errors', 0, (): void => {
      expect(APIClient.canFallbackPlayback(ApiError.server(404, '404 page not found'))).assertTrue();
      expect(APIClient.canFallbackPlayback(ApiError.server(405, 'Method Not Allowed'))).assertTrue();
      expect(APIClient.canFallbackPlayback(ApiError.server(404, '视频不存在'))).assertFalse();
      expect(APIClient.canFallbackPlayback(ApiError.unauthorized())).assertFalse();
      expect(APIClient.canFallbackPlayback(ApiError.decoding('未知状态'))).assertFalse();
      expect(APIClient.canFallbackPlayback(ApiError.network('请求超时'))).assertFalse();
    });
  });
}
