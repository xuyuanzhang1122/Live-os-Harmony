import { Formats } from '../common/Formats';
import { AppConfig } from '../config/AppConfig';
import { VideoRoomInfo } from '../model/VideoLibrary';
import {
  calculateLibraryColumns,
  MINIMUM_LIBRARY_GRID_WIDTH,
  VideoLibraryViewModel
} from '../viewmodel/VideoLibraryViewModel';
import { CachedThumbnail } from './components/CachedThumbnail';

export class VideoListRouteParams {
  folderPath: string;
  hostName: string;

  constructor(folderPath: string, hostName: string) {
    this.folderPath = folderPath;
    this.hostName = hostName;
  }
}

@ComponentV2
export struct VideoLibraryPage {
  @Require @Param stack: NavPathStack;
  @Require @Param active: boolean;
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private viewModel: VideoLibraryViewModel =
    new VideoLibraryViewModel(AppConfig.getInstance().getClient());
  @Local private columns: number = 2;
  @Local private availableWidth: number = 360;
  private pollingTimer: number = -1;

  aboutToAppear(): void {
    if (this.active) {
      this.activate();
    }
  }

  @Monitor('active')
  onActiveChanged(_monitor: IMonitor): void {
    if (this.active) {
      this.activate();
    } else {
      this.deactivate();
    }
  }

  aboutToDisappear(): void {
    this.deactivate();
  }

  private activate(): void {
    this.viewModel.updateClient(this.config.getClient());
    this.viewModel.load().catch((): void => {});
    this.startPolling();
  }

  private deactivate(): void {
    this.stopPolling();
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollingTimer = setInterval((): void => {
      this.viewModel.updateClient(this.config.getClient());
      this.viewModel.load(true).catch((): void => {});
    }, 10000);
  }

  private stopPolling(): void {
    if (this.pollingTimer >= 0) {
      clearInterval(this.pollingTimer);
      this.pollingTimer = -1;
    }
  }

  private openRoom(room: VideoRoomInfo): void {
    this.stack.pushPath({
      name: 'VideoListPage',
      param: new VideoListRouteParams(room.folder_path, room.host_name)
    });
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.video'))
        .fontSize(46)
        .fontColor([$r('sys.color.font_secondary')])
      Text('暂无录播')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
      Text('去「直播间」页签添加主播，开播后自动录制')
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
      Text('无法加载')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
      Text(this.viewModel.errorText)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button('重试')
        .onClick((): void => {
          this.viewModel.load(true).catch((): void => {});
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private roomCard(room: VideoRoomInfo) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        CachedThumbnail({
          url: this.viewModel.thumbnailURL(room),
          emptyText: room.video_count === 0 ? '暂无录播' : '',
          generation: this.viewModel.thumbnailGeneration
        })
        if (room.recording) {
          Row({ space: 4 }) {
            Circle()
              .width(6)
              .height(6)
              .fill(Color.White)
            Text('直播中')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .margin(8)
          .backgroundColor('#E84040')
          .borderRadius(12)
        }
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .clip(true)
      .borderRadius({ topLeft: 12, topRight: 12 })

      Column({ space: 6 }) {
        Text(room.host_name.length > 0 ? room.host_name : '未命名主播')
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${room.video_count} 个视频 · 已用 ${Formats.formatBytes(room.total_size)}`)
          .width('100%')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
    }
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(12)
    .shadow({ radius: 8, color: '#18000000', offsetY: 3 })
    .onClick((): void => this.openRoom(room))
  }

  build() {
    Refresh({ refreshing: this.viewModel.isRefreshing }) {
      if (this.viewModel.isLoading && this.viewModel.rooms.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36)
          Text('加载中…').fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.viewModel.errorText.length > 0 && this.viewModel.rooms.length === 0) {
        this.errorState()
      } else if (this.viewModel.rooms.length === 0) {
        this.emptyState()
      } else {
        Scroll() {
          Grid() {
            ForEach(this.viewModel.rooms, (room: VideoRoomInfo): void => {
              GridItem() {
                this.roomCard(room)
              }
            }, (room: VideoRoomInfo): string => room.folder_path)
          }
          .columnsTemplate(`repeat(${this.columns}, 1fr)`)
          .columnsGap(16)
          .rowsGap(16)
          .padding({ left: 8, right: 8, top: 12, bottom: 20 })
          .width(Math.max(this.availableWidth, MINIMUM_LIBRARY_GRID_WIDTH))
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.availableWidth = Number(newArea.width);
          this.columns = calculateLibraryColumns(this.availableWidth);
        })
      }
    }
    .width('100%')
    .height('100%')
    .onRefreshing((): void => {
      this.viewModel.manualRefresh(this.config).catch((): void => {});
    })
  }
}
