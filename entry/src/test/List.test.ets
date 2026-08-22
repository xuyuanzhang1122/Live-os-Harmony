import { describe, expect, it } from '@ohos/hypium';
import { AppConfig } from '../main/ets/config/AppConfig';

export default function listTest(): void {
  describe('Task0Skeleton', (): void => {
    it('initializes one empty AppConfig instance', 0, (): void => {
      const first: AppConfig = AppConfig.getInstance();
      const second: AppConfig = AppConfig.getInstance();
      expect(first === second).assertTrue();
      expect(first.activeURL).assertEqual('');
    });
  });
}
