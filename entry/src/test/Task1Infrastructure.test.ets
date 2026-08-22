import { describe, expect, it } from '@ohos/hypium';
import { Formats } from '../main/ets/common/Formats';
import { sha256Hex } from '../main/ets/common/Sha256';
import { AppConfig } from '../main/ets/config/AppConfig';
import { APIClient } from '../main/ets/net/APIClient';
import { ApiCache, CacheClock } from '../main/ets/net/ApiCache';
import { WatchHistoryEntry } from '../main/ets/model/HistoryEntry';
import {
  BackupDeviceConfig,
  BackupPackage,
  ServerConfigInput,
  ServerLiveRoomInput,
  ServerRpcConfigInput
} from '../main/ets/model/BackupModels';
import { VideoFileInfo, VideoFileInfoInit, VideoRoomInfo, VideoRoomInfoInit } from '../main/ets/model/VideoLibrary';
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
import {
  calculateLibraryColumns,
  historyProgressPercent,
  VideoLibraryViewModel,
  VideoListViewModel
} from '../main/ets/viewmodel/VideoLibraryViewModel';

class MutableClock implements CacheClock {
  nowValue: number;

  constructor(nowValue: number) {
    this.nowValue = nowValue;
  }

  now(): number {
    return this.nowValue;
  }
}

class MemoryApiCache extends ApiCache {
  private values: Map<string, string> = new Map<string, string>();

  constructor() {
    super('');
  }

  get(url: string): string | null {
    return this.values.get(url) ?? null;
  }

  set(url: string, body: string): void {
    this.values.set(url, body);
  }
}

class FakeVideoClient extends APIClient {
  rooms: VideoRoomInfo[] = [];
  files: VideoFileInfo[] = [];
  history: WatchHistoryEntry[] = [];
  libraryFails: boolean = false;
  deletedPath: string = '';
  batchPaths: string[] = [];

  constructor() {
    super('http://server');
  }

  async getVideoLibrary(): Promise<VideoRoomInfo[]> {
    if (this.libraryFails) {
      throw new Error('offline');
    }
    return this.rooms;
  }

  async getVideoFiles(_folderPath: string): Promise<VideoFileInfo[]> {
    return this.files;
  }

  async getHistoryAll(): Promise<WatchHistoryEntry[]> {
    return this.history;
  }

  async deleteFile(relPath: string): Promise<void> {
    this.deletedPath = relPath;
  }

  async batchDeleteFiles(paths: string[]): Promise<void> {
    this.batchPaths = paths;
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

    it('parses server date-time values with a space separator', 0, (): void => {
      const now: number = Date.parse('2026-05-04T12:00:00');
      expect(Formats.formatRelativeTime('2026-05-04 11:55:00', now)).assertEqual('5 分钟前');
    });
  });

  describe('Task2 video model normalization', (): void => {
    it('normalizes omitted video file fields instead of leaking undefined', 0, (): void => {
      const sparse: VideoFileInfoInit = JSON.parse('{"name":"a.mp4","rel_path":"房间/a.mp4","size":1,' +
        '"mod_time":"2026-05-04 12:00:00"}') as VideoFileInfoInit;
      const file: VideoFileInfo = new VideoFileInfo(sparse);
      expect(file.file_url).assertNull();
      expect(file.thumbnail_url).assertNull();
      expect(file.hls_url).assertNull();
      expect(file.recording).assertNull();
      expect(file.playback_status).assertNull();
    });

    it('normalizes omitted room fields to safe defaults', 0, (): void => {
      const sparse: VideoRoomInfoInit = JSON.parse('{"host_name":"主播","platform":"抖音",' +
        '"folder_path":"抖音/主播","video_count":0,"total_size":0,"latest_video_at":0}') as VideoRoomInfoInit;
      const room: VideoRoomInfo = new VideoRoomInfo(sparse);
      expect(room.latest_video).assertNull();
      expect(room.recording).assertFalse();
      expect(room.url).assertNull();
    });
  });

  describe('Task2 video library presentation rules', (): void => {
    it('keeps phone layouts at two columns and tablet layouts at four or more', 0, (): void => {
      expect(calculateLibraryColumns(320)).assertEqual(2);
      expect(calculateLibraryColumns(360)).assertEqual(2);
      expect(calculateLibraryColumns(819)).assertEqual(4);
      expect(calculateLibraryColumns(1200) >= 4).assertTrue();
    });

    it('derives watched percent with iOS resume boundaries and clamps', 0, (): void => {
      expect(historyProgressPercent(5, 100)).assertEqual(-1);
      expect(historyProgressPercent(5.01, 100)).assertEqual(5);
      expect(historyProgressPercent(95, 100)).assertEqual(95);
      expect(historyProgressPercent(200, 100)).assertEqual(100);
      expect(historyProgressPercent(10, 0)).assertEqual(-1);
    });

    it('renders cached rooms when the following network refresh fails', 0, async (): Promise<void> => {
      const cache: MemoryApiCache = new MemoryApiCache();
      const client: FakeVideoClient = new FakeVideoClient();
      client.libraryFails = true;
      cache.set('http://server/api/video-library', JSON.stringify([new VideoRoomInfo({
        host_name: '缓存主播',
        platform: '抖音',
        folder_path: '抖音/缓存主播',
        video_count: 1,
        total_size: 1024,
        latest_video_at: 0,
        latest_video: 'a.mp4',
        recording: false,
        url: null
      })]));
      const viewModel: VideoLibraryViewModel = new VideoLibraryViewModel(client, cache);
      await viewModel.load();
      expect(viewModel.rooms.length).assertEqual(1);
      expect(viewModel.rooms[0].host_name).assertEqual('缓存主播');
      expect(viewModel.errorText).assertEqual('');
    });

    it('indexes history and keeps delete state consistent with API calls', 0, async (): Promise<void> => {
      const cache: MemoryApiCache = new MemoryApiCache();
      const client: FakeVideoClient = new FakeVideoClient();
      const first: VideoFileInfo = videoFile('a.mp4', '房间/a.mp4', null, null, null);
      const second: VideoFileInfo = videoFile('b.mp4', '房间/b.mp4', null, null, null);
      client.files = [first, second];
      client.history = [{
        id: 1,
        api_key_user_id: 'user',
        video_path: first.rel_path,
        video_name: first.name,
        position_seconds: 50,
        duration_seconds: 100,
        updated_at: '2026-05-04 12:00:00'
      }];
      const viewModel: VideoListViewModel = new VideoListViewModel(client, '房间', '主播', cache);
      await viewModel.load(true);
      expect(viewModel.historyByPath.size).assertEqual(1);
      expect(viewModel.progressPercent(first.rel_path)).assertEqual(50);
      await viewModel.deleteFile(first);
      expect(client.deletedPath).assertEqual(first.rel_path);
      expect(viewModel.files.length).assertEqual(1);
      viewModel.toggleSelection(second.rel_path);
      expect(await viewModel.deleteSelected()).assertEqual(1);
      expect(client.batchPaths[0]).assertEqual(second.rel_path);
      expect(viewModel.files.length).assertEqual(0);
      expect(viewModel.selectedPaths.length).assertEqual(0);
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
