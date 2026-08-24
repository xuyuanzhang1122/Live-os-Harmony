import { AppConfig } from '../config/AppConfig';
import { AppButtonRole } from '../common/Theme';
import { APIKeyUser } from '../model/Common';
import { APIClient } from '../net/APIClient';
import { apiKeyValidationError } from '../viewmodel/SettingsViewModel';
import { AppActionButton } from './components/AppActionButton';

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

  private userName(): string {
    if (this.user === null) {
      return '';
    }
    // 服务端 key_suffix/name 等 json tag 带 omitempty，字段缺失时是 undefined 而非 null，
    // 真机默认用户（无 key_suffix）曾在此 TypeError 直接杀进程（jscrash 实锤）。
    return this.user.name ?? '';
  }

  private userId(): string {
    return this.user === null ? '' : (this.user.id ?? '');
  }

  private avatarLetter(): string {
    const name: string = this.userName();
    if (name.length === 0) {
      return '?';
    }
    return name.substring(0, 1).toUpperCase();
  }

  private keyTail(): string {
    const suffix: string = this.user === null ? '' : (this.user.key_suffix ?? '');
    if (suffix.length > 0) {
      return suffix;
    }
    return this.savedKey.slice(Math.max(0, this.savedKey.length - 4));
  }

  @Builder
  private boundKeyCard() {
    Column({ space: 16 }) {
      Row({ space: 13 }) {
        Text(this.avatarLetter())
          .width(54)
          .height(54)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#063D38')
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.brand_color'))
          .borderRadius(18)
        Column({ space: 3 }) {
          Text(this.userName())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
          Text(`User ID · ${this.userId()}`)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.checkmark_icloud_fill')).fontSize(14).fontColor(['#20A66A'])
          Text('已同步').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#20A66A')
        }
        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
        .backgroundColor('#1820A66A')
        .borderRadius(14)
      }

      Row({ space: 8 }) {
        Text(`Key 末尾 ${this.keyTail()}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.settings_card_background'))
          .borderRadius(14)
        Text('观看记录已隔离')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.settings_card_background'))
          .borderRadius(14)
      }

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(17).fontColor(['#20A66A'])
          Text('此设备会只读取该用户的服务端观看历史')
            .layoutWeight(1)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor(['#0D8D81'])
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
    .backgroundColor('#161FDBC7')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .border({ width: 1, color: '#401FDBC7' })
    .borderRadius(24)
    .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
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
          .backgroundColor($r('app.color.settings_input_background'))
          .borderRadius(12)
          .onChange((value: string): void => {
            this.inputKey = value;
            this.errorText = '';
          })
        Button() {
          SymbolGlyph(this.showKey ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_secondary')])
        }
          .type(ButtonType.Normal)
          .width(42)
          .height(42)
          .backgroundColor($r('app.color.settings_input_background'))
          .borderRadius(12)
          .onClick((): void => {
            this.showKey = !this.showKey;
          })
      }
      AppActionButton({
        title: this.validating ? '测试中…' : '测试并绑定',
        role: AppButtonRole.Primary,
        isEnabled: !this.validating,
        loading: this.validating,
        onPress: (): void => {
          this.validateAndBind().catch((): void => {});
        }
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.settings_card_background'))
    .border({ width: 1, color: $r('app.color.settings_card_border') })
    .borderRadius(18)
    .shadow({ radius: 14, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
  }

  build() {
    NavDestination() {
      Row() {
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
            AppActionButton({
              title: '清除已保存的 Key',
              role: AppButtonRole.Destructive,
              onPress: (): void => {
                this.confirmClear().catch((): void => {});
              }
            })
          } else {
            this.keyForm()
            if (this.savedKey.length > 0) {
              AppActionButton({
                title: '清除已保存的 Key',
                role: AppButtonRole.Destructive,
                onPress: (): void => {
                  this.confirmClear().catch((): void => {});
                }
              })
            }
          }

          if (this.errorText.length > 0) {
            Row({ space: 9 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
                .fontSize(17)
                .fontColor(['#E84040'])
              Text(this.errorText).layoutWeight(1).fontSize(13).fontColor('#E84040')
            }
              .width('100%')
              .padding(12)
              .backgroundColor('#14E84040')
              .borderRadius(12)
          }
          }
          .width('100%')
          .padding(16)
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
    .title('API Key')
  }
}
