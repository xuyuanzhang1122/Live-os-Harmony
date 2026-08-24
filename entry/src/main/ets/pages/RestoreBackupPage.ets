import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { AppButtonRole } from '../common/Theme';
import { AppConfig } from '../config/AppConfig';
import { BackupPackage } from '../model/BackupModels';
import {
  BackupRestoreOutcome,
  BackupRestoreViewModel,
  formatBackupExportTime,
  hasBackupDeviceConfig
} from '../viewmodel/BackupViewModel';
import { AppActionButton } from './components/AppActionButton';
import { SettingsRowIcon } from './components/SettingsRowIcon';

@ComponentV2
export struct RestoreBackupPage {
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private viewModel: BackupRestoreViewModel =
    new BackupRestoreViewModel(AppConfig.getInstance().getClient());
  @Local private selectedMode: number = 0;
  @Local private restoreID: string = '';
  @Local private importedPackage: BackupPackage | null = null;
  @Local private selectingFile: boolean = false;
  @Local private errorText: string = '';
  private pathStack: NavPathStack | null = null;

  private async selectLocalBackup(): Promise<void> {
    if (this.selectingFile || this.viewModel.isRestoring) {
      return;
    }
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.showToast('无法打开文件选择窗口');
      return;
    }
    this.selectingFile = true;
    this.errorText = '';
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    let uris: string[];
    try {
      uris = await documentPicker.select({
        fileSuffixFilters: ['.json'],
        maxSelectNumber: 1
      });
    } catch (_) {
      this.selectingFile = false;
      return;
    }
    if (uris.length === 0) {
      this.selectingFile = false;
      return;
    }
    try {
      const json: string = await fs.readText(uris[0]);
      this.importedPackage = BackupPackage.fromJson(json);
      this.showToast('备份文件已读取，请确认后恢复');
    } catch (_) {
      this.importedPackage = null;
      this.errorText = '不是有效的备份文件';
      this.showToast('不是有效的备份文件');
    } finally {
      this.selectingFile = false;
    }
  }

  private async restoreFromID(): Promise<void> {
    const normalizedID: string = this.restoreID.trim();
    if (normalizedID.length === 0 || this.viewModel.isRestoring) {
      return;
    }
    this.errorText = '';
    this.viewModel.updateClient(this.config.getClient());
    try {
      const outcome: BackupRestoreOutcome = await this.viewModel.restoreById(normalizedID,
        (this.config.backupServerURL ?? '').trim().length > 0);
      await this.completeRestore(outcome);
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : `${error}`;
    }
  }

  private async restoreImportedPackage(): Promise<void> {
    const pkg: BackupPackage | null = this.importedPackage;
    if (pkg === null || this.viewModel.isRestoring) {
      return;
    }
    this.errorText = '';
    this.viewModel.updateClient(this.config.getClient());
    try {
      const outcome: BackupRestoreOutcome = await this.viewModel.restorePackage(pkg);
      await this.completeRestore(outcome);
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : `${error}`;
    }
  }

  private async completeRestore(outcome: BackupRestoreOutcome): Promise<void> {
    const pkg: BackupPackage | null = outcome.package;
    if (pkg !== null) {
      this.config.serverURL = pkg.iosConfig.serverURL ?? '';
      this.config.lanURL = pkg.iosConfig.lanURL ?? '';
      this.config.publicURL = pkg.iosConfig.publicURL ?? '';
      this.config.autoSwitchNetwork = pkg.iosConfig.autoSwitchNetwork ?? false;
    }
    await this.config.refreshNetworkStatus();
    this.showToast(outcome.message);
    const stack: NavPathStack | null = this.pathStack;
    if (stack !== null) {
      stack.pop();
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  private previewValue(value: string): string {
    const normalized: string = value ?? '';
    return normalized.length > 0 ? normalized : '—';
  }

  @Builder
  private modePicker() {
    Row() {
      Button('按备份 ID')
        .layoutWeight(1)
        .height(38)
        .type(ButtonType.Normal)
        .fontColor(this.selectedMode === 0 ? '#063D38' : $r('sys.color.font_secondary'))
        .backgroundColor(this.selectedMode === 0 ? $r('app.color.brand_color') : Color.Transparent)
        .borderRadius(9)
        .onClick((): void => {
          this.selectedMode = 0;
          this.errorText = '';
        })
      Button('本地文件')
        .layoutWeight(1)
        .height(38)
        .type(ButtonType.Normal)
        .fontColor(this.selectedMode === 1 ? '#063D38' : $r('sys.color.font_secondary'))
        .backgroundColor(this.selectedMode === 1 ? $r('app.color.brand_color') : Color.Transparent)
        .borderRadius(9)
        .onClick((): void => {
          this.selectedMode = 1;
          this.errorText = '';
        })
    }
    .width('100%')
    .padding(3)
    .backgroundColor($r('app.color.settings_input_background'))
    .border({ width: 1, color: $r('app.color.settings_card_border') })
    .borderRadius(13)
  }

  @Builder
  private previewRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Text(value)
        .layoutWeight(1)
        .fontSize(14)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  @Builder
  private backupPreview(pkg: BackupPackage) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SettingsRowIcon({
          symbol: $r('sys.symbol.doc_text_badge_checkmark'), color: '#14A89A', tileColor: '#1814A89A'
        })
        Text('备份预览').fontSize(16).fontWeight(FontWeight.Bold).layoutWeight(1)
      }
      .width('100%')
      this.previewRow('导出时间', formatBackupExportTime(pkg.exportedAt ?? ''))
      this.previewRow('端口绑定', this.previewValue(pkg.server.rpc_bind ?? ''))
      this.previewRow('输出目录', this.previewValue(pkg.server.out_put_path ?? ''))
      this.previewRow('直播间', `${(pkg.server.live_rooms ?? []).length} 个`)
      if (hasBackupDeviceConfig(pkg)) {
        Divider()
        Text('设备配置')
          .width('100%')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
        this.previewRow('网络模式', (pkg.iosConfig.autoSwitchNetwork ?? false) ? '智能切换' : '手动')
        this.previewRow('服务器地址', this.previewValue(pkg.iosConfig.serverURL ?? ''))
        if ((pkg.iosConfig.lanURL ?? '').length > 0) {
          this.previewRow('局域网地址', pkg.iosConfig.lanURL ?? '')
        }
        if ((pkg.iosConfig.publicURL ?? '').length > 0) {
          this.previewRow('公网地址', pkg.iosConfig.publicURL ?? '')
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.settings_card_background'))
    .border({ width: 1, color: $r('app.color.settings_card_border') })
    .borderRadius(18)
    .shadow({ radius: 12, color: $r('app.color.settings_card_shadow'), offsetY: 4 })
  }

  @Builder
  private idRestoreContent() {
    Column({ space: 14 }) {
      Text('输入导出时获得的备份 ID，从备份服务器或主服务器找回配置。')
        .width('100%')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
      TextInput({
        text: this.restoreID,
        placeholder: 'bgo_20260504_abcd2345efgh6'
      })
        .width('100%')
        .height(48)
        .fontFamily('monospace')
        .backgroundColor($r('app.color.settings_input_background'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.restoreID = value;
          this.errorText = '';
        })
      AppActionButton({
        title: this.viewModel.isRestoring ? '正在恢复…' : '找回并恢复',
        role: AppButtonRole.Primary,
        isEnabled: !this.viewModel.isRestoring && this.restoreID.trim().length > 0,
        loading: this.viewModel.isRestoring,
        onPress: (): void => {
          this.restoreFromID().catch((): void => {});
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private fileRestoreContent() {
    Column({ space: 16 }) {
      Text('选择由 Live OS 导出的 JSON 备份文件，先预览内容再确认恢复。')
        .width('100%')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
      AppActionButton({
        title: this.selectingFile ? '正在选择…' : '选择本地备份文件',
        role: AppButtonRole.Secondary,
        isEnabled: !this.selectingFile && !this.viewModel.isRestoring,
        loading: this.selectingFile,
        onPress: (): void => {
          this.selectLocalBackup().catch((): void => {});
        }
      })
      if (this.importedPackage !== null) {
        this.backupPreview(this.importedPackage)
        AppActionButton({
          title: this.viewModel.isRestoring ? '正在恢复…' : '恢复这个备份',
          role: AppButtonRole.Primary,
          isEnabled: !this.viewModel.isRestoring,
          loading: this.viewModel.isRestoring,
          onPress: (): void => {
            this.restoreImportedPackage().catch((): void => {});
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Row() {
        Scroll() {
          Column({ space: 20 }) {
          this.modePicker()
          Column() {
            if (this.selectedMode === 0) {
              this.idRestoreContent()
            } else {
              this.fileRestoreContent()
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.settings_card_background'))
          .border({ width: 1, color: $r('app.color.settings_card_border') })
          .borderRadius(18)
          .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })

          if (this.viewModel.isRestoring) {
            Row({ space: 12 }) {
              LoadingProgress().width(24).height(24)
              Column({ space: 4 }) {
                Text('恢复进行中')
                  .width('100%')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                Text(this.viewModel.progressMessage.length > 0 ?
                  this.viewModel.progressMessage : '服务正在恢复…')
                  .width('100%')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#141FDBC7')
            .borderRadius(12)
          }

          if (this.errorText.length > 0) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
                .fontSize(18)
                .fontColor(['#D67613'])
              Text(this.errorText).layoutWeight(1).fontSize(14).fontColor('#A45A12')
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#12D67613')
            .borderRadius(10)
          }

          Text('恢复会要求主服务器写入配置并可能重启服务；重启期间短暂连接失败属于正常现象。')
            .width('100%')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 32 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: 960 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 180,
        colors: [
          [$r('app.color.settings_background_top'), 0.0],
          [$r('app.color.settings_background_bottom'), 1.0]
        ]
      })
    }
    .title('恢复备份')
    .onReady((context: NavDestinationContext): void => {
      this.pathStack = context.pathStack;
    })
  }
}
