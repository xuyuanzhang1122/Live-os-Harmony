import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppConfig } from '../config/AppConfig';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    AppConfig.getInstance(this.context);
    hilog.info(DOMAIN, TAG, 'Live OS initialized');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load pages/Index: %{public}s', JSON.stringify(error));
      }
    });
  }

  onForeground(): void {
    // 后台期间网络可能已切换而未收到回调，回前台时重测局域网可达性
    AppConfig.getInstance().refreshNetworkStatus().catch((): void => {});
  }
}
