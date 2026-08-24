import { ConfirmDialog } from '@kit.ArkUI';
import { AppButtonRole } from '../common/Theme';
import { AppConfig } from '../config/AppConfig';
import { LiveInfo } from '../model/LiveRoom';
import { BackupExportSheet } from './components/BackupExportSheet';
import { AppActionButton } from './components/AppActionButton';
import {
  AddRoomFailure,
  AddRoomsResult,
  RoomListViewModel,
  RoomStatusKind,
  roomRowKey,
  roomStatusKind
} from '../viewmodel/RoomListViewModel';

@ComponentV2
export struct RoomListPage {
  @Require @Param active: boolean;
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private viewModel: RoomListViewModel =
    new RoomListViewModel(AppConfig.getInstance().getClient());
  @Local private showAddSheet: boolean = false;
  @Local private showBackupSheet: boolean = false;
  @Local private addInput: string = '';
  @Local private isAdding: boolean = false;
  @Local private addErrorText: string = '';
  @Local private deleteCandidate: LiveInfo | null = null;
  @Local private deleteFiles: boolean = false;
  private pollingTimer: number = -1;
  private readonly deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: '确认删除',
      content: '确定删除这个直播间吗？此操作无法撤销。',
      checkTips: '同时删除该主播的全部录像文件',
      isChecked: this.deleteFiles,
      onCheckedChange: (checked: boolean): void => {
        this.deleteFiles = checked;
      },
      primaryButton: {
        value: '取消',
        action: (): void => {
          this.deleteCandidate = null;
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#E84040',
        action: (): void => {
          this.performDelete().catch((): void => {});
        }
      }
    }),
    autoCancel: true,
    cancel: (): void => {
      this.deleteCandidate = null;
    }
  });

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

  private openAddSheet(): void {
    this.addErrorText = '';
    this.showAddSheet = true;
  }

  private openBackupSheet(): void {
    this.showBackupSheet = true;
  }

  private closeAddSheet(): void {
    this.showAddSheet = false;
    this.addErrorText = '';
  }

  private refresh(): void {
    this.viewModel.updateClient(this.config.getClient());
    this.viewModel.load(true).catch((): void => {});
  }

  private toggleRoom(room: LiveInfo): void {
    this.viewModel.toggleListening(room.id).catch((error: Error): void => {
      this.showToast(error.message);
    });
  }

  private confirmDelete(room: LiveInfo): void {
    this.deleteCandidate = room;
    this.deleteFiles = false;
    this.deleteDialogController.open();
  }

  private async performDelete(): Promise<void> {
    const room: LiveInfo | null = this.deleteCandidate;
    this.deleteCandidate = null;
    if (room === null) {
      return;
    }
    try {
      await this.viewModel.deleteRoom(room.id, this.deleteFiles);
      this.showToast('已删除直播间');
    } catch (error) {
      this.showToast(error instanceof Error ? error.message : `${error}`);
    }
  }

  private failureText(failures: AddRoomFailure[]): string {
    return failures.map((failure: AddRoomFailure): string => failure.message === '添加未生效' ?
      `第 ${failure.lineNumber} 行添加未生效` :
      `第 ${failure.lineNumber} 行添加失败：${failure.message}`).join('\n');
  }

  private async showAddFailures(message: string): Promise<void> {
    try {
      await this.getUIContext().getPromptAction().showDialog({
        title: '部分链接未添加',
        message: message,
        buttons: [{ text: '好', color: '#1FDBC7' }]
      });
    } catch (_) {
    }
  }

  private async submitAdd(): Promise<void> {
    if (this.isAdding || this.addInput.trim().length === 0) {
      return;
    }
    this.isAdding = true;
    this.addErrorText = '';
    try {
      const result: AddRoomsResult = await this.viewModel.addRooms(this.addInput);
      const failures: string = this.failureText(result.failures);
      if (result.successCount > 0) {
        this.showToast(`成功添加 ${result.successCount} 个直播间`);
        this.addInput = '';
        this.showAddSheet = false;
        await this.viewModel.load(true);
        if (failures.length > 0) {
          await this.showAddFailures(failures);
        }
      } else {
        this.addErrorText = failures.length > 0 ? failures : '没有可添加的直播间';
      }
    } finally {
      this.isAdding = false;
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  private statusColor(kind: RoomStatusKind): string {
    if (kind === 'recording') {
      return '#F04444';
    }
    if (kind === 'listening') {
      return '#25C26E';
    }
    return '#7F8792';
  }

  private statusText(room: LiveInfo): string {
    if (room.initializing === true) {
      return '初始化中';
    }
    return room.listening === true ? '监听中' : '停止';
  }

  private roomSubtitle(room: LiveInfo): string {
    const roomName: string = room.room_name !== null && room.room_name.length > 0 ? room.room_name : '—';
    const platform: string = room.platform_cn_name !== null && room.platform_cn_name.length > 0 ?
      room.platform_cn_name : '未知平台';
    return `${roomName} · ${platform}`;
  }

  @Builder
  private pageToolbar() {
    Row({ space: 4 }) {
      Blank()
      Button() {
        SymbolGlyph($r('sys.symbol.archivebox'))
          .fontSize(22)
          .fontColor([$r('app.color.brand_color')])
      }
      .width(44)
      .height(44)
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .accessibilityText('导出备份')
      .onClick((): void => this.openBackupSheet())

      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(22)
          .fontColor([$r('app.color.brand_color')])
      }
      .width(44)
      .height(44)
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .accessibilityText('刷新')
      .onClick((): void => this.refresh())

      Button() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([$r('app.color.brand_color')])
      }
      .width(44)
      .height(44)
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .accessibilityText('添加直播间')
      .onClick((): void => this.openAddSheet())
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
  }

  @Builder
  private deleteSwipe(room: LiveInfo) {
    Button('删除')
      .height('100%')
      .fontColor(Color.White)
      .backgroundColor('#E84040')
      .onClick((): void => this.confirmDelete(room))
  }

  @Builder
  private roomRow(room: LiveInfo) {
    Row({ space: 14 }) {
      Stack() {
        if (room.recording === true || room.listening === true) {
          Circle()
            .width(22)
            .height(22)
            .fill(this.statusColor(roomStatusKind(room)))
            .opacity(0.18)
        }
        Circle()
          .width(12)
          .height(12)
          .fill(this.statusColor(roomStatusKind(room)))
      }
      .width(24)
      .height(24)

      Column({ space: 5 }) {
        Text(room.host_name !== null && room.host_name.length > 0 ? room.host_name : '未知主播')
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.roomSubtitle(room))
          .width('100%')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 7 }) {
          Text(this.statusText(room))
            .fontSize(12)
            .fontColor(room.initializing === true ? '#D58A19' : $r('sys.color.font_secondary'))
          if (room.listening === true && room.status === true) {
            Text('直播中')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#E84040')
              .borderRadius(10)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      AppActionButton({
        title: room.listening === true ? '停止' : '启动',
        role: room.listening === true ? AppButtonRole.Secondary : AppButtonRole.Primary,
        isEnabled: !this.viewModel.isRoomBusy(room.id),
        fill: false,
        compact: true,
        onPress: (): void => this.toggleRoom(room)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      Text('暂无直播间')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
      Text('点右上角添加按钮加入抖音直播间')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      AppActionButton({
        title: '添加直播间',
        role: AppButtonRole.Primary,
        fill: false,
        onPress: (): void => this.openAddSheet()
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
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
      AppActionButton({
        title: '重试',
        role: AppButtonRole.Secondary,
        fill: false,
        onPress: (): void => this.refresh()
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private addSheet() {
    Column({ space: 16 }) {
      Row() {
        AppActionButton({
          title: '取消',
          role: AppButtonRole.Plain,
          fill: false,
          compact: true,
          onPress: (): void => this.closeAddSheet()
        })
        Text('添加直播间')
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
        Blank().width(64)
      }
      .width('100%')

      TextArea({
        text: this.addInput,
        placeholder: '粘贴直播间链接或抖音分享文案，每行一个'
      })
        .width('100%')
        .height(150)
        .fontSize(15)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.addInput = value;
        })

      Text('支持抖音直播链接、短链或分享文案；无法解析的行不会阻塞其他行。')
        .width('100%')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))

      if (this.addErrorText.length > 0) {
        Text(this.addErrorText)
          .width('100%')
          .fontSize(13)
          .fontColor('#E84040')
      }

      AppActionButton({
        title: this.isAdding ? '添加中…' : '添加',
        role: AppButtonRole.Primary,
        isEnabled: !this.isAdding && this.addInput.trim().length > 0,
        loading: this.isAdding,
        onPress: (): void => {
          this.submitAdd().catch((): void => {});
        }
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private backupSheet() {
    BackupExportSheet({
      onClose: (): void => {
        this.showBackupSheet = false;
      }
    })
  }

  build() {
    Row() {
      Column() {
      this.pageToolbar()
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
          List() {
            ForEach(this.viewModel.rooms, (room: LiveInfo): void => {
              ListItem() {
                Column() {
                  this.roomRow(room)
                  Divider().margin({ left: 54 })
                }
              }
              .swipeAction({
                end: (): void => {
                  this.deleteSwipe(room);
                }
              })
            }, (room: LiveInfo): string => roomRowKey(room))
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
      // 同一节点链式绑定多个 bindSheet 时后者会覆盖前者，
      // 备份弹窗改挂在 Refresh 节点上，与添加弹窗（挂在 Column 上）分开宿主
      .bindSheet(this.showBackupSheet, this.backupSheet, {
        height: SheetSize.LARGE,
        showClose: false,
        onDisappear: (): void => {
          this.showBackupSheet = false;
        }
      })
    }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 960 })
      .bindSheet(this.showAddSheet, this.addSheet, {
        height: SheetSize.MEDIUM,
        showClose: false,
        onDisappear: (): void => {
          this.showAddSheet = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
