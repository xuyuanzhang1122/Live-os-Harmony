import { image } from '@kit.ImageKit';
import { ThumbnailCache } from '../../cache/ThumbnailCache';

@ComponentV2
export struct CachedThumbnail {
  @Param url: string = '';
  @Param emptyText: string = '';
  @Param generation: number = 0;
  @Local private pixelMap: image.PixelMap | null = null;
  @Local private loading: boolean = false;
  private loadToken: number = 0;

  aboutToAppear(): void {
    this.load().catch((): void => {});
  }

  @Monitor('url', 'generation')
  onURLChanged(_monitor: IMonitor): void {
    this.load().catch((): void => {});
  }

  private async load(): Promise<void> {
    const token: number = this.loadToken + 1;
    this.loadToken = token;
    const requestedURL: string = this.url;
    this.pixelMap = null;
    if (requestedURL.length === 0) {
      this.loading = false;
      return;
    }
    this.loading = true;
    const result: image.PixelMap | null = await ThumbnailCache.getInstance().load(requestedURL);
    if (token !== this.loadToken || requestedURL !== this.url) {
      return;
    }
    this.pixelMap = result;
    this.loading = false;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: [['#343A40', 0.0], ['#20242A', 1.0]]
        })

      if (this.pixelMap !== null) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.loading) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#B8C0CC')
      } else {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.video'))
            .fontSize(30)
            .fontColor(['#AAB2BD'])
          if (this.emptyText.length > 0) {
            Text(this.emptyText)
              .fontSize(12)
              .fontColor('#D6DBE2')
          }
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}
