import { describe, expect, it } from '@ohos/hypium';
import { LiveInfo, AddLiveRequest } from '../main/ets/model/LiveRoom';
import { WatchHistoryEntry } from '../main/ets/model/HistoryEntry';
import { VideoFileInfo } from '../main/ets/model/VideoLibrary';
import { APIClient } from '../main/ets/net/APIClient';
import { ApiCache } from '../main/ets/net/ApiCache';
import {
  AddRoomsResult,
  RoomListViewModel,
  roomStatusKind
} from '../main/ets/viewmodel/RoomListViewModel';
import {
  HistoryViewModel,
  historyHostName,
  historyProgressPercent,
  historyVideoFile
} from '../main/ets/viewmodel/HistoryViewModel';

class MemoryTask5Cache extends ApiCache {
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

class FakeTask5Client extends APIClient {
  lives: LiveInfo[] = [];
  historyEntries: WatchHistoryEntry[] = [];
  getLivesError: string = '';
  startError: string = '';
  addError: string = '';
  addedLives: LiveInfo[] = [];
  addLivesCallCount: number = 0;
  addRequests: AddLiveRequest[] = [];
  resolveInputs: string[] = [];
  deletedLiveId: string = '';
  deletedLiveFiles: boolean = false;
  deletedHistoryPath: string = '';
  private startResolve: ((value: LiveInfo) => void) | null = null;
  private startPending: boolean = false;

  constructor() {
    super('http://server', 'a b');
  }

  async getLives(): Promise<LiveInfo[]> {
    if (this.getLivesError.length > 0) {
      throw new Error(this.getLivesError);
    }
    return this.lives;
  }

  async startListen(_id: string): Promise<LiveInfo> {
    if (this.startError.length > 0) {
      throw new Error(this.startError);
    }
    if (this.startPending) {
      return new Promise<LiveInfo>((resolve: (value: LiveInfo) => void): void => {
        this.startResolve = resolve;
      });
    }
    return this.lives[0];
  }

  async stopListen(_id: string): Promise<LiveInfo> {
    return this.lives[0];
  }

  async addLives(reqs: AddLiveRequest[]): Promise<LiveInfo[]> {
    this.addLivesCallCount += 1;
    this.addRequests = reqs;
    if (this.addError.length > 0) {
      throw new Error(this.addError);
    }
    return this.addedLives;
  }

  async resolveUrl(raw: string): Promise<string> {
    this.resolveInputs = [...this.resolveInputs, raw];
    if (raw === '坏分享文案') {
      throw new Error('无法解析');
    }
    return 'https://live.douyin.com/resolved';
  }

  async deleteLive(id: string, deleteFiles: boolean): Promise<void> {
    this.deletedLiveId = id;
    this.deletedLiveFiles = deleteFiles;
  }

  async getHistoryAll(): Promise<WatchHistoryEntry[]> {
    return this.historyEntries;
  }

  async deleteHistoryEntry(videoPath: string): Promise<void> {
    this.deletedHistoryPath = videoPath;
  }

  deferStart(): void {
    this.startPending = true;
  }

  completeStart(value: LiveInfo): void {
    const resolve: ((value: LiveInfo) => void) | null = this.startResolve;
    this.startPending = false;
    this.startResolve = null;
    if (resolve !== null) {
      resolve(value);
    }
  }
}

function liveInfo(id: string, listening: boolean, recording: boolean, status: boolean = false): LiveInfo {
  return {
    id: id,
    live_url: `https://live.douyin.com/${id}`,
    platform_cn_name: '抖音',
    host_name: `主播${id}`,
    room_name: `房间${id}`,
    status: status,
    listening: listening,
    recording: recording,
    recording_preparing: false,
    initializing: false,
    last_start_time: null,
    last_start_time_unix: null,
    audio_only: false,
    nick_name: null,
    last_error: null,
    available_streams: null,
    available_streams_updated_at: null
  };
}

function historyEntry(path: string = '抖音/主播甲/a.flv'): WatchHistoryEntry {
  return {
    id: 1,
    api_key_user_id: 'user',
    video_path: path,
    video_name: 'a.flv',
    position_seconds: 25,
    duration_seconds: 100,
    updated_at: '2026-05-04 12:00:00'
  };
}

export default function task5RoomHistoryTest(): void {
  describe('Task5 room list rules', (): void => {
    it('prioritizes recording over listening for the three status colors', 0, (): void => {
      expect(roomStatusKind(liveInfo('1', true, true))).assertEqual('recording');
      expect(roomStatusKind(liveInfo('2', true, false))).assertEqual('listening');
      expect(roomStatusKind(liveInfo('3', false, false))).assertEqual('stopped');
    });

    it('shows cached rooms when the following network refresh fails', 0, async (): Promise<void> => {
      const cache: MemoryTask5Cache = new MemoryTask5Cache();
      const client: FakeTask5Client = new FakeTask5Client();
      client.getLivesError = 'offline';
      cache.set('http://server/api/lives', JSON.stringify([liveInfo('cached', false, false)]));
      const viewModel: RoomListViewModel = new RoomListViewModel(client, cache);

      await viewModel.load();

      expect(viewModel.rooms.length).assertEqual(1);
      expect(viewModel.rooms[0].id).assertEqual('cached');
      expect(viewModel.errorText).assertEqual('');
    });

    it('optimistically starts listening then replaces the row with the server response', 0,
      async (): Promise<void> => {
        const client: FakeTask5Client = new FakeTask5Client();
        const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());
        viewModel.rooms = [liveInfo('1', false, false)];
        client.deferStart();

        const toggleTask: Promise<void> = viewModel.toggleListening('1');
        expect(viewModel.rooms[0].listening).assertTrue();

        const updated: LiveInfo = liveInfo('1', true, true, true);
        client.completeStart(updated);
        await toggleTask;
        expect(viewModel.rooms[0].recording).assertTrue();
        expect(viewModel.rooms[0].status).assertTrue();
      });

    it('rolls an optimistic listening change back when the request fails', 0, async (): Promise<void> => {
      const client: FakeTask5Client = new FakeTask5Client();
      const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());
      viewModel.rooms = [liveInfo('1', false, false)];
      client.startError = '启动失败';

      try {
        await viewModel.toggleListening('1');
      } catch (_) {
      }

      expect(viewModel.rooms[0].listening).assertFalse();
    });

    it('optimistically clears recording while stopping and then uses the stop response', 0,
      async (): Promise<void> => {
        const client: FakeTask5Client = new FakeTask5Client();
        const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());
        viewModel.rooms = [liveInfo('1', true, true, true)];
        client.lives = [liveInfo('1', false, false)];

        const toggleTask: Promise<void> = viewModel.toggleListening('1');
        expect(viewModel.rooms[0].listening).assertFalse();
        expect(viewModel.rooms[0].recording).assertFalse();

        await toggleTask;
        expect(viewModel.rooms[0].listening).assertFalse();
        expect(viewModel.rooms[0].status).assertFalse();
      });

    it('passes delete_files and removes only the confirmed room', 0, async (): Promise<void> => {
      const client: FakeTask5Client = new FakeTask5Client();
      const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());
      viewModel.rooms = [liveInfo('1', false, false), liveInfo('2', false, false)];

      await viewModel.deleteRoom('1', true);

      expect(client.deletedLiveId).assertEqual('1');
      expect(client.deletedLiveFiles).assertTrue();
      expect(viewModel.rooms.length).assertEqual(1);
      expect(viewModel.rooms[0].id).assertEqual('2');
    });

    it('resolves only non-Douyin lines and submits one listen=true array', 0, async (): Promise<void> => {
      const client: FakeTask5Client = new FakeTask5Client();
      client.addedLives = [
        liveInfo('direct', true, false),
        liveInfo('resolved', true, false),
        liveInfo('short', true, false)
      ];
      const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());

      const result: AddRoomsResult = await viewModel.addRooms('https://live.douyin.com/direct\n' +
        '一段分享文案\n坏分享文案\n\nhttps://v.douyin.com/short/');

      expect(client.resolveInputs.join(',')).assertEqual('一段分享文案,坏分享文案');
      expect(client.addLivesCallCount).assertEqual(1);
      expect(client.addRequests.length).assertEqual(3);
      expect(client.addRequests[0].url).assertEqual('https://live.douyin.com/direct');
      expect(client.addRequests[1].url).assertEqual('https://live.douyin.com/resolved');
      expect(client.addRequests[2].url).assertEqual('https://v.douyin.com/short/');
      expect(client.addRequests[0].listen).assertTrue();
      expect(result.successCount).assertEqual(3);
      expect(result.failures.length).assertEqual(1);
      expect(result.failures[0].lineNumber).assertEqual(3);
      expect(result.failures[0].message).assertEqual('无法解析');
    });

    it('reports every submitted line when the one batch request fails', 0, async (): Promise<void> => {
      const client: FakeTask5Client = new FakeTask5Client();
      client.addError = '服务器拒绝';
      const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());

      const result: AddRoomsResult = await viewModel.addRooms('https://live.douyin.com/1\n\n' +
        'https://live.douyin.com/3');

      expect(client.addLivesCallCount).assertEqual(1);
      expect(result.successCount).assertEqual(0);
      expect(result.failures.length).assertEqual(2);
      expect(result.failures[0].lineNumber).assertEqual(1);
      expect(result.failures[1].lineNumber).assertEqual(3);
      expect(result.failures[0].message).assertEqual('服务器拒绝');
    });

    it('identifies standard live URLs silently skipped by the server without blaming short links', 0,
      async (): Promise<void> => {
        const client: FakeTask5Client = new FakeTask5Client();
        client.addedLives = [liveInfo('kept', true, false)];
        const viewModel: RoomListViewModel = new RoomListViewModel(client, new MemoryTask5Cache());

        const result: AddRoomsResult = await viewModel.addRooms('https://live.douyin.com/kept\n' +
          'https://live.douyin.com/missing\nhttps://v.douyin.com/server-will-normalize/');

        expect(result.successCount).assertEqual(1);
        expect(result.failures.length).assertEqual(1);
        expect(result.failures[0].lineNumber).assertEqual(2);
        expect(result.failures[0].message).assertEqual('添加未生效');
      });
  });

  describe('Task5 history rules', (): void => {
    it('clamps progress to 0-100 and treats invalid duration as zero', 0, (): void => {
      expect(historyProgressPercent(25, 100)).assertEqual(25);
      expect(historyProgressPercent(200, 100)).assertEqual(100);
      expect(historyProgressPercent(-10, 100)).assertEqual(0);
      expect(historyProgressPercent(10, 0)).assertEqual(0);
      expect(historyProgressPercent(Number.NaN, 100)).assertEqual(0);
    });

    it('derives the displayed host and the exact player fallback file', 0, (): void => {
      const entry: WatchHistoryEntry = historyEntry();
      const file: VideoFileInfo = historyVideoFile(entry);

      expect(historyHostName(entry.video_path)).assertEqual('抖音');
      expect(file.name).assertEqual('a.flv');
      expect(file.rel_path).assertEqual('抖音/主播甲/a.flv');
      expect(file.size).assertEqual(0);
      expect(file.mod_time).assertEqual('2026-05-04 12:00:00');
      expect(file.file_url).assertNull();
      expect(file.thumbnail_url).assertNull();
      expect(file.hls_url).assertNull();
    });

    it('builds a signed-key thumbnail URL from video_path and deletes by path', 0, async (): Promise<void> => {
      const client: FakeTask5Client = new FakeTask5Client();
      const entry: WatchHistoryEntry = historyEntry();
      client.historyEntries = [entry];
      const viewModel: HistoryViewModel = new HistoryViewModel(client);
      await viewModel.load();

      expect(viewModel.thumbnailURL(entry))
        .assertEqual('http://server/api/thumbnail/%E6%8A%96%E9%9F%B3/%E4%B8%BB%E6%92%AD%E7%94%B2/a.flv?_key=a%20b');

      await viewModel.deleteEntry(entry.video_path);
      expect(client.deletedHistoryPath).assertEqual(entry.video_path);
      expect(viewModel.entries.length).assertEqual(0);
    });

    it('does not retain another API key user history when the client identity changes', 0,
      async (): Promise<void> => {
        const client: FakeTask5Client = new FakeTask5Client();
        client.historyEntries = [historyEntry()];
        const viewModel: HistoryViewModel = new HistoryViewModel(client);
        await viewModel.load();

        viewModel.updateClient(new APIClient('http://server', 'another-key'));

        expect(viewModel.entries.length).assertEqual(0);
      });
  });
}
