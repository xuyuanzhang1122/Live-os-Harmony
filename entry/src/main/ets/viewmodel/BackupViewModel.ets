import { BackupTarget, APIClient } from '../net/APIClient';
import { ApiError, ApiErrorType } from '../model/Common';
import {
  BackupDeviceConfig,
  BackupIdResult,
  BackupPackage,
  RestoreResult
} from '../model/BackupModels';

const RESTORE_POLL_INTERVAL_MS: number = 2000;
const RESTORE_POLL_MAX_ATTEMPTS: number = 20;
const RESTORE_TIMEOUT_TEXT: string = '恢复超时，请手动检查服务器';
const BACKUP_FALLBACK_TEXT: string = '当前服务器暂不支持备份接口，已保留本地文件';

export interface BackupPollDelay {
  wait(milliseconds: number): Promise<void>;
}

class TimerBackupPollDelay implements BackupPollDelay {
  async wait(milliseconds: number): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }
}

class RestoreResultValue implements RestoreResult {
  status: string;
  job_id: string | null;
  message: string | null;

  constructor(status: string, jobId: string | null, message: string | null) {
    this.status = status;
    this.job_id = jobId;
    this.message = message;
  }
}

export class BackupUploadOutcome {
  target: BackupTarget;
  record: BackupIdResult;
  statusText: string;

  constructor(target: BackupTarget, record: BackupIdResult, statusText: string) {
    this.target = target;
    this.record = record;
    this.statusText = statusText;
  }
}

export class BackupRestoreOutcome {
  package: BackupPackage | null;
  result: RestoreResult;
  message: string;

  constructor(pkg: BackupPackage | null, result: RestoreResult, message: string) {
    this.package = pkg;
    this.result = result;
    this.message = message;
  }
}

export function backupFilename(nowMilliseconds: number = Date.now()): string {
  return `bililive-harmony-backup-${Math.floor(nowMilliseconds / 1000)}.json`;
}

export function backupUploadErrorText(error: Object): string {
  if (error instanceof ApiError &&
    (error.type === ApiErrorType.NETWORK || error.statusCode === 404 || error.statusCode === 405)) {
    return BACKUP_FALLBACK_TEXT;
  }
  if (error instanceof Error) {
    return error.message.length > 0 ? error.message : '备份上传失败';
  }
  return `${error}`;
}

export function hasBackupDeviceConfig(pkg: BackupPackage): boolean {
  const serverURL: string = pkg.iosConfig.serverURL ?? '';
  const lanURL: string = pkg.iosConfig.lanURL ?? '';
  const publicURL: string = pkg.iosConfig.publicURL ?? '';
  return serverURL.length > 0 || lanURL.length > 0 || publicURL.length > 0 ||
    (pkg.iosConfig.autoSwitchNetwork ?? false);
}

export function formatBackupExportTime(value: string): string {
  const normalized: string = value ?? '';
  if (normalized.length === 0) {
    return '未知';
  }
  const parsed: number = Date.parse(normalized);
  if (!Number.isFinite(parsed)) {
    return normalized;
  }
  const date: Date = new Date(parsed);
  const pad: (part: number) => string = (part: number): string => part.toString().padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export class BackupExportViewModel {
  private client: APIClient;

  constructor(client: APIClient) {
    this.client = client;
  }

  updateClient(client: APIClient): void {
    this.client = client;
  }

  async buildPackage(device: BackupDeviceConfig, exportedAt?: string): Promise<BackupPackage> {
    const serverConfig: Object = await this.client.getServerConfig();
    return BackupPackage.fromServerConfig(device, serverConfig, exportedAt);
  }

  async uploadPackage(pkg: BackupPackage, backupServerURL: string): Promise<BackupUploadOutcome> {
    const target: BackupTarget = (backupServerURL ?? '').trim().length > 0 ? 'backup' : 'main';
    const record: BackupIdResult = await this.client.uploadBackup(target, pkg);
    const statusText: string = target === 'backup' ? '已上传到备份服务器' :
      '已上传到主服务器（建议配置备份服务器）';
    return new BackupUploadOutcome(target, record, statusText);
  }
}

@ObservedV2
export class BackupRestoreViewModel {
  @Trace isRestoring: boolean = false;
  @Trace progressMessage: string = '';
  private client: APIClient;
  private readonly delay: BackupPollDelay;

  constructor(client: APIClient, delay: BackupPollDelay = new TimerBackupPollDelay()) {
    this.client = client;
    this.delay = delay;
  }

  updateClient(client: APIClient): void {
    this.client = client;
  }

  async restoreById(id: string, hasBackupServer: boolean): Promise<BackupRestoreOutcome> {
    this.beginRestore();
    try {
      const normalizedID: string = id.trim();
      let pkg: BackupPackage | null = null;
      let initial: RestoreResult;
      if (hasBackupServer) {
        pkg = await this.client.fetchBackupPackage('backup', normalizedID);
        initial = await this.client.restoreBackup({ package: pkg });
      } else {
        try {
          pkg = await this.client.fetchBackupPackage('main', normalizedID);
        } catch (_) {
          pkg = null;
        }
        initial = await this.client.restoreBackup({ id: normalizedID });
      }
      return await this.finishRestore(pkg, initial);
    } finally {
      this.isRestoring = false;
    }
  }

  async restorePackage(pkg: BackupPackage): Promise<BackupRestoreOutcome> {
    this.beginRestore();
    try {
      const initial: RestoreResult = await this.client.restoreBackup({ package: pkg });
      return await this.finishRestore(pkg, initial);
    } finally {
      this.isRestoring = false;
    }
  }

  private beginRestore(): void {
    this.isRestoring = true;
    this.progressMessage = '正在提交恢复请求…';
  }

  private async finishRestore(pkg: BackupPackage | null, initial: RestoreResult): Promise<BackupRestoreOutcome> {
    const finalResult: RestoreResult = await this.pollRestoreIfNeeded(initial);
    const finalStatus: string = finalResult.status ?? '';
    if (finalStatus !== 'completed') {
      const failureMessage: string = finalResult.message ?? '';
      throw new Error(failureMessage.length > 0 ? failureMessage : '恢复失败');
    }
    const finalMessage: string = finalResult.message ?? '';
    const initialMessage: string = initial.message ?? '';
    const message: string = finalMessage.length > 0 ? finalMessage :
      (initialMessage.length > 0 ? initialMessage : '恢复完成');
    this.progressMessage = message;
    return new BackupRestoreOutcome(pkg, finalResult, message);
  }

  private async pollRestoreIfNeeded(initial: RestoreResult): Promise<RestoreResult> {
    const initialStatus: string = initial.status ?? '';
    if (initialStatus === 'completed') {
      return initial;
    }
    const jobId: string = initial.job_id ?? '';
    if (!BackupRestoreViewModel.isPollingStatus(initialStatus) || jobId.length === 0) {
      return initial;
    }
    this.progressMessage = initial.message ?? '服务正在恢复…';
    for (let attempt: number = 0; attempt < RESTORE_POLL_MAX_ATTEMPTS; attempt += 1) {
      await this.delay.wait(RESTORE_POLL_INTERVAL_MS);
      let statusResult: RestoreResult | null;
      try {
        statusResult = await this.client.getRestoreStatus(jobId);
      } catch (error) {
        if (error instanceof ApiError && error.type === ApiErrorType.NETWORK) {
          continue;
        }
        throw error instanceof Error ? error : new Error(`${error}`);
      }
      if (statusResult === null) {
        return new RestoreResultValue('completed', jobId, '服务已重启完成');
      }
      const nextMessage: string = statusResult.message ?? '';
      if (nextMessage.length > 0) {
        this.progressMessage = nextMessage;
      }
      const nextStatus: string = statusResult.status ?? '';
      if (nextStatus === 'completed') {
        return statusResult;
      }
      if (!BackupRestoreViewModel.isPollingStatus(nextStatus)) {
        return statusResult;
      }
    }
    throw new Error(RESTORE_TIMEOUT_TEXT);
  }

  private static isPollingStatus(status: string): boolean {
    return status === 'pending' || status === 'running' || status === 'restarting';
  }
}
