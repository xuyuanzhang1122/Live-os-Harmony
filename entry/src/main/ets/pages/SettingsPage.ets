import { pasteboard } from '@kit.BasicServicesKit';
import { ApiCache } from '../net/ApiCache';
import { ThumbnailCache } from '../cache/ThumbnailCache';
import { AppButtonRole, ConnectionVisualState, settingsConnectionVisualState } from '../common/Theme';
import { AppConfig } from '../config/AppConfig';
import { ServerInfo } from '../model/Common';
import { apiKeySummary, apiKeySummaryNeedsReload, totalCacheBytes } from '../viewmodel/SettingsViewModel';
import { AppActionButton } from './components/AppActionButton';
import { SettingsRowIcon } from './components/SettingsRowIcon';

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
    // 先同步给出绑定状态，异步读取成功后再补全尾号；读取返回空时不覆盖已绑定文案
    this.keyText = this.config.apiKeyBound ? '已配置' : '未设置';
    this.config.getApiKey().then((key: string): void => {
      if (key.trim().length > 0 || !this.config.apiKeyBound) {
        this.keyText = apiKeySummary(key, null);
      }
    }).catch((): void => {
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

  private connectionVisualState(): ConnectionVisualState {
    return settingsConnectionVisualState(this.testingConnection, this.connectionFailed,
      this.config.isOnLAN, this.config.serverInfo !== null);
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
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .padding({ left: 6, bottom: 8 })
  }

  @Builder
  private line() {
    Divider()
      .margin({ left: 62 })
      .color($r('sys.color.comp_divider'))
  }

  @Builder
  private chevron() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontColor([$r('sys.color.font_secondary')])
  }

  @Builder
  private navRow(symbol: Resource, iconColor: ResourceColor, iconBackground: ResourceColor,
    title: string, subtitle: string, route: string) {
    Button() {
      Row({ space: 12 }) {
        SettingsRowIcon({ symbol: symbol, color: iconColor, tileColor: iconBackground })
        Column({ space: 3 }) {
          Text(title)
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .textAlign(TextAlign.Start)
          if (subtitle.length > 0) {
            Text(subtitle)
              .width('100%')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.chevron()
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    }
    .type(ButtonType.Normal)
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
    .onClick((): void => this.stack.pushPath({ name: route }))
  }

  @Builder
  private connectionIcon() {
    if (this.connectionVisualState() === ConnectionVisualState.Loading) {
      Stack() {
        LoadingProgress().width(18).height(18).color('#0D8D81')
      }
      .width(34)
      .height(34)
      .backgroundColor('#181FDBC7')
      .borderRadius(10)
    } else if (this.connectionVisualState() === ConnectionVisualState.Failure) {
      SettingsRowIcon({
        symbol: $r('sys.symbol.xmark_circle_fill'), color: '#E84040', tileColor: '#16E84040'
      })
    } else if (this.connectionVisualState() === ConnectionVisualState.LAN) {
      SettingsRowIcon({ symbol: $r('sys.symbol.wifi'), color: '#20A66A', tileColor: '#1820A66A' })
    } else if (this.connectionVisualState() === ConnectionVisualState.Public) {
      SettingsRowIcon({
        symbol: $r('sys.symbol.worldclock_fill_1'), color: '#3478F6', tileColor: '#183478F6'
      })
    } else {
      SettingsRowIcon({ symbol: $r('sys.symbol.circle'), color: '#8E8E93', tileColor: '#188E8E93' })
    }
  }

  @Builder
  private serverSection() {
    Column() {
      this.navRow($r('sys.symbol.network_acceleration'), '#3478F6', '#183478F6',
        '网络配置', this.networkSubtitle(), 'NetworkConfigPage')
      this.line()
      this.navRow($r('sys.symbol.square_and_arrow_down'), '#14A89A', '#1814A89A',
        '恢复备份', '通过 ID 或本地文件找回配置', 'RestoreBackupPage')
      this.line()
      Row({ space: 12 }) {
        this.connectionIcon()
        Column({ space: 3 }) {
          Text('连接状态').width('100%').fontSize(16).fontWeight(FontWeight.Medium)
          Text(this.testingConnection ? '正在测试服务器…' : this.connectionText)
            .width('100%')
            .fontSize(12)
            .fontColor(this.connectionFailed ? '#E84040' : $r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        AppActionButton({
          title: this.testingConnection ? '测试中' : '测试',
          role: AppButtonRole.Secondary,
          isEnabled: !this.testingConnection,
          fill: false,
          compact: true,
          onPress: (): void => {
            this.testConnection().catch((): void => {});
          }
        })
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 12, bottom: 12 })
      this.line()
      Row({ space: 12 }) {
        SettingsRowIcon({
          symbol: $r('sys.symbol.externaldrive_fill'), color: '#8B5CF6', tileColor: '#188B5CF6'
        })
        Text('服务器版本').fontSize(16).layoutWeight(1)
        Text(this.serverVersion()).fontSize(14).fontColor($r('sys.color.font_secondary'))
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
  }

  @Builder
  private backupSection() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        SettingsRowIcon({
          symbol: $r('sys.symbol.icloud'), color: '#3478F6', tileColor: '#183478F6'
        })
        Column({ space: 3 }) {
          Text('备份地址').width('100%').fontSize(16).fontWeight(FontWeight.Medium)
          Text('远端备份独立保存位置')
            .width('100%')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      TextInput({ text: this.backupInput, placeholder: '留空则存主服务器' })
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.settings_input_background'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.backupInput = value;
        })
        .onBlur((): void => this.saveBackupURL())
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.settings_card_background'))
    .border({ width: 1, color: $r('app.color.settings_card_border') })
    .borderRadius(18)
    .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
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
            this.backupSection()
            Text('配置后远端备份上传到该服务器，主服务器重装后仍可凭 ID 找回；留空则存主服务器。')
              .width('100%')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .padding({ left: 8, right: 8, top: 8 })
          }
        }

        ListItem() {
          Column() {
            this.groupTitle('认证')
            Column() {
              this.navRow($r('sys.symbol.key_fill'), '#F59E0B', '#18F59E0B',
                'API Key', this.keyText, 'ApiKeyPage')
            }
            .backgroundColor($r('app.color.settings_card_background'))
            .border({ width: 1, color: $r('app.color.settings_card_border') })
            .borderRadius(18)
            .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
            Text('在服务端 Web 设置页开启 API Key 后填入，各设备进度互不串扰。')
              .width('100%')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .padding({ left: 8, right: 8, top: 8 })
          }
        }

        ListItem() {
          Column() {
            this.groupTitle('存储')
            Column() {
              this.navRow($r('sys.symbol.externaldrive_fill'), '#8B5CF6', '#188B5CF6',
                '存储管理', this.cacheText, 'StorageManagementPage')
            }
            .backgroundColor($r('app.color.settings_card_background'))
            .border({ width: 1, color: $r('app.color.settings_card_border') })
            .borderRadius(18)
            .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
          }
        }

        ListItem() {
          Column() {
            this.groupTitle('关于')
            Column() {
              this.navRow($r('sys.symbol.info_circle_fill'), '#3478F6', '#183478F6',
                '版本', '2.0.0', 'AboutPage')
              this.line()
              Button() {
                Row({ space: 12 }) {
                  SettingsRowIcon({ symbol: $r('sys.symbol.link'), color: '#3478F6', tileColor: '#183478F6' })
                  Text('GitHub 开源项目').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
                  Text('复制链接').fontSize(12).fontColor($r('sys.color.font_secondary'))
                  this.chevron()
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              }
              .type(ButtonType.Normal)
              .width('100%')
              .backgroundColor(Color.Transparent)
              .borderRadius(12)
              .onClick((): void => this.copyGitHub())
            }
            .width('100%')
            .backgroundColor($r('app.color.settings_card_background'))
            .border({ width: 1, color: $r('app.color.settings_card_border') })
            .borderRadius(18)
            .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
            .clip(true)
            Text('由 Xumy 开发')
              .width('100%')
              .padding({ top: 14, bottom: 4 })
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 960 })
      .padding({ left: 14, right: 14, top: 14, bottom: 32 })
      .backgroundColor(Color.Transparent)
      .edgeEffect(EdgeEffect.Spring)
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
}
