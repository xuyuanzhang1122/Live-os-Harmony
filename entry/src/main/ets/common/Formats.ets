export class Formats {
  static formatBytes(value: number): string {
    const safe: number = Number.isFinite(value) && value > 0 ? value : 0;
    const units: string[] = ['B', 'KB', 'MB', 'GB'];
    let amount: number = safe;
    let unitIndex: number = 0;
    while (amount >= 1024 && unitIndex < units.length - 1) {
      amount /= 1024;
      unitIndex += 1;
    }
    return `${amount.toFixed(1)} ${units[unitIndex]}`;
  }

  static formatClock(seconds: number): string {
    const total: number = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
    const hours: number = Math.floor(total / 3600);
    const minutes: number = Math.floor((total % 3600) / 60);
    const secs: number = total % 60;
    const mm: string = minutes.toString().padStart(2, '0');
    const ss: string = secs.toString().padStart(2, '0');
    return hours > 0 ? `${hours}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  static formatDuration(seconds: number): string {
    return Formats.formatClock(seconds);
  }

  static formatSpeedLabel(value: number): string {
    const safe: number = Number.isFinite(value) ? value : 1;
    return `${safe.toFixed(2)}x`;
  }

  static formatRelativeTime(isoOrDateTime: string, nowMillis: number = Date.now()): string {
    const normalized: string = isoOrDateTime.replace(' ', 'T');
    const timestamp: number = Date.parse(normalized);
    if (!Number.isFinite(timestamp)) {
      return isoOrDateTime;
    }
    const elapsedSeconds: number = Math.max(0, Math.floor((nowMillis - timestamp) / 1000));
    if (elapsedSeconds < 60) {
      return '刚刚';
    }
    if (elapsedSeconds < 3600) {
      return `${Math.floor(elapsedSeconds / 60)} 分钟前`;
    }
    if (elapsedSeconds < 86400) {
      return `${Math.floor(elapsedSeconds / 3600)} 小时前`;
    }
    const date: Date = new Date(timestamp);
    const year: string = date.getFullYear().toString();
    const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
    const day: string = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}

export function formatBytes(value: number): string {
  return Formats.formatBytes(value);
}

export function formatClock(seconds: number): string {
  return Formats.formatClock(seconds);
}

export function formatDuration(seconds: number): string {
  return Formats.formatDuration(seconds);
}

export function formatSpeedLabel(value: number): string {
  return Formats.formatSpeedLabel(value);
}

export function formatRelativeTime(isoOrDateTime: string, nowMillis: number = Date.now()): string {
  return Formats.formatRelativeTime(isoOrDateTime, nowMillis);
}
