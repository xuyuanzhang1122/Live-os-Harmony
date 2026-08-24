import { describe, expect, it } from '@ohos/hypium';
import {
  AppButtonRole,
  AppButtonVisualStyle,
  ConnectionVisualState,
  appButtonVisualStyle,
  settingsConnectionVisualState
} from '../main/ets/common/Theme';

export default function uiRefreshTest(): void {
  describe('iOS-aligned UI presentation rules', (): void => {
    it('keeps primary actions legible and visibly disables unavailable actions', 0, (): void => {
      const active: AppButtonVisualStyle = appButtonVisualStyle(AppButtonRole.Primary, true);
      const disabled: AppButtonVisualStyle = appButtonVisualStyle(AppButtonRole.Primary, false);

      expect(active.backgroundColor).assertEqual('#1FDBC7');
      expect(active.foregroundColor).assertEqual('#063D38');
      expect(active.opacity).assertEqual(1);
      expect(disabled.opacity < active.opacity).assertTrue();
    });

    it('does not let destructive actions inherit the brand treatment', 0, (): void => {
      const primary: AppButtonVisualStyle = appButtonVisualStyle(AppButtonRole.Primary, true);
      const destructive: AppButtonVisualStyle = appButtonVisualStyle(AppButtonRole.Destructive, true);

      expect(destructive.foregroundColor).assertEqual('#E84040');
      expect(destructive.backgroundColor === primary.backgroundColor).assertFalse();
    });

    it('prioritizes loading and failure over the last known network route', 0, (): void => {
      expect(settingsConnectionVisualState(true, true, true, true))
        .assertEqual(ConnectionVisualState.Loading);
      expect(settingsConnectionVisualState(false, true, true, true))
        .assertEqual(ConnectionVisualState.Failure);
      expect(settingsConnectionVisualState(false, false, true, true))
        .assertEqual(ConnectionVisualState.LAN);
      expect(settingsConnectionVisualState(false, false, false, true))
        .assertEqual(ConnectionVisualState.Public);
      expect(settingsConnectionVisualState(false, false, false, false))
        .assertEqual(ConnectionVisualState.Idle);
    });
  });
}
