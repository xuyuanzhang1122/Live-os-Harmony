import { ThumbnailCache } from '../cache/ThumbnailCache';
import { AppConfig } from '../config/AppConfig';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { VideoFileInfo, VideoFileInfoInit, VideoRoomInfo, VideoRoomInfoInit } from '../model/VideoLibrary';
import { APIClient } from '../net/APIClient';
import { ApiCache } from '../net/ApiCache';

const GRID_HORIZONTAL_PADDING: number = 16;
const GRID_GAP: number = 16;
const GRID_MIN_COLUMN_WIDTH: number = 160;
const GRID_MAX_COLUMN_WIDTH: number = 300;
const GRID_TARGET_COLUMN_WIDTH: number = 180;
export const MINIMUM_LIBRARY_GRID_WIDTH: number = 352;
export const MAXIMUM_LIBRARY_GRID_WIDTH: number = 1580;

export function calculateLibraryColumns(width: number): number {
  const constrainedWidth: number = Math.max(MINIMUM_LIBRARY_GRID_WIDTH, width);
  const contentWidth: number = constrainedWidth - GRID_HORIZONTAL_PADDING;
  const target: number = Math.floor((contentWidth + GRID_GAP) / (GRID_TARGET_COLUMN_WIDTH + GRID_GAP));
  const minimumForMaxWidth: number = Math.max(1,
    Math.ceil((contentWidth + GRID_GAP) / (GRID_MAX_COLUMN_WIDTH + GRID_GAP)));
  const maximumForMinWidth: number = Math.max(1,
    Math.floor((contentWidth + GRID_GAP) / (GRID_MIN_COLUMN_WIDTH + GRID_GAP)));
  if (maximumForMinWidth < 2) {
    return 2;
  }
  return Math.max(2, Math.min(5, Math.min(maximumForMinWidth, Math.max(minimumForMaxWidth, target))));
}

export function historyProgressPercent(positionSeconds: number, durationSeconds: number): number {
  if (!Number.isFinite(positionSeconds) || !Number.isFinite(durationSeconds) ||
    positionSeconds <= 5 || durationSeconds <= 0) {
    return -1;
  }
  const ratio: number = Math.max(0, Math.min(1, positionSeconds / durationSeconds));
  return Math.round(ratio * 100);
}

function errorMessage(error: Object): string {
  return error instanceof Error ? error.message : `${error}`;
}

@ObservedV2
export class VideoLibraryViewModel {
  @Trace rooms: VideoRoomInfo[] = [];
  @Trace isLoading: boolean = false;
  @Trace isRefreshing: boolean = false;
  @Trace errorText: string = '';
  @Trace thumbnailGeneration: number = 0;

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
      const rooms: VideoRoomInfo[] = await this.client.getVideoLibrary();
      this.rooms = rooms;
      this.cache.set(key, JSON.stringify(rooms));
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
      ThumbnailCache.getInstance().invalidateSession();
      this.thumbnailGeneration += 1;
      await config.refreshNetworkStatus();
      this.client = config.getClient();
      await this.load(true);
    } finally {
      this.isRefreshing = false;
    }
  }

  thumbnailURL(room: VideoRoomInfo): string {
    if (room.latest_video === null || room.latest_video.length === 0) {
      return '';
    }
    const relativePath: string = room.latest_video.indexOf('/') >= 0 ? room.latest_video :
      `${room.folder_path}/${room.latest_video}`;
    const file: VideoFileInfo = new VideoFileInfo({
      name: room.latest_video,
      rel_path: relativePath,
      size: 0,
      mod_time: room.latest_video_at,
      file_url: null,
      thumbnail_url: null,
      hls_url: null,
      recording: room.recording,
      playback_status: room.recording ? 'recording' : null
    });
    return APIClient.buildThumbnailUrl(this.client.baseURL, this.client.apiKey, file);
  }

  private cacheKey(): string {
    return `${this.client.baseURL}/api/video-library`;
  }

  private restoreCache(key: string): void {
    const cached: string | null = this.cache.get(key);
    if (cached === null) {
      return;
    }
    try {
      const values: VideoRoomInfoInit[] = JSON.parse(cached) as VideoRoomInfoInit[];
      this.rooms = values.map((value: VideoRoomInfoInit): VideoRoomInfo => new VideoRoomInfo(value));
    } catch (_) {
    }
  }
}

@ObservedV2
export class VideoListViewModel {
  @Trace files: VideoFileInfo[] = [];
  @Trace historyByPath: Map<string, WatchHistoryEntry> = new Map<string, WatchHistoryEntry>();
  @Trace selectedPaths: string[] = [];
  @Trace isLoading: boolean = false;
  @Trace isRefreshing: boolean = false;
  @Trace errorText: string = '';
  @Trace thumbnailGeneration: number = 0;

  readonly folderPath: string;
  readonly hostName: string;
  private client: APIClient;
  private readonly cache: ApiCache;
  private loading: boolean = false;

  constructor(client: APIClient, folderPath: string, hostName: string,
    cache: ApiCache = ApiCache.getInstance()) {
    this.client = client;
    this.folderPath = folderPath;
    this.hostName = hostName;
    this.cache = cache;
  }

  updateClient(client: APIClient): void {
    this.client = client;
  }

  async load(skipCache: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    const key: string = this.cacheKey();
    if (!skipCache && this.files.length === 0) {
      this.restoreCache(key);
    }
    this.isLoading = this.files.length === 0;
    this.errorText = '';
    try {
      const files: VideoFileInfo[] = await this.client.getVideoFiles(this.folderPath);
      this.files = files;
      this.cache.set(key, JSON.stringify(files));
      try {
        const entries: WatchHistoryEntry[] = await this.client.getHistoryAll();
        const history: Map<string, WatchHistoryEntry> = new Map<string, WatchHistoryEntry>();
        entries.forEach((entry: WatchHistoryEntry): void => {
          history.set(entry.video_path, entry);
        });
        this.historyByPath = history;
      } catch (_) {
        this.historyByPath = new Map<string, WatchHistoryEntry>();
      }
    } catch (error) {
      if (this.files.length === 0) {
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
      ThumbnailCache.getInstance().invalidateSession();
      this.thumbnailGeneration += 1;
      await config.refreshNetworkStatus();
      this.client = config.getClient();
      await this.load(true);
    } finally {
      this.isRefreshing = false;
    }
  }

  historyForPath(path: string): WatchHistoryEntry | null {
    const match: WatchHistoryEntry | undefined = this.historyByPath.get(path);
    return match ?? null;
  }

  progressPercent(path: string): number {
    const entry: WatchHistoryEntry | null = this.historyForPath(path);
    return entry === null ? -1 : historyProgressPercent(entry.position_seconds, entry.duration_seconds);
  }

  isSelected(path: string): boolean {
    return this.selectedPaths.indexOf(path) >= 0;
  }

  toggleSelection(path: string): void {
    if (this.isSelected(path)) {
      this.selectedPaths = this.selectedPaths.filter((value: string): boolean => value !== path);
    } else {
      this.selectedPaths = [...this.selectedPaths, path];
    }
  }

  clearSelection(): void {
    this.selectedPaths = [];
  }

  async deleteFile(file: VideoFileInfo): Promise<void> {
    await this.client.deleteFile(file.rel_path);
    this.files = this.files.filter((value: VideoFileInfo): boolean => value.rel_path !== file.rel_path);
    this.selectedPaths = this.selectedPaths.filter((value: string): boolean => value !== file.rel_path);
    this.cache.set(this.cacheKey(), JSON.stringify(this.files));
  }

  async deleteSelected(): Promise<number> {
    const paths: string[] = [...this.selectedPaths];
    if (paths.length === 0) {
      return 0;
    }
    await this.client.batchDeleteFiles(paths);
    this.files = this.files.filter((file: VideoFileInfo): boolean => paths.indexOf(file.rel_path) < 0);
    this.selectedPaths = [];
    this.cache.set(this.cacheKey(), JSON.stringify(this.files));
    return paths.length;
  }

  thumbnailURL(file: VideoFileInfo): string {
    return APIClient.buildThumbnailUrl(this.client.baseURL, this.client.apiKey, file);
  }

  private cacheKey(): string {
    return `${this.client.baseURL}/api/video-files/${APIClient.encodePathSegments(this.folderPath)}`;
  }

  private restoreCache(key: string): void {
    const cached: string | null = this.cache.get(key);
    if (cached === null) {
      return;
    }
    try {
      const values: VideoFileInfoInit[] = JSON.parse(cached) as VideoFileInfoInit[];
      this.files = values.map((value: VideoFileInfoInit): VideoFileInfo => new VideoFileInfo(value));
    } catch (_) {
    }
  }
}
