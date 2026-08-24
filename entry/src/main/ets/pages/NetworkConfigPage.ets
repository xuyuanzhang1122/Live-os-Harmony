import { AppConfig } from '../config/AppConfig';
import { validateNetworkConfig } from '../viewmodel/SettingsViewModel';

@ComponentV2
export struct NetworkConfigPage {
  @Event onSettingsChanged: () => void = (): void => {};
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private smartMode: boolean = false;
  @Local private serverURL: string = '';
  @Local private lanURL: string = '';
  @Local private publicURL: string = '';
  @Local private errorText: string = '';
  @Local private probing: boolean = false;
  @Local private saving: boolean = false;
  @Local private savedVisible: boolean = false;
  private savedTimer: number = -1;

  aboutToAppear(): void {
    this.smartMode = this.config.autoSwitchNetwork;
    this.serverURL = this.config.serverURL;
    this.lanURL = this.config.lanURL;
    this.publicURL = this.config.publicURL;
  }

  aboutToDisappear(): void {
    if (this.savedTimer >= 0) {
      clearTimeout(this.savedTimer);
      this.savedTimer = -1;
    }
  }

  private async refreshConnection(): Promise<void> {
    this.probing = true;
    try {
      await this.config.refreshNetworkStatus();
    } finally {
      this.probing = false;
    }
  }

  private async save(): Promise<void> {
    const validation: string = validateNetworkConfig(this.smartMode, this.serverURL, this.lanURL, this.publicURL);
    if (validation.length > 0) {
      this.errorText = validation;
      return;
    }
    this.errorText = '';
    this.saving = true;
    const normalizedServer: string = this.serverURL.trim();
    const normalizedLAN: string = this.lanURL.trim();
    const normalizedPublic: string = this.publicURL.trim();
    const changed: boolean = this.config.autoSwitchNetwork !== this.smartMode ||
      this.config.serverURL !== normalizedServer || this.config.lanURL !== normalizedLAN ||
      this.config.publicURL !== normalizedPublic;
    this.config.autoSwitchNetwork = this.smartMode;
    this.config.serverURL = normalizedServer;
    this.config.lanURL = normalizedLAN;
    this.config.publicURL = normalizedPublic;
    if (changed) {
      this.config.serverInfo = null;
    }
    try {
      await this.config.refreshNetworkStatus();
      this.onSettingsChanged();
      this.showSavedCapsule();
    } finally {
      this.saving = false;
    }
  }

  private showSavedCapsule(): void {
    this.savedVisible = true;
    if (this.savedTimer >= 0) {
      clearTimeout(this.savedTimer);
    }
    this.savedTimer = setTimeout((): void => {
      this.savedVisible = false;
      this.savedTimer = -1;
    }, 1500);
  }

  @Builder
  private modePicker() {
    Row() {
      Button('手动')
        .layoutWeight(1)
        .height(36)
        .type(ButtonType.Normal)
        .fontColor(this.smartMode ? $r('sys.color.font_secondary') : Color.White)
        .backgroundColor(this.smartMode ? Color.Transparent : $r('app.color.brand_color'))
        .borderRadius(9)
        .onClick((): void => {
          this.smartMode = false;
          this.errorText = '';
        })
      Button('智能切换')
        .layoutWeight(1)
        .height(36)
        .type(ButtonType.Normal)
        .fontColor(this.smartMode ? Color.White : $r('sys.color.font_secondary'))
        .backgroundColor(this.smartMode ? $r('app.color.brand_color') : Color.Transparent)
        .borderRadius(9)
        .onClick((): void => {
          this.smartMode = true;
          this.errorText = '';
        })
    }
    .width('100%')
    .padding(3)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
  }

  @Builder
  private urlField(title: string, value: string, placeholder: string, helper: string, field: number) {
    Column({ space: 7 }) {
      Text(title).width('100%').fontSize(15).fontWeight(FontWeight.Medium)
      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(46)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(10)
        .onChange((next: string): void => {
          if (field === 0) {
            this.serverURL = next;
          } else if (field === 1) {
            this.lanURL = next;
          } else {
            this.publicURL = next;
          }
          this.errorText = '';
        })
      if (helper.length > 0) {
        Text(helper).width('100%').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private connectionCard() {
    Column({ space: 10 }) {
      Row() {
        Text('当前连接').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button(this.probing ? '探测中…' : '刷新')
          .type(ButtonType.Normal)
          .fontSize(13)
          .fontColor($r('app.color.brand_color'))
          .backgroundColor(Color.Transparent)
          .enabled(!this.probing)
          .onClick((): void => {
            this.refreshConnection().catch((): void => {});
          })
      }
      Row({ space: 8 }) {
        if (this.probing) {
          LoadingProgress().width(18).height(18)
        } else if (this.config.isOnLAN) {
          SymbolGlyph($r('sys.symbol.wifi')).fontSize(18).fontColor([$r('app.color.brand_color')])
        } else {
          Text('🌐').fontSize(18)
        }
        Text(this.probing ? '正在探测局域网…' : (this.config.isOnLAN ? '局域网 LAN' : '公网'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
      }
      Text(this.config.activeURL.length > 0 ? this.config.activeURL : '尚未建立连接')
        .width('100%')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .borderRadius(14)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: 20 }) {
            this.modePicker()

            Column({ space: 18 }) {
              if (this.smartMode) {
                this.urlField('局域网地址', this.lanURL, 'http://192.168.1.10:8080', '在家或店里速度最快', 1)
                this.urlField('公网地址', this.publicURL, 'https://live.example.com',
                  '端口转发 / frp / cloudflare 均可', 2)
              } else {
                this.urlField('服务器地址', this.serverURL, 'http://192.168.1.10:8080', '', 0)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('sys.color.comp_background_primary'))
            .borderRadius(14)

            if (this.smartMode) {
              this.connectionCard()
            }

            if (this.errorText.length > 0) {
              Text(this.errorText)
                .width('100%')
                .padding(12)
                .fontSize(13)
                .fontColor('#E84040')
                .backgroundColor('#14E84040')
                .borderRadius(10)
            }

            Button(this.saving ? '保存中…' : '保存')
              .width('100%')
              .height(46)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.brand_color'))
              .enabled(!this.saving)
              .onClick((): void => {
                this.save().catch((): void => {});
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 72 })
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: 960 })

        if (this.savedVisible) {
          Text('已保存')
            .fontSize(14)
            .fontColor(Color.White)
            .padding({ left: 20, right: 20, top: 9, bottom: 9 })
            .margin({ bottom: 24 })
            .backgroundColor('#CC202020')
            .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
            .borderRadius(20)
            .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%')
      .height('100%')
      .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .title('网络配置')
  }
}
