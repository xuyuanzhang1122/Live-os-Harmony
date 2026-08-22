import { AppConfig } from '../config/AppConfig';
import { APIKeyUser } from '../model/Common';
import { APIClient } from '../net/APIClient';
import { apiKeyValidationError } from '../viewmodel/SettingsViewModel';

@ComponentV2
export struct ApiKeyPage {
  @Event onSettingsChanged: () => void = (): void => {};
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private inputKey: string = '';
  @Local private savedKey: string = '';
  @Local private user: APIKeyUser | null = null;
  @Local private showKey: boolean = false;
  @Local private validating: boolean = false;
  @Local private loadingSaved: boolean = false;
  @Local private errorText: string = '';

  aboutToAppear(): void {
    this.loadSavedKey().catch((): void => {});
  }

  private async loadSavedKey(): Promise<void> {
    this.loadingSaved = true;
    try {
      const key: string = await this.config.getApiKey();
      this.savedKey = key;
      this.inputKey = key;
      if (key.length > 0) {
        const client: APIClient = new APIClient(this.config.activeURL, key);
        this.user = await client.getAuthMe();
      }
    } catch (error) {
      this.errorText = apiKeyValidationError(error as Object);
    } finally {
      this.loadingSaved = false;
    }
  }

  private async validateAndBind(): Promise<void> {
    const key: string = this.inputKey.trim();
    if (key.length === 0) {
      this.errorText = '请输入 API Key';
      return;
    }
    if (this.config.activeURL.length === 0) {
      this.errorText = '请先配置服务器地址';
      return;
    }
    this.validating = true;
    this.errorText = '';
    try {
      const client: APIClient = new APIClient(this.config.activeURL, key);
      const boundUser: APIKeyUser = await client.getAuthMe();
      await this.config.setApiKey(key);
      this.savedKey = key;
      this.user = boundUser;
      this.onSettingsChanged();
    } catch (error) {
      this.errorText = apiKeyValidationError(error as Object);
    } finally {
      this.validating = false;
    }
  }

  private async confirmClear(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '清除 API Key',
        message: '确定清除已保存的 API Key 吗？清除后将无法同步该用户的观看进度。',
        buttons: [{ text: '取消', color: '#666666' }, { text: '清除', color: '#E84040' }]
      });
      if (result.index !== 1) {
        return;
      }
      await this.config.clearApiKey();
      this.savedKey = '';
      this.inputKey = '';
      this.user = null;
      this.errorText = '';
      this.showKey = false;
      this.onSettingsChanged();
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : `${error}`;
    }
  }

  private avatarLetter(): string {
    if (this.user === null || this.user.name.length === 0) {
      return '?';
    }
    return this.user.name.substring(0, 1).toUpperCase();
  }

  private keyTail(): string {
    if (this.user !== null && this.user.key_suffix !== null && this.user.key_suffix.length > 0) {
      return this.user.key_suffix;
    }
    return this.savedKey.slice(Math.max(0, this.savedKey.length - 4));
  }

  @Builder
  private boundKeyCard() {
    Column({ space: 16 }) {
      Row({ space: 13 }) {
        Text(this.avatarLetter())
          .width(46)
          .height(46)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.brand_color'))
          .borderRadius(23)
        Column({ space: 3 }) {
          Text(this.user === null ? '' : this.user.name)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
          Text(`User ID · ${this.user === null ? '' : this.user.id}`)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.cloud')).fontSize(14).fontColor([$r('app.color.brand_color')])
          Text('已同步').fontSize(12).fontColor($r('app.color.brand_color'))
        }
        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
        .backgroundColor('#14FF6699')
        .borderRadius(14)
      }

      Row() {
        Text('API Key').fontSize(14).layoutWeight(1)
        Text(`••••${this.keyTail()}`).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }

      Divider().color($r('sys.color.comp_divider'))

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('✓').fontSize(17).fontColor($r('app.color.brand_color'))
          Text('此设备会只读取该用户的服务端观看历史')
            .layoutWeight(1)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        Row({ space: 8 }) {
          Text('↻').fontSize(17).fontColor($r('app.color.brand_color'))
          Text('退出播放器时把最新进度同步回后端')
            .layoutWeight(1)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(18)
    .backgroundColor('#CCFFFFFF')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .borderRadius(16)
    .shadow({ radius: 12, color: '#18000000', offsetY: 4 })
  }

  @Builder
  private keyForm() {
    Column({ space: 16 }) {
      Text('输入服务端 Web 设置页生成的 API Key。测试通过后才会保存到本机。')
        .width('100%')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
      Row({ space: 8 }) {
        TextInput({ text: this.inputKey, placeholder: 'API Key' })
          .layoutWeight(1)
          .height(46)
          .type(this.showKey ? InputType.Normal : InputType.Password)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .borderRadius(10)
          .onChange((value: string): void => {
            this.inputKey = value;
            this.errorText = '';
          })
        Button(this.showKey ? '隐藏' : '显示')
          .type(ButtonType.Normal)
          .height(42)
          .fontSize(13)
          .fontColor($r('app.color.brand_color'))
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.showKey = !this.showKey;
          })
      }
      Button(this.validating ? '测试中…' : '测试并绑定')
        .width('100%')
        .height(46)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand_color'))
        .enabled(!this.validating)
        .onClick((): void => {
          this.validateAndBind().catch((): void => {});
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(14)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 18 }) {
          if (this.loadingSaved) {
            Row({ space: 10 }) {
              LoadingProgress().width(22).height(22)
              Text('正在读取已保存的 Key…').fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding(24)
          } else if (this.user !== null) {
            this.boundKeyCard()
            Button('清除已保存的 Key')
              .width('100%')
              .height(46)
              .fontColor('#E84040')
              .backgroundColor('#14E84040')
              .onClick((): void => {
                this.confirmClear().catch((): void => {});
              })
          } else {
            this.keyForm()
            if (this.savedKey.length > 0) {
              Button('清除已保存的 Key')
                .width('100%')
                .height(46)
                .fontColor('#E84040')
                .backgroundColor('#14E84040')
                .onClick((): void => {
                  this.confirmClear().catch((): void => {});
                })
            }
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
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .height('100%')
    }
    .title('API Key')
  }
}
