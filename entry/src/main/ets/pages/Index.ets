import { Haptics } from '../common/Haptics';
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
    .backgroundColor($r('sys.color.comp_background_primary'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .borderRadius(14)
    .shadow({ radius: 10, color: '#24000000', offsetY: 4 })
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
