import { Haptics } from '../common/Haptics';
import { AppButtonRole } from '../common/Theme';
import { AppConfig } from '../config/AppConfig';
import { VideoFileInfo } from '../model/VideoLibrary';
import { VideoLibraryPage, VideoListRouteParams } from './VideoLibraryPage';
import { VideoListPage } from './VideoListPage';
import { PlayerPage, PlayerShutdownHandler } from './PlayerPage';
import { AboutPage } from './AboutPage';
import { ApiKeyPage } from './ApiKeyPage';
import { NetworkConfigPage } from './NetworkConfigPage';
import { RestoreBackupPage } from './RestoreBackupPage';
import { RoomListPage } from './RoomListPage';
import { SettingsPage } from './SettingsPage';
import { StorageManagementPage } from './StorageManagementPage';
import { HistoryPage } from './HistoryPage';
import { LaunchDisplayGate } from './components/LaunchRules';
import { LaunchView } from './components/LaunchView';
import { AppActionButton } from './components/AppActionButton';

const LAUNCH_DISPLAY_GATE: LaunchDisplayGate = new LaunchDisplayGate();

@Entry
@ComponentV2
struct Index {
  @Local private selectedTab: number = 0;
  @Local private config: AppConfig = AppConfig.getInstance();
  @Local private videoListVisible: boolean = false;
  @Local private activePlayerFile: VideoFileInfo | null = null;
  @Local private settingsRefreshToken: number = 0;
  @Local private showLaunch: boolean = LAUNCH_DISPLAY_GATE.consume();
  private playerShutdownHandler: PlayerShutdownHandler | null = null;

  private readonly videoLibraryStack: NavPathStack = new NavPathStack();
  private readonly roomListStack: NavPathStack = new NavPathStack();
  private readonly historyStack: NavPathStack = new NavPathStack();
  private readonly settingsStack: NavPathStack = new NavPathStack();

  @Builder
  private tabBar(title: string, index: number, symbol: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([this.selectedTab === index ? '#0D8D81' : $r('sys.color.font_secondary')])
      Text(title)
        .fontSize(11)
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTab === index ? '#0D8D81' : $r('sys.color.font_secondary'))
    }
    .width('92%')
    .height(50)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selectedTab === index ? '#181FDBC7' : Color.Transparent)
    .borderRadius(16)
  }

  @Builder
  private floatingTabBarBackground() {
    Row()
      .width('calc(100% - 24vp)')
      .height(62)
      .margin({ bottom: 8 })
      .backgroundColor($r('app.color.settings_card_background'))
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
      .border({ width: 1, color: $r('app.color.settings_card_border') })
      .borderRadius(22)
      .shadow({ radius: 16, color: $r('app.color.settings_card_shadow'), offsetY: 5 })
  }

  @Builder
  private videoDestinationBuilder(name: string, param: Object) {
    if (name === 'VideoListPage') {
      VideoListPage({
        folderPath: (param as VideoListRouteParams).folderPath,
        hostName: (param as VideoListRouteParams).hostName,
        onVisibilityChange: (visible: boolean): void => {
          this.videoListVisible = visible;
        },
        onPlayFile: (file: VideoFileInfo): void => {
          this.activePlayerFile = file;
        }
      })
    } else {
      NavDestination() {
        Text('页面不存在')
      }
    }
  }

  @Builder
  private settingsDestinationBuilder(name: string, _param: Object) {
    if (name === 'NetworkConfigPage') {
      NetworkConfigPage({
        onSettingsChanged: (): void => {
          this.settingsRefreshToken += 1;
        }
      })
    } else if (name === 'ApiKeyPage') {
      ApiKeyPage({
        onSettingsChanged: (): void => {
          this.settingsRefreshToken += 1;
        }
      })
    } else if (name === 'StorageManagementPage') {
      StorageManagementPage({
        onSettingsChanged: (): void => {
          this.settingsRefreshToken += 1;
        }
      })
    } else if (name === 'AboutPage') {
      AboutPage()
    } else if (name === 'RestoreBackupPage') {
      RestoreBackupPage()
    } else {
      NavDestination() {
        Text('页面不存在')
      }
    }
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
      RoomListPage({
        active: this.selectedTab === 1
      })
    }
    .title('直播间')
    .mode(NavigationMode.Stack)
  }

  @Builder
  private historyTab() {
    Navigation(this.historyStack) {
      HistoryPage({
        active: this.selectedTab === 2,
        onPlayFile: (file: VideoFileInfo): void => {
          this.activePlayerFile = file;
        },
        onOpenSettings: (): void => {
          this.selectedTab = 3;
        }
      })
    }
    .title('观看历史')
    .mode(NavigationMode.Stack)
  }

  @Builder
  private settingsTab() {
    Navigation(this.settingsStack) {
      SettingsPage({
        stack: this.settingsStack,
        active: this.selectedTab === 3,
        refreshToken: this.settingsRefreshToken
      })
    }
    .title('设置')
    .mode(NavigationMode.Stack)
    .navDestination(this.settingsDestinationBuilder)
  }

  @Builder
  private unconfiguredBanner() {
    Row({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
          .fontSize(16)
          .fontColor(['#A85D00'])
      }
      .width(30)
      .height(30)
      .backgroundColor('#FFFFD8A8')
      .borderRadius(10)
      Text('未配置服务器，请前往设置')
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
      AppActionButton({
        title: '去设置',
        role: AppButtonRole.Secondary,
        fill: false,
        compact: true,
        onPress: (): void => {
          this.selectedTab = 3;
        }
      })
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .margin({ top: 12 })
    .backgroundColor($r('app.color.settings_card_background'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .border({ width: 1, color: $r('app.color.settings_card_border') })
    .borderRadius(18)
    .shadow({ radius: 12, color: $r('app.color.settings_card_shadow'), offsetY: 4 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -72 })))
  }

  // 播放器以 if/else 覆盖 Tabs 时，Navigation/NavDestination 整棵树被卸载，系统返回
  // 手势（两侧侧滑/底部返回）找不到可弹出页面会直接退出应用：必须在此消费并走
  // PlayerPage 的关闭漏斗（暂停→上报历史→释放→恢复窗口），回到播放前列表页。
  onBackPress(): boolean {
    if (this.activePlayerFile === null) {
      return false;
    }
    const shutdown: PlayerShutdownHandler | null = this.playerShutdownHandler;
    if (shutdown !== null) {
      shutdown('system back').catch((): void => {});
    }
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.activePlayerFile !== null) {
        PlayerPage({
          file: this.activePlayerFile,
          onClose: (): void => {
            this.activePlayerFile = null;
            this.playerShutdownHandler = null;
          },
          onShutdownReady: (handler: PlayerShutdownHandler | null): void => {
            this.playerShutdownHandler = handler;
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(10)
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          this.floatingTabBarBackground()

          Tabs({
            barPosition: BarPosition.End,
            index: this.selectedTab
          }) {
            TabContent() {
              this.videoLibraryTab()
            }
            .tabBar(this.tabBar('视频库', 0, $r('sys.symbol.video_fill')))

            TabContent() {
              this.roomListTab()
            }
            .tabBar(this.tabBar('直播间', 1, $r('sys.symbol.dot_radiowaves_left_and_right')))

            TabContent() {
              this.historyTab()
            }
            .tabBar(this.tabBar('历史', 2, $r('sys.symbol.clock_fill')))

            TabContent() {
              this.settingsTab()
            }
            .tabBar(this.tabBar('设置', 3, $r('sys.symbol.gearshape_fill')))
          }
          .width('100%')
          .height('100%')
          .barHeight(78)
          .barBackgroundColor(Color.Transparent)
          .divider(null)
          .scrollable(false)
          .onChange((index: number): void => {
            this.selectedTab = index;
            Haptics.selection();
          })
        }
        .width('100%')
        .height('100%')

        if (this.config.activeURL.length === 0) {
          this.unconfiguredBanner()
        }
      }

      if (this.showLaunch) {
        LaunchView({
          onComplete: (): void => {
            this.showLaunch = false;
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .animation({ duration: 300, curve: Curve.EaseOut })
  }
}
