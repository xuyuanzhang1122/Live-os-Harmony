import { Formats } from '../common/Formats';
import { AppConfig } from '../config/AppConfig';
import { WatchHistoryEntry } from '../model/HistoryEntry';
import { VideoFileInfo } from '../model/VideoLibrary';
import {
  HistoryViewModel,
  historyHostName,
  historyProgressPercent,
  historyVideoFile
} from '../viewmodel/HistoryViewModel';
import { CachedThumbnail } from './components/CachedThumbnail';

@ComponentV2
export struct HistoryPage {
  @Require @Param active: boolean;
  @Event onPlayFile: (file: VideoFileInfo) => void = (_file: VideoFileInfo): void => {};
  @Event onOpenSettings: () => void = (): void => {};
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private viewModel: HistoryViewModel =
    new HistoryViewModel(AppConfig.getInstance().getClient());

  aboutToAppear(): void {
    if (this.active) {
      this.activate();
    }
  }

  @Monitor('active')
  onActiveChanged(_monitor: IMonitor): void {
    if (this.active) {
      this.activate();
    }
  }

  private activate(): void {
    if (!this.config.apiKeyBound) {
      this.viewModel.clear();
      return;
    }
    this.viewModel.updateClient(this.config.getClient());
    this.viewModel.load().catch((): void => {});
  }

  private async manualRefresh(): Promise<void> {
    if (!this.config.apiKeyBound) {
      await this.config.refreshNetworkStatus();
      this.viewModel.clear();
      return;
    }
    await this.viewModel.manualRefresh(this.config);
  }

  private openPlayer(entry: WatchHistoryEntry): void {
    this.onPlayFile(historyVideoFile(entry));
  }

  private async confirmDelete(entry: WatchHistoryEntry): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除这条记录',
        message: `确定删除“${entry.video_name}”的观看记录吗？`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#E84040' }]
      });
      if (result.index !== 1) {
        return;
      }
      await this.viewModel.deleteEntry(entry.video_path);
      this.showToast('已删除观看记录');
    } catch (error) {
      this.showToast(error instanceof Error ? error.message : `${error}`);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  @Builder
  private historyMenu(entry: WatchHistoryEntry) {
    Menu() {
      MenuItem({ content: '删除这条记录' })
        .onClick((): void => {
          this.confirmDelete(entry).catch((): void => {});
        })
    }
  }

  @Builder
  private unboundState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.key_fill'))
        .fontSize(46)
        .fontColor([$r('sys.color.font_secondary')])
      Text('未绑定 API Key')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
      Text('绑定后可同步各设备的观看历史与进度')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button('去设置')
        .onClick((): void => this.onOpenSettings())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.clock_fill'))
        .fontSize(46)
        .fontColor([$r('sys.color.font_secondary')])
      Text('暂无观看记录')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
      Text('看过的视频会出现在这里，进度多端同步')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private errorState() {
    Column({ space: 12 }) {
      Text('无法加载观看历史')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
      Text(this.viewModel.errorText)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button('重试')
        .onClick((): void => this.activate())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private historyCard(entry: WatchHistoryEntry) {
    Row({ space: 12 }) {
      CachedThumbnail({
        url: this.viewModel.thumbnailURL(entry),
        generation: this.viewModel.thumbnailGeneration
      })
        .width(140)
        .height(78.75)
        .borderRadius(10)
        .clip(true)

      Column({ space: 6 }) {
        Text(entry.video_name.length > 0 ? entry.video_name : '未知视频')
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(historyHostName(entry.video_path))
            .layoutWeight(1)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(Formats.formatRelativeTime(entry.updated_at))
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        Progress({
          value: historyProgressPercent(entry.position_seconds, entry.duration_seconds),
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(4)
          .color($r('app.color.brand_color'))
          .backgroundColor('#22000000')
      }
      .layoutWeight(1)
      .height(78.75)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(14)
    .shadow({ radius: 8, color: '#16000000', offsetY: 3 })
    .bindMenu(this.historyMenu(entry))
    .onClick((): void => this.openPlayer(entry))
  }

  build() {
    Refresh({ refreshing: this.viewModel.isRefreshing }) {
      if (!this.config.apiKeyBound) {
        this.unboundState()
      } else if (this.viewModel.isLoading && this.viewModel.entries.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36)
          Text('加载中…').fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.viewModel.errorText.length > 0 && this.viewModel.entries.length === 0) {
        this.errorState()
      } else if (this.viewModel.entries.length === 0) {
        this.emptyState()
      } else {
        List({ space: 12 }) {
          ForEach(this.viewModel.entries, (entry: WatchHistoryEntry): void => {
            ListItem() {
              this.historyCard(entry)
            }
          }, (entry: WatchHistoryEntry): string => entry.video_path)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 20 })
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .onRefreshing((): void => {
      this.manualRefresh().catch((): void => {});
    })
  }
}
