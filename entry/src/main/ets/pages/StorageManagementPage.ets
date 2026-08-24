import { ThumbnailCache } from '../cache/ThumbnailCache';
import { AppButtonRole } from '../common/Theme';
import { Formats } from '../common/Formats';
import { ApiCache } from '../net/ApiCache';
import { cacheClearMessage, totalCacheBytes } from '../viewmodel/SettingsViewModel';
import { AppActionButton } from './components/AppActionButton';
import { SettingsRowIcon } from './components/SettingsRowIcon';

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
  private sizeRow(title: string, bytes: number, symbol: Resource,
    iconColor: ResourceColor, iconBackground: ResourceColor) {
    Row({ space: 12 }) {
      SettingsRowIcon({ symbol: symbol, color: iconColor, tileColor: iconBackground })
      Text(title).fontSize(16).layoutWeight(1)
      Text(Formats.formatBytes(bytes)).fontSize(14).fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }

  build() {
    NavDestination() {
      Row() {
        Column({ space: 18 }) {
          Column() {
            this.sizeRow('缩略图缓存', this.thumbnailBytes,
              $r('sys.symbol.picture_fill'), '#3478F6', '#183478F6')
            Divider().margin({ left: 62 }).color($r('sys.color.comp_divider'))
            this.sizeRow('接口数据缓存', this.apiBytes,
              $r('sys.symbol.network_acceleration'), '#14A89A', '#1814A89A')
            Divider().margin({ left: 62 }).color($r('sys.color.comp_divider'))
            Row({ space: 12 }) {
              SettingsRowIcon({
                symbol: $r('sys.symbol.externaldrive_fill'), color: '#8B5CF6', tileColor: '#188B5CF6'
              })
              Text('合计').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
              Text(Formats.formatBytes(totalCacheBytes(this.apiBytes, this.thumbnailBytes)))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          }
          .width('100%')
          .backgroundColor($r('app.color.settings_card_background'))
          .border({ width: 1, color: $r('app.color.settings_card_border') })
          .borderRadius(18)
          .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
          .clip(true)

          Text('缓存用于加快视频库加载，清除后会在下次访问时自动重新生成。')
            .width('100%')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 12, right: 12 })

          AppActionButton({
            title: this.clearing ? '清除中…' : '清除所有缓存',
            role: AppButtonRole.Destructive,
            isEnabled: !this.clearing,
            loading: this.clearing,
            onPress: (): void => {
              this.confirmClear().catch((): void => {});
            }
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: 960 })
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Top)
      .linearGradient({
        angle: 180,
        colors: [
          [$r('app.color.settings_background_top'), 0.0],
          [$r('app.color.settings_background_bottom'), 1.0]
        ]
      })
    }
    .title('存储管理')
  }
}
