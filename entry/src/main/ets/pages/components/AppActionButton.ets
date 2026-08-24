import { AppButtonRole, AppButtonVisualStyle, appButtonVisualStyle } from '../../common/Theme';

@ComponentV2
export struct AppActionButton {
  @Require @Param title: string;
  @Param role: AppButtonRole = AppButtonRole.Primary;
  @Param isEnabled: boolean = true;
  @Param loading: boolean = false;
  @Param fill: boolean = true;
  @Param compact: boolean = false;
  @Event onPress: () => void = (): void => {};

  build() {
    Button() {
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress()
            .width(this.compact ? 16 : 19)
            .height(this.compact ? 16 : 19)
            .color(appButtonVisualStyle(this.role, this.isEnabled).foregroundColor)
        }
        Text(this.title)
          .fontSize(this.compact ? 13 : 15)
          .fontWeight(this.compact ? FontWeight.Medium : FontWeight.Bold)
          .fontColor(appButtonVisualStyle(this.role, this.isEnabled).foregroundColor)
      }
      .justifyContent(FlexAlign.Center)
    }
    .type(ButtonType.Normal)
    .width(this.fill ? '100%' : 'auto')
    .height(this.compact ? 34 : 48)
    .padding({ left: this.compact ? 14 : 18, right: this.compact ? 14 : 18 })
    .backgroundColor(appButtonVisualStyle(this.role, this.isEnabled).backgroundColor)
    .border({
      width: this.role === AppButtonRole.Plain ? 0 : 1,
      color: appButtonVisualStyle(this.role, this.isEnabled).borderColor
    })
    .borderRadius(this.compact ? 17 : 14)
    .opacity(appButtonVisualStyle(this.role, this.isEnabled).opacity)
    .enabled(this.isEnabled && !this.loading)
    .onClick((): void => this.onPress())
  }
}
