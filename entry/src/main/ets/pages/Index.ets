import { Haptics } from '../common/Haptics';

@Entry
@ComponentV2
struct Index {
  @Local private selectedTab: number = 0;

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
  private destinationBuilder(name: string, _param: Object) {
    NavDestination() {
      Text(`${name} - 待实现`)
        .fontSize(18)
    }
    .title(name)
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
      this.placeholder('视频库 - 待实现（TASK-2）')
    }
    .title('视频库')
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
  }

  @Builder
  private roomListTab() {
    Navigation(this.roomListStack) {
      this.placeholder('直播间 - 待实现（TASK-5）')
    }
    .title('直播间')
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
  }

  @Builder
  private historyTab() {
    Navigation(this.historyStack) {
      this.placeholder('观看历史 - 待实现（TASK-5）')
    }
    .title('观看历史')
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
  }

  @Builder
  private settingsTab() {
    Navigation(this.settingsStack) {
      this.placeholder('设置 - 待实现（TASK-6）')
    }
    .title('设置')
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
  }

  build() {
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
  }
}
