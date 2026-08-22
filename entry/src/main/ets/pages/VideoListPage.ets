import { Formats } from '../common/Formats';
import { AppConfig } from '../config/AppConfig';
import { VideoFileInfo } from '../model/VideoLibrary';
import { VideoListViewModel } from '../viewmodel/VideoLibraryViewModel';
import { CachedThumbnail } from './components/CachedThumbnail';

@ComponentV2
export struct VideoListPage {
  @Require @Param folderPath: string;
  @Require @Param hostName: string;
  @Event onVisibilityChange: (visible: boolean) => void = (_visible: boolean): void => {};
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private viewModel: VideoListViewModel =
    new VideoListViewModel(AppConfig.getInstance().getClient(), '', '');
  @Local private editMode: boolean = false;
  @Local private selectedFile: VideoFileInfo | null = null;
  private pollingTimer: number = -1;
  private initialized: boolean = false;

  aboutToAppear(): void {
    this.ensureViewModel();
  }

  private activate(): void {
    this.onVisibilityChange(true);
    this.ensureViewModel();
    this.viewModel.updateClient(this.config.getClient());
    this.viewModel.load().catch((): void => {});
    this.startPolling();
  }

  private deactivate(): void {
    this.onVisibilityChange(false);
    this.stopPolling();
  }

  aboutToDisappear(): void {
    this.deactivate();
  }

  private ensureViewModel(): void {
    if (this.initialized) {
      return;
    }
    this.viewModel = new VideoListViewModel(this.config.getClient(), this.folderPath, this.hostName);
    this.initialized = true;
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

  openPlayer(file: VideoFileInfo): void {
    this.selectedFile = file;
  }

  private closePlayer(): void {
    this.selectedFile = null;
  }

  private async confirmDelete(file: VideoFileInfo): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认删除',
        message: `确定删除“${file.name}”吗？此操作无法撤销。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#E84040' }]
      });
      if (result.index !== 1) {
        return;
      }
      await this.viewModel.deleteFile(file);
      this.showToast('已删除');
    } catch (error) {
      this.showToast(error instanceof Error ? error.message : `${error}`);
    }
  }

  private async confirmBatchDelete(): Promise<void> {
    const count: number = this.viewModel.selectedPaths.length;
    if (count === 0) {
      return;
    }
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认删除',
        message: `确定删除选中的 ${count} 个文件吗？此操作无法撤销。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#E84040' }]
      });
      if (result.index !== 1) {
        return;
      }
      const deleted: number = await this.viewModel.deleteSelected();
      this.editMode = false;
      this.showToast(`已删除 ${deleted} 个文件`);
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

  private toggleEditMode(): void {
    this.editMode = !this.editMode;
    if (!this.editMode) {
      this.viewModel.clearSelection();
    }
  }

  private fileDate(file: VideoFileInfo): string {
    if (typeof file.mod_time === 'string') {
      return file.mod_time.replace('T', ' ').substring(0, 16);
    }
    const millis: number = file.mod_time > 100000000000 ? file.mod_time : file.mod_time * 1000;
    const date: Date = new Date(millis);
    const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
    const day: string = date.getDate().toString().padStart(2, '0');
    const hour: string = date.getHours().toString().padStart(2, '0');
    const minute: string = date.getMinutes().toString().padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }

  @Builder
  private deleteSwipe(file: VideoFileInfo) {
    Button('删除')
      .height('100%')
      .fontColor(Color.White)
      .backgroundColor('#E84040')
      .onClick((): void => {
        this.confirmDelete(file).catch((): void => {});
      })
  }

  @Builder
  private fileRow(file: VideoFileInfo, progressPercent: number) {
    Row({ space: 12 }) {
      if (this.editMode) {
        Checkbox({ name: file.rel_path })
          .select(this.viewModel.isSelected(file.rel_path))
          .selectedColor($r('app.color.brand_color'))
          .onChange((value: boolean): void => {
            // select() 重放也会触发 onChange，仅处理与当前状态不一致的真实交互。
            if (value !== this.viewModel.isSelected(file.rel_path)) {
              this.viewModel.toggleSelection(file.rel_path);
            }
          })
      }

      CachedThumbnail({
        url: this.viewModel.thumbnailURL(file),
        generation: this.viewModel.thumbnailGeneration
      })
        .width(120)
        .height(67.5)
        .borderRadius(6)
        .clip(true)

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(file.name)
            .layoutWeight(1)
            .fontSize(15)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (file.recording === true || file.playback_status === 'recording') {
            Text('录制中')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#E84040')
              .borderRadius(10)
          }
        }
        .width('100%')

        Text(`${Formats.formatBytes(file.size)} · ${this.fileDate(file)}`)
          .width('100%')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (progressPercent >= 0) {
          Row({ space: 8 }) {
            Progress({
              value: progressPercent,
              total: 100,
              type: ProgressType.Linear
            })
              .layoutWeight(1)
              .height(4)
              .color($r('app.color.brand_color'))
              .backgroundColor('#22000000')
            Text(`已看 ${progressPercent}%`)
              .fontSize(11)
              .fontColor($r('app.color.brand_color'))
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 12, right: 12 })
    .onClick((): void => {
      if (this.editMode) {
        this.viewModel.toggleSelection(file.rel_path);
      } else {
        this.openPlayer(file);
      }
    })
  }

  @Builder
  private playerCover() {
    Column({ space: 16 }) {
      Text(this.selectedFile?.name ?? '')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
      Text('播放器将在 TASK-3 实现')
        .fontSize(15)
        .fontColor('#B8C0CC')
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Black)
    .onClick((): void => this.closePlayer())
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      Text('该主播还没有录像')
        .fontSize(18)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private errorState() {
    Column({ space: 12 }) {
      Text('无法加载').fontSize(20).fontWeight(FontWeight.Medium)
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

  build() {
    NavDestination() {
      Column() {
        Row() {
          Blank()
          if (this.viewModel.files.length > 0) {
            Button(this.editMode ? '完成' : '编辑')
              .type(ButtonType.Normal)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.brand_color'))
              .onClick((): void => this.toggleEditMode())
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })

        Refresh({ refreshing: this.viewModel.isRefreshing }) {
          if (this.viewModel.isLoading && this.viewModel.files.length === 0) {
            Column({ space: 10 }) {
              LoadingProgress().width(36).height(36)
              Text('加载中…').fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.viewModel.errorText.length > 0 && this.viewModel.files.length === 0) {
            this.errorState()
          } else if (this.viewModel.files.length === 0) {
            this.emptyState()
          } else {
            List() {
              ForEach(this.viewModel.files, (file: VideoFileInfo): void => {
                ListItem() {
                  Column() {
                    this.fileRow(file, this.viewModel.progressPercent(file.rel_path))
                    Divider().margin({ left: this.editMode ? 164 : 144 })
                  }
                }
                .swipeAction({
                  end: (): void => {
                    this.deleteSwipe(file);
                  }
                })
              }, (file: VideoFileInfo): string => file.rel_path)
            }
            .width('100%')
            .height('100%')
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing((): void => {
          this.viewModel.manualRefresh(this.config).catch((): void => {});
        })

        if (this.editMode) {
          Button(`删除(${this.viewModel.selectedPaths.length})`)
            .width('calc(100% - 32vp)')
            .height(44)
            .margin({ top: 8, bottom: 12 })
            .enabled(this.viewModel.selectedPaths.length > 0)
            .fontColor(Color.White)
            .backgroundColor(this.viewModel.selectedPaths.length > 0 ? '#E84040' : '#909399')
            .onClick((): void => {
              this.confirmBatchDelete().catch((): void => {});
            })
        }
      }
      .width('100%')
      .height('100%')
      .bindContentCover(this.selectedFile !== null, this.playerCover)
    }
    .title(this.hostName)
    .onShown((_reason: VisibilityChangeReason): void => this.activate())
    .onHidden((_reason: VisibilityChangeReason): void => this.deactivate())
  }
}
