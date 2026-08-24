import { pasteboard } from '@kit.BasicServicesKit';
import { ApiCache } from '../net/ApiCache';
import { ThumbnailCache } from '../cache/ThumbnailCache';
import { AppConfig } from '../config/AppConfig';
import { ServerInfo } from '../model/Common';
import { apiKeySummary, apiKeySummaryNeedsReload, totalCacheBytes } from '../viewmodel/SettingsViewModel';

const GITHUB_URL: string = 'https://github.com/xuyuanzhang1122/bililive-harmony';

@ComponentV2
export struct SettingsPage {
  @Require @Param stack: NavPathStack;
  @Require @Param active: boolean;
  @Require @Param refreshToken: number;
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private backupInput: string = '';
  @Local private keyText: string = '未设置';
  @Local private cacheText: string = '已用 0.0 MB';
  @Local private testingConnection: boolean = false;
  @Local private connectionText: string = '未测试';
  @Local private connectionFailed: boolean = false;

  aboutToAppear(): void {
    this.reloadSummaries();
  }

  @Monitor('active')
  onActiveChanged(_monitor: IMonitor): void {
    if (this.active) {
      this.reloadSummaries();
    }
  }

  @Monitor('refreshToken')
  onRefreshTokenChanged(_monitor: IMonitor): void {
    this.reloadSummaries();
  }

  @Monitor('config.apiKeyBound')
  onApiKeyBoundChanged(_monitor: IMonitor): void {
    if (apiKeySummaryNeedsReload(this.config.apiKeyBound, this.keyText)) {
      this.reloadApiKeySummary();
    }
  }

  private reloadSummaries(): void {
    this.backupInput = this.config.backupServerURL;
    const total: number = totalCacheBytes(ApiCache.getInstance().sizeBytes(), ThumbnailCache.getInstance().sizeBytes());
    this.cacheText = `已用 ${(total / 1024 / 1024).toFixed(1)} MB`;
    this.reloadApiKeySummary();
    if (this.config.serverInfo === null) {
      this.connectionText = '未测试';
      this.connectionFailed = false;
    } else if (this.connectionText === '未测试') {
      this.connectionText = `${this.config.serverInfo.app_name} ${this.config.serverInfo.app_version}`;
      this.connectionFailed = false;
    }
  }

  private reloadApiKeySummary(): void {
    this.config.getApiKey().then((key: string): void => {
      this.keyText = apiKeySummary(key, null);
    }).catch((): void => {
      this.keyText = this.config.apiKeyBound ? '已配置' : '未设置';
    });
  }

  private networkSubtitle(): string {
    if (this.config.autoSwitchNetwork) {
      return '智能切换 · 局域网/公网';
    }
    return this.config.serverURL.length > 0 ? this.config.serverURL : '未配置';
  }

  private serverVersion(): string {
    return this.config.serverInfo === null ? '-' : this.config.serverInfo.app_version;
  }

  private async testConnection(): Promise<void> {
    this.testingConnection = true;
    this.connectionFailed = false;
    try {
      const info: ServerInfo = await this.config.getClient().getServerInfo();
      this.config.serverInfo = info;
      this.connectionText = `${info.app_name} ${info.app_version}`;
    } catch (_) {
      this.connectionText = '连接失败';
      this.connectionFailed = true;
    } finally {
      this.testingConnection = false;
    }
  }

  private saveBackupURL(): void {
    this.backupInput = this.backupInput.trim();
    this.config.backupServerURL = this.backupInput;
  }

  private copyGitHub(): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GITHUB_URL);
      pasteboard.getSystemPasteboard().setData(data).then((): void => {
        this.showToast('GitHub 链接已复制');
      }).catch((): void => {
        this.showToast(GITHUB_URL);
      });
    } catch (_) {
      this.showToast(GITHUB_URL);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  @Builder
  private groupTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .padding({ left: 12, bottom: 7 })
  }

  @Builder
  private line() {
    Divider()
      .margin({ left: 16 })
      .color($r('sys.color.comp_divider'))
  }

  @Builder
  private serverSection() {
    Column() {
      Column({ space: 3 }) {
        Row() {
          Column({ space: 3 }) {
            Text('网络配置').fontSize(16)
            Text(this.networkSubtitle())
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('›').fontSize(24).fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding(16)
      }
      .onClick((): void => this.stack.pushPath({ name: 'NetworkConfigPage' }))
      this.line()
      Row() {
        Text('恢复备份').fontSize(16).layoutWeight(1)
        Text('›').fontSize(24).fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding(16)
      .onClick((): void => this.stack.pushPath({ name: 'RestoreBackupPage' }))
      this.line()
      Row({ space: 10 }) {
        Text('连接状态').fontSize(16).layoutWeight(1)
        if (!this.testingConnection && !this.connectionFailed && this.config.serverInfo !== null) {
          if (this.config.isOnLAN) {
            SymbolGlyph($r('sys.symbol.wifi')).fontSize(17).fontColor([$r('app.color.brand_color')])
          } else {
            Text('🌐').fontSize(17)
          }
        }
        Text(this.testingConnection ? '测试中…' : this.connectionText)
          .fontSize(13)
          .fontColor(this.connectionFailed ? '#E84040' : $r('sys.color.font_secondary'))
          .maxLines(1)
        Button('测试')
          .type(ButtonType.Normal)
          .fontSize(13)
          .fontColor($r('app.color.brand_color'))
          .backgroundColor(Color.Transparent)
          .enabled(!this.testingConnection)
          .onClick((): void => {
            this.testConnection().catch((): void => {});
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 10, bottom: 10 })
      this.line()
      Row() {
        Text('服务器版本').fontSize(16).layoutWeight(1)
        Text(this.serverVersion()).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(14)
    .clip(true)
  }

  @Builder
  private backupSection() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text('URL').fontSize(16)
        TextInput({ text: this.backupInput, placeholder: '留空则存主服务器' })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .textAlign(TextAlign.End)
          .onChange((value: string): void => {
            this.backupInput = value;
          })
          .onBlur((): void => this.saveBackupURL())
      }
      .width('100%')
      .padding(16)
      Text('配置后远端备份上传到该服务器，主服务器重装后仍可凭 ID 找回；留空则存主服务器')
        .width('100%')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .padding({ left: 12, right: 12, bottom: 2 })
    }
  }

  @Builder
  private simpleNavRow(title: string, subtitle: string, route: string) {
    Row({ space: 12 }) {
      Text(title).fontSize(16).layoutWeight(1)
      Text(subtitle)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('›').fontSize(24).fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding(16)
    .onClick((): void => this.stack.pushPath({ name: route }))
  }

  build() {
    Row() {
      List({ space: 18 }) {
      ListItem() {
        Column() {
          this.groupTitle('服务器')
          this.serverSection()
        }
      }

      ListItem() {
        Column() {
          this.groupTitle('备份服务器（源站）')
          Column() {
            this.backupSection()
          }
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(14)
          .padding({ bottom: 10 })
        }
      }

      ListItem() {
        Column() {
          this.groupTitle('认证')
          Column() {
            this.simpleNavRow('API Key', this.keyText, 'ApiKeyPage')
          }
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(14)
          Text('在服务端 Web 设置页开启 API Key 后填入，各设备进度互不串扰')
            .width('100%')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 12, right: 12, top: 7 })
        }
      }

      ListItem() {
        Column() {
          this.groupTitle('存储')
          Column() {
            this.simpleNavRow('存储管理', this.cacheText, 'StorageManagementPage')
          }
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(14)
        }
      }

      ListItem() {
        Column() {
          this.groupTitle('关于')
          Column() {
            this.simpleNavRow('版本', '2.0.0', 'AboutPage')
            this.line()
            Row() {
              Text('GitHub').fontSize(16).layoutWeight(1)
              Text('复制链接').fontSize(13).fontColor($r('sys.color.font_secondary'))
              Text('›').fontSize(24).fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
            .padding(16)
            .onClick((): void => this.copyGitHub())
            this.line()
            Text('由 Xumy 开发')
              .width('100%')
              .padding(16)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
          }
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(14)
          .clip(true)
        }
      }
    }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 960 })
      .padding({ left: 12, right: 12, top: 12, bottom: 28 })
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
