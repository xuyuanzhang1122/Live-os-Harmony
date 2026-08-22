import { describe, expect, it } from '@ohos/hypium';
import { Formats } from '../main/ets/common/Formats';
import { sha256Hex } from '../main/ets/common/Sha256';
import { AppConfig } from '../main/ets/config/AppConfig';
import { APIClient } from '../main/ets/net/APIClient';
import { ApiCache, CacheClock } from '../main/ets/net/ApiCache';
import {
  BackupDeviceConfig,
  BackupPackage,
  ServerConfigInput,
  ServerLiveRoomInput,
  ServerRpcConfigInput
} from '../main/ets/model/BackupModels';
import { VideoFileInfo } from '../main/ets/model/VideoLibrary';
import { LruCache } from '../main/ets/cache/LruCache';
import { ThumbnailCache } from '../main/ets/cache/ThumbnailCache';
import {
  clamp,
  horizontalSeekTarget,
  isSideZone,
  lockPullSatisfied,
  resumeTarget,
  seekRangeFor,
  shouldResume
} from '../main/ets/player/PlayerMath';

class MutableClock implements CacheClock {
  nowValue: number;

  constructor(nowValue: number) {
    this.nowValue = nowValue;
  }

  now(): number {
    return this.nowValue;
  }
}

function videoFile(name: string, relPath: string, fileUrl: string | null,
  thumbnailUrl: string | null, hlsUrl: string | null): VideoFileInfo {
  return new VideoFileInfo({
    name: name,
    rel_path: relPath,
    size: 1,
    mod_time: '2026-05-01 12:00:00',
    file_url: fileUrl,
    thumbnail_url: thumbnailUrl,
    hls_url: hlsUrl,
    recording: false,
    playback_status: 'ready'
  });
}

export default function task1InfrastructureTest(): void {
  describe('Task1 API URL helpers', (): void => {
    it('encodes every path segment and preserves slash separators', 0, (): void => {
      expect(APIClient.encodePathSegments('抖音/主播 A/[]{}|\\^"#%<>.flv'))
        .assertEqual('%E6%8A%96%E9%9F%B3/%E4%B8%BB%E6%92%AD%20A/%5B%5D%7B%7D%7C%5C%5E%22%23%25%3C%3E.flv');
    });

    it('uses all playback URL branches and key fallback rules', 0, (): void => {
      const base: string = 'http://server:8080/';
      expect(APIClient.buildPlaybackUrl(base, 'a b', videoFile('a.flv', '房间/a.flv', null, null,
        '/hls/a.m3u8?expires=1&sig=s'))).assertEqual('http://server:8080/hls/a.m3u8?expires=1&sig=s');
      expect(APIClient.buildPlaybackUrl(base, 'key', videoFile('a.mp4', '房间/a.mp4', '/files/a.mp4', null,
        null))).assertEqual('http://server:8080/files/a.mp4?_key=key');
      expect(APIClient.buildPlaybackUrl(base, 'key', videoFile('A.MP4', '房间/A.MP4', null, null, null)))
        .assertEqual('http://server:8080/files/%E6%88%BF%E9%97%B4/A.MP4?_key=key');
      expect(APIClient.buildPlaybackUrl(base, '', videoFile('a.flv', '房间/a.flv', null, null, null)))
        .assertEqual('http://server:8080/api/stream/hls/%E6%88%BF%E9%97%B4/a.flv');
      expect(APIClient.appendKeyIfUnsigned('https://x/a?foo=1', 'a b'))
        .assertEqual('https://x/a?foo=1&_key=a%20b');
    });

    it('uses thumbnail URL then fallback and preserves signed URLs', 0, (): void => {
      const signedFile: VideoFileInfo = videoFile('a.flv', '房间/a.flv', null,
        '/thumb/a.jpg?sig=s&expires=1', null);
      expect(APIClient.buildThumbnailUrl('http://server/', 'key', signedFile))
        .assertEqual('http://server/thumb/a.jpg?sig=s&expires=1');
      const fallbackFile: VideoFileInfo = videoFile('a.flv', '房间/a.flv', null, null, null);
      expect(APIClient.buildThumbnailUrl('http://server/', 'key', fallbackFile))
        .assertEqual('http://server/api/thumbnail/%E6%88%BF%E9%97%B4/a.flv?_key=key');
    });
  });

  describe('Task1 backup models', (): void => {
    it('serializes sorted iOS-compatible keys and round trips', 0, (): void => {
      const cfg: ServerConfigInput = {
        rpc: { bind: ':8080' },
        out_put_path: './recordings',
        app_data_path: '.appdata',
        live_rooms: [{ url: 'https://live.example/a', is_listening: true }]
      };
      const device: BackupDeviceConfig = new BackupDeviceConfig('http://main', 'http://lan', 'https://public', true);
      const pkg: BackupPackage = BackupPackage.fromServerConfig(device, cfg, '2026-05-04T12:00:00Z');
      const json: string = pkg.toJson();
      expect(json.indexOf('"exportedAt"') < json.indexOf('"iosConfig"')).assertTrue();
      expect(json.indexOf('"iosConfig"') < json.indexOf('"schemaVersion"')).assertTrue();
      expect(json.indexOf('"schemaVersion"') < json.indexOf('"server"')).assertTrue();
      expect(json.indexOf('"autoSwitchNetwork"') < json.indexOf('"lanURL"')).assertTrue();
      expect(json.indexOf('"iosConfig"') >= 0).assertTrue();
      const restored: BackupPackage = BackupPackage.fromJson(json);
      expect(restored.exportedAt).assertEqual('2026-05-04T12:00:00Z');
      expect(restored.server.live_rooms[0].is_listening).assertTrue();
      const map: Map<string, Object> = new Map<string, Object>();
      const rpc: ServerRpcConfigInput = { bind: ':9090' };
      const emptyRooms: ServerLiveRoomInput[] = [];
      map.set('rpc', rpc);
      map.set('out_put_path', './map-output');
      map.set('app_data_path', '.map-data');
      map.set('live_rooms', emptyRooms);
      expect(BackupPackage.fromServerConfig(device, map).server.rpc_bind).assertEqual(':9090');
    });

    it('tolerates missing backup fields', 0, (): void => {
      const pkg: BackupPackage = BackupPackage.fromJson('{"schemaVersion":1}');
      expect(pkg.iosConfig.serverURL).assertEqual('');
      expect(pkg.server.live_rooms.length).assertEqual(0);
      expect(pkg.exportedAt).assertEqual('');
    });
  });

  describe('Task1 PlayerMath', (): void => {
    it('covers clamps, seek range and horizontal seek', 0, (): void => {
      expect(clamp(5, 0, 4)).assertEqual(4);
      expect(seekRangeFor(null)).assertEqual(90);
      expect(seekRangeFor(100)).assertEqual(30);
      expect(seekRangeFor(4000)).assertEqual(300);
      expect(horizontalSeekTarget(50, 50, 100, 100)).assertEqual(65);
      expect(horizontalSeekTarget(90, 1000, 100, 100)).assertEqual(100);
      expect(horizontalSeekTarget(20, 10, 0, 100)).assertEqual(20);
    });

    it('covers resume boundaries and gesture zones', 0, (): void => {
      expect(shouldResume(5, 100)).assertFalse();
      expect(shouldResume(5.01, 100)).assertTrue();
      expect(shouldResume(95, 100)).assertFalse();
      expect(resumeTarget(-1, 100)).assertEqual(0);
      expect(resumeTarget(100, 100)).assertEqual(99);
      expect(isSideZone(28, 100)).assertFalse();
      expect(isSideZone(72, 100)).assertFalse();
      expect(isSideZone(27.99, 100)).assertTrue();
      expect(isSideZone(72.01, 100)).assertTrue();
      expect(lockPullSatisfied(40, 70, 100)).assertTrue();
      expect(lockPullSatisfied(41, 70, 100)).assertFalse();
      expect(lockPullSatisfied(10, 40, 100)).assertFalse();
    });
  });

  describe('Task1 formatting', (): void => {
    it('formats bytes clocks and speed labels', 0, (): void => {
      expect(Formats.formatBytes(0)).assertEqual('0.0 B');
      expect(Formats.formatBytes(1024)).assertEqual('1.0 KB');
      expect(Formats.formatBytes(1024 * 1024)).assertEqual('1.0 MB');
      expect(Formats.formatBytes(1024 * 1024 * 1024)).assertEqual('1.0 GB');
      expect(Formats.formatClock(65)).assertEqual('01:05');
      expect(Formats.formatClock(3661)).assertEqual('1:01:01');
      expect(Formats.formatSpeedLabel(0.5)).assertEqual('0.50x');
    });

    it('formats relative time branches', 0, (): void => {
      const now: number = Date.parse('2026-05-04T12:00:00Z');
      expect(Formats.formatRelativeTime('2026-05-04T11:59:40Z', now)).assertEqual('刚刚');
      expect(Formats.formatRelativeTime('2026-05-04T11:55:00Z', now)).assertEqual('5 分钟前');
      expect(Formats.formatRelativeTime('2026-05-04T09:00:00Z', now)).assertEqual('3 小时前');
      expect(Formats.formatRelativeTime('2026-05-01T09:00:00Z', now)).assertEqual('2026-05-01');
    });
  });

  describe('Task1 cache policies', (): void => {
    it('uses standard SHA-256 hex keys', 0, (): void => {
      expect(sha256Hex('abc')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    it('evaluates API cache TTL with an injected clock', 0, (): void => {
      const clock: MutableClock = new MutableClock(1000);
      const cache: ApiCache = new ApiCache('', clock);
      expect(cache.isFreshTimestamp(1000 - 30 * 60 * 1000)).assertTrue();
      clock.nowValue += 1;
      expect(cache.isFreshTimestamp(1000 - 30 * 60 * 1000)).assertFalse();
    });

    it('evicts least recently used entries by count and bytes', 0, (): void => {
      const cache: LruCache<string, string> = new LruCache<string, string>(2, 5);
      cache.set('a', 'aa', 2);
      cache.set('b', 'bb', 2);
      expect(cache.get('a')).assertEqual('aa');
      cache.set('c', 'ccc', 3);
      expect(cache.get('b')).assertUndefined();
      expect(cache.get('a')).assertEqual('aa');
    });

    it('only permits disk thumbnail reads for session-loaded URLs', 0, (): void => {
      const loaded: Set<string> = new Set<string>();
      expect(ThumbnailCache.canUseDisk('https://x/a.jpg', loaded)).assertFalse();
      loaded.add('https://x/a.jpg');
      expect(ThumbnailCache.canUseDisk('https://x/a.jpg', loaded)).assertTrue();
    });
  });

  describe('Task1 AppConfig decisions', (): void => {
    it('matches manual, dual, partial and empty network decisions', 0, (): void => {
      expect(AppConfig.selectActiveURL(false, 'http://manual', 'http://lan', 'https://public', true))
        .assertEqual('http://manual');
      expect(AppConfig.selectActiveURL(true, '', 'http://lan', 'https://public', true)).assertEqual('http://lan');
      expect(AppConfig.selectActiveURL(true, '', 'http://lan', 'https://public', false)).assertEqual('https://public');
      expect(AppConfig.selectActiveURL(true, '', 'http://lan', '', false)).assertEqual('http://lan');
      expect(AppConfig.selectActiveURL(true, '', '', '', false)).assertEqual('');
    });

    it('rebuilds client when active URL or key changes', 0, (): void => {
      expect(AppConfig.clientNeedsRebuild('a', 'a', 'k', 'k')).assertFalse();
      expect(AppConfig.clientNeedsRebuild('a', 'b', 'k', 'k')).assertTrue();
      expect(AppConfig.clientNeedsRebuild('a', 'a', 'k', 'k2')).assertTrue();
      const config: AppConfig = AppConfig.getInstance();
      config.activeURL = 'http://first';
      const first: APIClient = config.getClient();
      expect(config.getClient() === first).assertTrue();
      config.activeURL = 'http://second';
      expect(config.getClient() === first).assertFalse();
      config.activeURL = '';
    });
  });
}
