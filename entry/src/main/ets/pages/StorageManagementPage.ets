import { ThumbnailCache } from '../cache/ThumbnailCache';
import { Formats } from '../common/Formats';
import { ApiCache } from '../net/ApiCache';
import { cacheClearMessage, totalCacheBytes } from '../viewmodel/SettingsViewModel';

@ComponentV2
export struct StorageManagementPage {
  @Event onSettingsChanged: () => void = (): void => {};
  @Local private thumbnailBytes: number = 0;
  @Local private apiBytes: number = 0;
  @Local private clearing: boolean = false;

  aboutToAppear(): void {
    this.reloadSizes();
  }

  private reloadSizes(): void {
    this.thumbnailBytes = ThumbnailCache.getInstance().sizeBytes();
    this.apiBytes = ApiCache.getInstance().sizeBytes();
  }

  private async confirmClear(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '清除所有缓存',
        message: '确定清除缩略图和接口数据缓存吗？已录制的视频不会被删除。',
        buttons: [{ text: '取消', color: '#666666' }, { text: '清除', color: '#E84040' }]
      });
      if (result.index !== 1) {
        return;
      }
      this.clearing = true;
      ThumbnailCache.getInstance().clearAll();
      ApiCache.getInstance().clear();
      this.reloadSizes();
      this.onSettingsChanged();
      try {
        const remaining: number = totalCacheBytes(this.apiBytes, this.thumbnailBytes);
        this.getUIContext().getPromptAction().showToast({ message: cacheClearMessage(remaining), duration: 2000 });
      } catch (_) {
      }
    } catch (_) {
    } finally {
      this.clearing = false;
    }
  }

  @Builder
  private sizeRow(title: string, bytes: number) {
    Row() {
      Text(title).fontSize(16).layoutWeight(1)
      Text(Formats.formatBytes(bytes)).fontSize(14).fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding(16)
  }

  build() {
    NavDestination() {
      Column({ space: 18 }) {
        Column() {
          this.sizeRow('缩略图缓存', this.thumbnailBytes)
          Divider().margin({ left: 16 }).color($r('sys.color.comp_divider'))
          this.sizeRow('接口数据缓存', this.apiBytes)
          Divider().margin({ left: 16 }).color($r('sys.color.comp_divider'))
          Row() {
            Text('合计').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
            Text(Formats.formatBytes(totalCacheBytes(this.apiBytes, this.thumbnailBytes)))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(14)
        .clip(true)

        Text('缓存用于加快视频库加载，清除后会在下次访问时自动重新生成。')
          .width('100%')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 12, right: 12 })

        Button(this.clearing ? '清除中…' : '清除所有缓存')
          .width('100%')
          .height(46)
          .fontColor('#E84040')
          .backgroundColor('#14E84040')
          .enabled(!this.clearing)
          .onClick((): void => {
            this.confirmClear().catch((): void => {});
          })
      }
      .width('100%')
      .padding(16)
    }
    .title('存储管理')
  }
}
