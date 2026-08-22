import vibrator from '@ohos.vibrator';

export class Haptics {
  static light(): void {
    Haptics.vibrate(10);
  }

  static medium(): void {
    Haptics.vibrate(20);
  }

  static selection(): void {
    Haptics.vibrate(8);
  }

  private static vibrate(duration: number): void {
    try {
      vibrator.startVibration(
        {
          type: 'time',
          duration: duration
        },
        {
          usage: 'touch'
        }
      ).catch((): void => {
      });
    } catch (_error) {
    }
  }
}
