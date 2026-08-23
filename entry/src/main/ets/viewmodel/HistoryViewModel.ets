import { ThumbnailCache } from '../cache/ThumbnailCache';
import { AppConfig } from '../config/AppConfig';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { VideoFileInfo } from '../model/VideoLibrary';
import { APIClient } from '../net/APIClient';

function errorMessage(error: Object): string {
  return error instanceof Error ? error.message : `${error}`;
}

export function historyProgressPercent(positionSeconds: number, durationSeconds: number): number {
  if (!Number.isFinite(positionSeconds) || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, positionSeconds / durationSeconds * 100));
}

export function historyHostName(videoPath: string): string {
  const segments: string[] = videoPath.split('/').filter((value: string): boolean => value.length > 0);
  return segments.length > 0 ? segments[0] : '未知主播';
}

export function historyVideoFile(entry: WatchHistoryEntry): VideoFileInfo {
  const pathSegments: string[] = entry.video_path.split('/');
  const fallbackName: string = pathSegments.length > 0 ? pathSegments[pathSegments.length - 1] : '未知视频';
  return new VideoFileInfo({
    name: entry.video_name.length > 0 ? entry.video_name : fallbackName,
    rel_path: entry.video_path,
    size: 0,
    mod_time: entry.updated_at,
    file_url: null,
    thumbnail_url: null,
    hls_url: null,
    recording: null,
    playback_status: null
  });
}

@ObservedV2
export class HistoryViewModel {
  @Trace entries: WatchHistoryEntry[] = [];
  @Trace isLoading: boolean = false;
  @Trace isRefreshing: boolean = false;
  @Trace errorText: string = '';
  @Trace thumbnailGeneration: number = 0;

  private client: APIClient;
  private loading: boolean = false;

  constructor(client: APIClient) {
    this.client = client;
  }

  updateClient(client: APIClient): void {
    const identityChanged: boolean = this.client.baseURL !== client.baseURL || this.client.apiKey !== client.apiKey;
    this.client = client;
    if (identityChanged) {
      this.clear();
    }
  }

  clear(): void {
    this.entries = [];
    this.errorText = '';
    this.isLoading = false;
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.isLoading = this.entries.length === 0;
    this.errorText = '';
    try {
      this.entries = await this.client.getHistoryAll();
    } catch (error) {
      if (this.entries.length === 0) {
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
      await this.load();
    } finally {
      this.isRefreshing = false;
    }
  }

  thumbnailURL(entry: WatchHistoryEntry): string {
    return APIClient.buildThumbnailUrl(this.client.baseURL, this.client.apiKey, historyVideoFile(entry));
  }

  async deleteEntry(videoPath: string): Promise<void> {
    await this.client.deleteHistoryEntry(videoPath);
    this.entries = this.entries.filter((entry: WatchHistoryEntry): boolean => entry.video_path !== videoPath);
  }
}
