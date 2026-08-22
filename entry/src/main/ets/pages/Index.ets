import { Haptics } from '../common/Haptics';
import { AppConfig } from '../config/AppConfig';
import { VideoLibraryPage, VideoListRouteParams } from './VideoLibraryPage';
import { VideoListPage } from './VideoListPage';

@Entry
@ComponentV2
struct Index {
  @Local private selectedTab: number = 0;
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private videoListVisible: boolean = false;

  private readonly videoLibraryStack: NavPathStack = new NavPathStack();
  private readonly roomListStack: NavPathStack = new NavPathStack();
  private readonly historyStack: NavPathStack = new NavPathStack();
  private readonly settingsStack: NavPathStack = new NavPathStack();

  @Builder
  private tabBar(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTab === index ? $r('app.color.brand_color') : $r('sys.color.font_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private videoDestinationBuilder(name: string, param: Object) {
    if (name === 'VideoListPage') {
      VideoListPage({
        folderPath: (param as VideoListRouteParams).folderPath,
        hostName: (param as VideoListRouteParams).hostName,
        onVisibilityChange: (visible: boolean): void => {
          this.videoListVisible = visible;
        }
      })
    } else {
      NavDestination() {
        Text('页面不存在')
      }
    }
  }

  @Builder
  private placeholderDestinationBuilder(name: string, _param: Object) {
    NavDestination() {
      Text(`${name} - 待实现`).fontSize(18)
    }.title(name)
  }

  @Builder
  private placeholder(text: string) {
    Column() {
      Text(text)
        .fontSize(18)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private videoLibraryTab() {
    Navigation(this.videoLibraryStack) {
      VideoLibraryPage({
        stack: this.videoLibraryStack,
        active: this.selectedTab === 0 && !this.videoListVisible
      })
    }
    .title('视频库')
    .mode(NavigationMode.Stack)
    .navDestination(this.videoDestinationBuilder)
  }

  @Builder
  private roomListTab() {
    Navigation(this.roomListStack) {
      this.placeholder('直播间 - 待实现（TASK-5）')
    }
    .title('直播间')
    .mode(NavigationMode.Stack)
    .navDestination(this.placeholderDestinationBuilder)
  }

  @Builder
  private historyTab() {
    Navigation(this.historyStack) {
      this.placeholder('观看历史 - 待实现（TASK-5）')
    }
    .title('观看历史')
    .mode(NavigationMode.Stack)
    .navDestination(this.placeholderDestinationBuilder)
  }

  @Builder
  private settingsTab() {
    Navigation(this.settingsStack) {
      this.placeholder('设置 - 待实现（TASK-6）')
    }
    .title('设置')
    .mode(NavigationMode.Stack)
    .navDestination(this.placeholderDestinationBuilder)
  }

  @Builder
  private unconfiguredBanner() {
    Row({ space: 10 }) {
      Text('!')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#A85D00')
        .width(26)
        .height(26)
        .textAlign(TextAlign.Center)
        .backgroundColor('#FFFFD8A8')
        .borderRadius(13)
      Text('未配置服务器，请前往设置')
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
      Button('去设置')
        .type(ButtonType.Normal)
        .fontSize(13)
        .fontColor($r('app.color.brand_color'))
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.selectedTab = 3;
        })
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .margin({ top: 12 })
    .backgroundColor('#CCFFFFFF')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .borderRadius(14)
    .shadow({ radius: 10, color: '#24000000', offsetY: 4 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -72 })))
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Tabs({
        barPosition: BarPosition.End,
        index: this.selectedTab
      }) {
        TabContent() {
          this.videoLibraryTab()
        }
        .tabBar(this.tabBar('视频库', 0))

        TabContent() {
          this.roomListTab()
        }
        .tabBar(this.tabBar('直播间', 1))

        TabContent() {
          this.historyTab()
        }
        .tabBar(this.tabBar('历史', 2))

        TabContent() {
          this.settingsTab()
        }
        .tabBar(this.tabBar('设置', 3))
      }
      .width('100%')
      .height('100%')
      .barHeight(56)
      .onChange((index: number): void => {
        this.selectedTab = index;
        Haptics.selection();
      })

      if (this.config.activeURL.length === 0) {
        this.unconfiguredBanner()
      }
    }
    .width('100%')
    .height('100%')
    .animation({ duration: 300, curve: Curve.EaseOut })
  }
}
