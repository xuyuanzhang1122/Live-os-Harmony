import { AppConfig } from '../config/AppConfig';
import { AddLiveRequest, LiveInfo } from '../model/LiveRoom';
import { APIClient } from '../net/APIClient';
import { ApiCache } from '../net/ApiCache';

export type RoomStatusKind = 'recording' | 'listening' | 'stopped';

export class AddRoomFailure {
  lineNumber: number;
  message: string;

  constructor(lineNumber: number, message: string) {
    this.lineNumber = lineNumber;
    this.message = message;
  }
}

export class AddRoomsResult {
  successCount: number;
  failures: AddRoomFailure[];

  constructor(successCount: number, failures: AddRoomFailure[]) {
    this.successCount = successCount;
    this.failures = failures;
  }
}

class SubmittedRoomLine {
  lineNumber: number;
  url: string;

  constructor(lineNumber: number, url: string) {
    this.lineNumber = lineNumber;
    this.url = url;
  }
}

export function roomStatusKind(room: LiveInfo): RoomStatusKind {
  if (room.recording === true) {
    return 'recording';
  }
  return room.listening === true ? 'listening' : 'stopped';
}

function errorMessage(error: Object): string {
  return error instanceof Error ? error.message : `${error}`;
}

function withListening(room: LiveInfo, listening: boolean): LiveInfo {
  return {
    id: room.id,
    live_url: room.live_url,
    platform_cn_name: room.platform_cn_name,
    host_name: room.host_name,
    room_name: room.room_name,
    status: listening ? room.status : false,
    listening: listening,
    recording: listening ? room.recording : false,
    recording_preparing: listening ? room.recording_preparing : false,
    initializing: listening ? room.initializing : false,
    last_start_time: room.last_start_time,
    last_start_time_unix: room.last_start_time_unix,
    audio_only: room.audio_only,
    nick_name: room.nick_name,
    last_error: room.last_error,
    available_streams: room.available_streams,
    available_streams_updated_at: room.available_streams_updated_at
  };
}

function isDouyinInput(value: string): boolean {
  return value.toLowerCase().indexOf('douyin.com') >= 0;
}

function normalizeLiveURL(value: string): string {
  let normalized: string = value.trim().toLowerCase();
  const queryIndex: number = normalized.indexOf('?');
  if (queryIndex >= 0) {
    normalized = normalized.substring(0, queryIndex);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

function isStandardLiveURL(value: string): boolean {
  const normalized: string = normalizeLiveURL(value);
  return normalized.startsWith('https://live.douyin.com/') || normalized.startsWith('http://live.douyin.com/');
}

@ObservedV2
export class RoomListViewModel {
  @Trace rooms: LiveInfo[] = [];
  @Trace isLoading: boolean = false;
  @Trace isRefreshing: boolean = false;
  @Trace errorText: string = '';
  @Trace busyRoomIds: string[] = [];

  private client: APIClient;
  private readonly cache: ApiCache;
  private loading: boolean = false;

  constructor(client: APIClient, cache: ApiCache = ApiCache.getInstance()) {
    this.client = client;
    this.cache = cache;
  }

  updateClient(client: APIClient): void {
    this.client = client;
  }

  isRoomBusy(id: string): boolean {
    return this.busyRoomIds.indexOf(id) >= 0;
  }

  async load(skipCache: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    const key: string = this.cacheKey();
    if (!skipCache && this.rooms.length === 0) {
      this.restoreCache(key);
    }
    this.isLoading = this.rooms.length === 0;
    this.errorText = '';
    try {
      const rooms: LiveInfo[] = await this.client.getLives();
      this.rooms = rooms;
      this.saveCache();
    } catch (error) {
      if (this.rooms.length === 0) {
        this.errorText = errorMessage(error);
      }
    } finally {
      this.isLoading = false;
      this.loading = false;
    }
  }

  async manualRefresh(config: AppConfig): Promise<void> {
    this.isRefreshing = true;
    try {
      await config.refreshNetworkStatus();
      this.client = config.getClient();
      await this.load(true);
    } finally {
      this.isRefreshing = false;
    }
  }

  async toggleListening(id: string): Promise<void> {
    if (this.isRoomBusy(id)) {
      return;
    }
    const index: number = this.rooms.findIndex((room: LiveInfo): boolean => room.id === id);
    if (index < 0) {
      return;
    }
    const original: LiveInfo = this.rooms[index];
    const shouldListen: boolean = original.listening !== true;
    this.busyRoomIds = [...this.busyRoomIds, id];
    this.replaceRoom(withListening(original, shouldListen));
    try {
      const updated: LiveInfo = shouldListen ? await this.client.startListen(id) : await this.client.stopListen(id);
      this.replaceRoom(updated);
      this.saveCache();
    } catch (error) {
      this.replaceRoom(original);
      this.saveCache();
      throw error instanceof Error ? error : new Error(`${error}`);
    } finally {
      this.busyRoomIds = this.busyRoomIds.filter((value: string): boolean => value !== id);
    }
  }

  async deleteRoom(id: string, deleteFiles: boolean): Promise<void> {
    await this.client.deleteLive(id, deleteFiles);
    this.rooms = this.rooms.filter((room: LiveInfo): boolean => room.id !== id);
    this.busyRoomIds = this.busyRoomIds.filter((value: string): boolean => value !== id);
    this.saveCache();
  }

  async addRooms(rawInput: string): Promise<AddRoomsResult> {
    const rawLines: string[] = rawInput.split(/\r?\n/);
    const submitted: SubmittedRoomLine[] = [];
    const failures: AddRoomFailure[] = [];
    for (let index: number = 0; index < rawLines.length; index += 1) {
      const value: string = rawLines[index].trim();
      if (value.length === 0) {
        continue;
      }
      if (isDouyinInput(value)) {
        submitted.push(new SubmittedRoomLine(index + 1, value));
        continue;
      }
      try {
        const resolved: string = await this.client.resolveUrl(value);
        submitted.push(new SubmittedRoomLine(index + 1, resolved));
      } catch (error) {
        failures.push(new AddRoomFailure(index + 1, errorMessage(error)));
      }
    }
    if (submitted.length === 0) {
      return new AddRoomsResult(0, failures);
    }
    const requests: AddLiveRequest[] = submitted.map((line: SubmittedRoomLine): AddLiveRequest =>
      new AddLiveRequest(line.url, true));
    try {
      const added: LiveInfo[] = await this.client.addLives(requests);
      if (added.length < submitted.length) {
        const returnedCounts: Map<string, number> = new Map<string, number>();
        added.forEach((room: LiveInfo): void => {
          if (room.live_url === null) {
            return;
          }
          const normalized: string = normalizeLiveURL(room.live_url);
          returnedCounts.set(normalized, (returnedCounts.get(normalized) ?? 0) + 1);
        });
        submitted.forEach((line: SubmittedRoomLine): void => {
          if (!isStandardLiveURL(line.url)) {
            return;
          }
          const normalized: string = normalizeLiveURL(line.url);
          const remaining: number = returnedCounts.get(normalized) ?? 0;
          if (remaining > 0) {
            returnedCounts.set(normalized, remaining - 1);
          } else {
            failures.push(new AddRoomFailure(line.lineNumber, '添加未生效'));
          }
        });
      }
      return new AddRoomsResult(added.length, failures);
    } catch (error) {
      const message: string = errorMessage(error);
      submitted.forEach((line: SubmittedRoomLine): void => {
        failures.push(new AddRoomFailure(line.lineNumber, message));
      });
      return new AddRoomsResult(0, failures);
    }
  }

  private replaceRoom(room: LiveInfo): void {
    this.rooms = this.rooms.map((value: LiveInfo): LiveInfo => value.id === room.id ? room : value);
  }

  private cacheKey(): string {
    return `${this.client.baseURL}/api/lives`;
  }

  private saveCache(): void {
    this.cache.set(this.cacheKey(), JSON.stringify(this.rooms));
  }

  private restoreCache(key: string): void {
    const cached: string | null = this.cache.get(key);
    if (cached === null) {
      return;
    }
    try {
      this.rooms = JSON.parse(cached) as LiveInfo[];
    } catch (_) {
    }
  }
}
