@ComponentV2
export struct LaunchView {
  @Event onComplete: () => void = (): void => {};
  @Local private browserOffset: number = -500;
  @Local private deviceOffset: number = 500;
  @Local private lightningScaleY: number = 0.01;
  @Local private lightningOpacity: number = 0;
  @Local private flashOpacity: number = 0;
  @Local private titleOpacity: number = 0;
  @Local private screenOpacity: number = 1;
  private timers: number[] = [];
  private completed: boolean = false;

  aboutToAppear(): void {
    this.schedule(0, (): void => {
      this.browserOffset = 0;
      this.deviceOffset = 0;
    });
    this.schedule(380, (): void => {
      this.lightningScaleY = 1;
      this.lightningOpacity = 1;
      this.flashOpacity = 0.25;
    });
    this.schedule(480, (): void => {
      this.flashOpacity = 0;
    });
    this.schedule(540, (): void => {
      this.titleOpacity = 1;
    });
    this.schedule(2100, (): void => {
      this.screenOpacity = 0;
    });
    this.schedule(2300, (): void => this.finish());
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private schedule(delay: number, action: () => void): void {
    const timer: number = setTimeout(action, delay);
    this.timers.push(timer);
  }

  private clearTimers(): void {
    this.timers.forEach((timer: number): void => clearTimeout(timer));
    this.timers = [];
  }

  private finish(): void {
    if (this.completed) {
      return;
    }
    this.completed = true;
    this.clearTimers();
    this.onComplete();
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.background_primary'))

      Column({ space: 38 }) {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.splash_browser'))
            .width(200)
            .objectFit(ImageFit.Contain)
            .translate({ x: this.browserOffset - 44, y: 8 })
            .animation({ duration: 520, curve: Curve.Friction })
          Image($r('app.media.splash_phone'))
            .width(300)
            .objectFit(ImageFit.Contain)
            .translate({ x: this.deviceOffset + 50 })
            .animation({ duration: 520, curve: Curve.Friction })
          Image($r('app.media.splash_lightning'))
            .width(150)
            .objectFit(ImageFit.Contain)
            .translate({ x: 4 })
            .scale({ x: 1, y: this.lightningScaleY, centerX: '50%', centerY: '0%' })
            .opacity(this.lightningOpacity)
            .animation({ duration: 220, curve: Curve.EaseOut })
        }
        .width(310)
        .height(210)

        Column({ space: 8 }) {
          Text('哔哩录播 · 鸿蒙版')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text('录播工具 / bililive')
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_secondary'))
        }
        .opacity(this.titleOpacity)
        .animation({ duration: 320, curve: Curve.EaseIn })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.White)
        .opacity(this.flashOpacity)
        .animation({ duration: this.flashOpacity > 0 ? 100 : 180,
          curve: this.flashOpacity > 0 ? Curve.EaseOut : Curve.EaseIn })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .opacity(this.screenOpacity)
    .animation({ duration: 380, curve: Curve.EaseInOut })
    .hitTestBehavior(HitTestMode.Block)
  }
}
