import { describe, expect, it } from '@ohos/hypium';
import { ApiError } from '../main/ets/model/Common';
import {
  BackupDeviceConfig,
  BackupIdResult,
  BackupPackage,
  RestoreRequestBody,
  RestoreResult
} from '../main/ets/model/BackupModels';
import { APIClient, BackupTarget } from '../main/ets/net/APIClient';
import {
  BackupExportViewModel,
  BackupPollDelay,
  BackupRestoreOutcome,
  BackupRestoreViewModel,
  backupFilename,
  backupUploadErrorText,
  formatBackupExportTime,
  hasBackupDeviceConfig
} from '../main/ets/viewmodel/BackupViewModel';

class ImmediatePollDelay implements BackupPollDelay {
  waits: number[] = [];

  async wait(milliseconds: number): Promise<void> {
    this.waits.push(milliseconds);
  }
}

class FakeBackupClient extends APIClient {
  fetchTargets: BackupTarget[] = [];
  uploadTargets: BackupTarget[] = [];
  restoreBodies: RestoreRequestBody[] = [];
  statusCalls: number = 0;
  failMainFetch: boolean = false;
  alwaysFailStatusWithNetwork: boolean = false;
  serverConfig: Object = new Map<string, Object>();
  statusValues: Array<RestoreResult | null | Error> = [];
  initialResult: RestoreResult = {
    status: 'completed',
    job_id: null,
    message: '配置已恢复'
  };
  packageValue: BackupPackage = BackupPackage.fromJson('{"schemaVersion":1,' +
    '"exportedAt":"2026-05-04T12:00:00Z","iosConfig":{"serverURL":"http://main",' +
    '"lanURL":"http://lan","publicURL":"https://public","autoSwitchNetwork":true},' +
    '"server":{"rpc_bind":":8080","out_put_path":"./recordings","app_data_path":".appdata",' +
    '"live_rooms":[]}}');

  constructor() {
    super('http://main');
  }

  async getServerConfig(): Promise<Object> {
    return this.serverConfig;
  }

  async uploadBackup(target: BackupTarget, _pkg: BackupPackage): Promise<BackupIdResult> {
    this.uploadTargets.push(target);
    return { id: `id-${target}`, created_at: null };
  }

  async fetchBackupPackage(target: BackupTarget, _id: string): Promise<BackupPackage> {
    this.fetchTargets.push(target);
    if (target === 'main' && this.failMainFetch) {
      throw ApiError.server(404, '备份不存在');
    }
    return this.packageValue;
  }

  async restoreBackup(body: RestoreRequestBody): Promise<RestoreResult> {
    this.restoreBodies.push(body);
    return this.initialResult;
  }

  async getRestoreStatus(_jobId: string): Promise<RestoreResult | null> {
    this.statusCalls += 1;
    if (this.alwaysFailStatusWithNetwork) {
      throw ApiError.network('服务重启中');
    }
    const next: RestoreResult | null | Error | undefined = this.statusValues.shift();
    if (next instanceof Error) {
      throw next;
    }
    return next ?? null;
  }
}

export default function task7BackupTest(): void {
  describe('Task7 backup export', (): void => {
    it('builds omitted server fields defensively and selects both upload targets', 0,
      async (): Promise<void> => {
        const client: FakeBackupClient = new FakeBackupClient();
        client.serverConfig = JSON.parse('{"rpc":{},"live_rooms":[{}],"api_key":"secret",' +
          '"cookie":"secret","history":[{"video":"private"}]}') as Object;
        const viewModel: BackupExportViewModel = new BackupExportViewModel(client);
        const pkg: BackupPackage = await viewModel.buildPackage(
          new BackupDeviceConfig('http://main', '', '', false), '2026-05-04T12:00:00Z');
        expect(pkg.server.rpc_bind).assertEqual('');
        expect(pkg.server.out_put_path).assertEqual('');
        expect(pkg.server.live_rooms[0].url).assertEqual('');
        expect(pkg.toJson().indexOf('secret')).assertEqual(-1);
        expect((await viewModel.uploadPackage(pkg, 'https://backup.example')).target).assertEqual('backup');
        expect((await viewModel.uploadPackage(pkg, '  ')).target).assertEqual('main');
        expect(client.uploadTargets.join(',')).assertEqual('backup,main');
      });

    it('uses the exact filename and shared local-file fallback copy', 0, (): void => {
      expect(backupFilename(1777896000123)).assertEqual('bililive-harmony-backup-1777896000.json');
      expect(backupUploadErrorText(ApiError.server(404, '不存在')))
        .assertEqual('当前服务器暂不支持备份接口，已保留本地文件');
      expect(backupUploadErrorText(ApiError.server(405, '不允许')))
        .assertEqual('当前服务器暂不支持备份接口，已保留本地文件');
      expect(backupUploadErrorText(ApiError.network('离线')))
        .assertEqual('当前服务器暂不支持备份接口，已保留本地文件');
    });

    it('formats preview time and only shows a non-empty iOS device configuration', 0, (): void => {
      expect(formatBackupExportTime('2026-05-04T12:00:00Z').length > 0).assertTrue();
      expect(formatBackupExportTime('')).assertEqual('未知');
      expect(hasBackupDeviceConfig(BackupPackage.fromJson('{"iosConfig":{}}'))).assertFalse();
      expect(hasBackupDeviceConfig(BackupPackage.fromJson('{"iosConfig":{"lanURL":"http://lan"}}')))
        .assertTrue();
    });
  });

  describe('Task7 backup restore', (): void => {
    it('fetches from the backup server and restores the inline package on the main server', 0,
      async (): Promise<void> => {
        const client: FakeBackupClient = new FakeBackupClient();
        const viewModel: BackupRestoreViewModel = new BackupRestoreViewModel(client, new ImmediatePollDelay());
        const outcome: BackupRestoreOutcome = await viewModel.restoreById('bgo_source', true);
        expect(client.fetchTargets.join(',')).assertEqual('backup');
        expect(client.restoreBodies.length).assertEqual(1);
        expect(client.restoreBodies[0].id).assertUndefined();
        expect(client.restoreBodies[0].package === client.packageValue).assertTrue();
        expect(outcome.package === client.packageValue).assertTrue();
      });

    it('continues ID restore when the optional main-server package prefetch fails', 0,
      async (): Promise<void> => {
        const client: FakeBackupClient = new FakeBackupClient();
        client.failMainFetch = true;
        const viewModel: BackupRestoreViewModel = new BackupRestoreViewModel(client, new ImmediatePollDelay());
        const outcome: BackupRestoreOutcome = await viewModel.restoreById('bgo_main', false);
        expect(client.fetchTargets.join(',')).assertEqual('main');
        expect(client.restoreBodies.length).assertEqual(1);
        expect(client.restoreBodies[0].id).assertEqual('bgo_main');
        expect(client.restoreBodies[0].package).assertUndefined();
        expect(outcome.package).assertNull();
      });

    it('treats a missing status job as restart completion after one two-second wait', 0,
      async (): Promise<void> => {
        const client: FakeBackupClient = new FakeBackupClient();
        const delay: ImmediatePollDelay = new ImmediatePollDelay();
        client.initialResult = { status: 'restarting', job_id: 'restore_1', message: '正在重启' };
        client.statusValues = [null];
        const viewModel: BackupRestoreViewModel = new BackupRestoreViewModel(client, delay);
        const outcome: BackupRestoreOutcome = await viewModel.restorePackage(client.packageValue);
        expect(delay.waits.join(',')).assertEqual('2000');
        expect(client.statusCalls).assertEqual(1);
        expect(outcome.result.status).assertEqual('completed');
        expect(outcome.message).assertEqual('服务已重启完成');
      });

    it('continues polling after a connection failure and uses the completed server message', 0,
      async (): Promise<void> => {
        const client: FakeBackupClient = new FakeBackupClient();
        const delay: ImmediatePollDelay = new ImmediatePollDelay();
        client.initialResult = JSON.parse('{"status":"running","job_id":"restore_2"}') as RestoreResult;
        client.statusValues = [
          ApiError.network('连接失败'),
          JSON.parse('{"status":"completed","message":"服务已恢复"}') as RestoreResult
        ];
        const viewModel: BackupRestoreViewModel = new BackupRestoreViewModel(client, delay);
        const outcome: BackupRestoreOutcome = await viewModel.restorePackage(client.packageValue);
        expect(delay.waits.join(',')).assertEqual('2000,2000');
        expect(client.statusCalls).assertEqual(2);
        expect(outcome.message).assertEqual('服务已恢复');
      });

    it('stops after exactly twenty two-second polls and reports the fixed timeout copy', 0,
      async (): Promise<void> => {
        const client: FakeBackupClient = new FakeBackupClient();
        const delay: ImmediatePollDelay = new ImmediatePollDelay();
        client.initialResult = { status: 'pending', job_id: 'restore_3', message: '等待中' };
        client.alwaysFailStatusWithNetwork = true;
        const viewModel: BackupRestoreViewModel = new BackupRestoreViewModel(client, delay);
        let errorText: string = '';
        try {
          await viewModel.restorePackage(client.packageValue);
        } catch (error) {
          errorText = error instanceof Error ? error.message : `${error}`;
        }
        expect(delay.waits.length).assertEqual(20);
        expect(delay.waits.every((value: number): boolean => value === 2000)).assertTrue();
        expect(client.statusCalls).assertEqual(20);
        expect(errorText).assertEqual('恢复超时，请手动检查服务器');
      });
  });

  describe('Task7 iOS backup compatibility', (): void => {
    it('parses a full iOS backup JSON fixture with the exact shared field names', 0, (): void => {
      const pkg: BackupPackage = BackupPackage.fromJson('{"schemaVersion":1,' +
        '"exportedAt":"2026-05-04T12:00:00Z","iosConfig":{' +
        '"serverURL":"http://192.168.1.10:8080","lanURL":"http://192.168.1.10:8080",' +
        '"publicURL":"https://live.example.com","autoSwitchNetwork":true},' +
        '"server":{"rpc_bind":":8080","out_put_path":"./recordings","app_data_path":".appdata",' +
        '"live_rooms":[{"url":"https://live.douyin.com/123","is_listening":false}]}}');
      expect(pkg.iosConfig.publicURL).assertEqual('https://live.example.com');
      expect(pkg.server.rpc_bind).assertEqual(':8080');
      expect(pkg.server.live_rooms[0].is_listening).assertFalse();
    });

    it('parses a minimal iOS backup JSON fixture without leaking undefined', 0, (): void => {
      const pkg: BackupPackage = BackupPackage.fromJson('{"schemaVersion":1,"iosConfig":{},"server":{}}');
      expect(pkg.exportedAt).assertEqual('');
      expect(pkg.iosConfig.serverURL).assertEqual('');
      expect(pkg.iosConfig.autoSwitchNetwork).assertFalse();
      expect(pkg.server.rpc_bind).assertEqual('');
      expect(pkg.server.live_rooms.length).assertEqual(0);
    });
  });
}
