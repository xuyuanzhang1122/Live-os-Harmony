import { describe, expect, it } from '@ohos/hypium';
import { calculateLibraryColumns } from '../main/ets/viewmodel/VideoLibraryViewModel';
import { apiKeySummaryNeedsReload } from '../main/ets/viewmodel/SettingsViewModel';
import { LaunchDisplayGate } from '../main/ets/pages/components/LaunchRules';

export default function task8PolishTest(): void {
  describe('Task8 polish rules', (): void => {
    it('re-reads an early empty API Key summary after binding becomes ready', 0, (): void => {
      expect(apiKeySummaryNeedsReload(false, '未设置')).assertFalse();
      expect(apiKeySummaryNeedsReload(true, '未设置')).assertTrue();
      expect(apiKeySummaryNeedsReload(true, '已配置（••••ceac）')).assertFalse();
    });

    it('keeps the video library between four and five columns on wide layouts', 0, (): void => {
      expect(calculateLibraryColumns(819)).assertEqual(4);
      expect(calculateLibraryColumns(1000)).assertEqual(5);
      expect(calculateLibraryColumns(1600)).assertEqual(5);
    });

    it('shows the brand launch cover only once in one application process', 0, (): void => {
      const gate: LaunchDisplayGate = new LaunchDisplayGate();
      expect(gate.consume()).assertTrue();
      expect(gate.consume()).assertFalse();
      expect(gate.consume()).assertFalse();
    });
  });
}
