import { describe, expect, it } from '@ohos/hypium';
import { AppConfig } from '../main/ets/config/AppConfig';
import task1InfrastructureTest from './Task1Infrastructure.test';
import task3PlayerTest from './Task3Player.test';
import task5RoomHistoryTest from './Task5RoomHistory.test';
import task7BackupTest from './Task7Backup.test';
import task8PolishTest from './Task8Polish.test';

export default function listTest(): void {
  describe('Task0Skeleton', (): void => {
    it('initializes one empty AppConfig instance', 0, (): void => {
      const first: AppConfig = AppConfig.getInstance();
      const second: AppConfig = AppConfig.getInstance();
      expect(first === second).assertTrue();
      expect(first.activeURL).assertEqual('');
    });
  });

  task1InfrastructureTest();
  task3PlayerTest();
  task5RoomHistoryTest();
  task7BackupTest();
  task8PolishTest();
}
