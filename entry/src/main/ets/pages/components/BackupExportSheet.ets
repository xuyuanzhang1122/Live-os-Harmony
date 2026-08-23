import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import pasteboard from '@ohos.pasteboard';
import { AppConfig } from '../../config/AppConfig';
import { BackupDeviceConfig, BackupPackage } from '../../model/BackupModels';
import {
  BackupExportViewModel,
  BackupUploadOutcome,
  backupFilename,
  backupUploadErrorText
} from '../../viewmodel/BackupViewModel';

@ComponentV2
export struct BackupExportSheet {
  @Event onClose: () => void = (): void => {};
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private viewModel: BackupExportViewModel =
    new BackupExportViewModel(AppConfig.getInstance().getClient());
  @Local private isWorking: boolean = false;
  @Local private isUploading: boolean = false;
  @Local private localStatus: string = '';
  @Local private localError: string = '';
  @Local private remoteID: string = '';
  @Local private remoteStatus: string = '';
  @Local private remoteError: string = '';

  private async createBackup(): Promise<void> {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    this.isUploading = false;
    this.localStatus = '';
    this.localError = '';
    this.remoteID = '';
    this.remoteStatus = '';
    this.remoteError = '';
    this.viewModel.updateClient(this.config.getClient());
    try {
      const device: BackupDeviceConfig = new BackupDeviceConfig(
        this.config.serverURL ?? '',
        this.config.lanURL ?? '',
        this.config.publicURL ?? '',
        this.config.autoSwitchNetwork ?? false
      );
      const pkg: BackupPackage = await this.viewModel.buildPackage(device);
      const localTask: Promise<void> = this.saveLocalBackup(pkg);
      const uploadTask: Promise<void> = this.uploadRemoteBackup(pkg);
      await Promise.all([localTask, uploadTask]);
    } catch (error) {
      this.localError = error instanceof Error ? error.message : `${error}`;
    } finally {
      this.isWorking = false;
      this.isUploading = false;
    }
  }

  private async saveLocalBackup(pkg: BackupPackage): Promise<void> {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.localError = '无法打开文件保存窗口';
      return;
    }
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    let uris: string[];
    try {
      uris = await documentPicker.save({
        newFileNames: [backupFilename()],
        fileSuffixChoices: ['JSON|.json']
      });
    } catch (_) {
      this.localStatus = '已取消保存本地文件';
      return;
    }
    if (uris.length === 0) {
      this.localStatus = '已取消保存本地文件';
      return;
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, pkg.toJson());
      this.localStatus = '本地备份文件已保存';
    } catch (error) {
      this.localError = `本地文件保存失败：${error instanceof Error ? error.message : `${error}`}`;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private async uploadRemoteBackup(pkg: BackupPackage): Promise<void> {
    this.isUploading = true;
    try {
      const outcome: BackupUploadOutcome = await this.viewModel.uploadPackage(pkg, this.config.backupServerURL ?? '');
      this.remoteID = outcome.record.id ?? '';
      this.remoteStatus = outcome.statusText;
    } catch (error) {
      const value: Object = error instanceof Error ? error : new Error(`${error}`);
      this.remoteError = backupUploadErrorText(value);
    } finally {
      this.isUploading = false;
    }
  }

  private copyBackupID(): void {
    const backupID: string = this.remoteID;
    if (backupID.length === 0) {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, backupID);
      pasteboard.getSystemPasteboard().setData(data).then((): void => {
        this.showToast('备份 ID 已复制');
      }).catch((): void => {
        this.showToast('复制失败');
      });
    } catch (_) {
      this.showToast('复制失败');
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  @Builder
  private statusCard(message: string, error: boolean) {
    Row({ space: 10 }) {
      Text(error ? '!' : '✓')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(error ? '#D67613' : '#188A62')
      Text(message)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor(error ? '#A45A12' : '#146D51')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(error ? '#12D67613' : '#12188A62')
    .borderRadius(10)
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Button('关闭')
            .type(ButtonType.Normal)
            .fontColor($r('sys.color.font_secondary'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.onClose())
          Text('导出备份')
            .layoutWeight(1)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
          Blank().width(64)
        }
        .width('100%')

        Text('备份包含服务器地址、端口绑定、输出目录、AppData 路径和直播间地址；不会包含 API Key、Cookie 或观看历史。')
          .width('100%')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))

        Button(this.isWorking ? '正在导出…' : '导出并备份') {
          if (this.isWorking) {
            LoadingProgress().width(20).height(20).margin({ right: 8 })
          }
        }
        .width('100%')
        .height(48)
        .enabled(!this.isWorking && this.config.activeURL.length > 0)
        .fontColor(Color.White)
        .backgroundColor(!this.isWorking && this.config.activeURL.length > 0 ?
          $r('app.color.brand_color') : '#909399')
        .onClick((): void => {
          this.createBackup().catch((): void => {});
        })

        if (this.config.activeURL.length === 0) {
          Text('请先在设置中配置服务器')
            .width('100%')
            .fontSize(13)
            .fontColor('#D67613')
        }

        if (this.localStatus.length > 0) {
          this.statusCard(this.localStatus, false)
        }
        if (this.localError.length > 0) {
          this.statusCard(this.localError, true)
        }

        if (this.isUploading) {
          Row({ space: 10 }) {
            LoadingProgress().width(20).height(20)
            Text('正在上传备份…').fontSize(14).fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding(12)
        }

        if (this.remoteID.length > 0) {
          Column({ space: 10 }) {
            Text('备份 ID')
              .width('100%')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
            Text(this.remoteID)
              .width('100%')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .textAlign(TextAlign.Center)
              .copyOption(CopyOptions.None)
            Button('复制 ID')
              .width('100%')
              .height(40)
              .type(ButtonType.Normal)
              .fontColor($r('app.color.brand_color'))
              .backgroundColor('#141FDBC7')
              .onClick((): void => this.copyBackupID())
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .borderRadius(12)
        }

        if (this.remoteStatus.length > 0) {
          this.statusCard(this.remoteStatus, false)
        }
        if (this.remoteError.length > 0) {
          this.statusCard(this.remoteError, true)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
