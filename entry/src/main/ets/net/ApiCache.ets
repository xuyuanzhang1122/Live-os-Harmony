import { fileIo as fs } from '@kit.CoreFileKit';
import { sha256Hex } from '../common/Sha256';

export interface CacheClock {
  now(): number;
}

class SystemCacheClock implements CacheClock {
  now(): number {
    return Date.now();
  }
}

interface CacheEnvelope {
  body: string;
  savedAt: number;
}

const TTL_MILLIS: number = 30 * 60 * 1000;

export class ApiCache {
  private static instance: ApiCache | null = null;
  private readonly directory: string;
  private readonly clock: CacheClock;

  constructor(cacheDir: string, clock: CacheClock = new SystemCacheClock()) {
    this.directory = `${cacheDir}/api-cache`;
    this.clock = clock;
    if (cacheDir.length > 0) {
      this.ensureDirectory();
      this.cleanOldFiles();
    }
  }

  static getInstance(cacheDir: string = ''): ApiCache {
    if (ApiCache.instance === null ||
      (cacheDir.length > 0 && ApiCache.instance.directory === '/api-cache')) {
      ApiCache.instance = new ApiCache(cacheDir);
    }
    return ApiCache.instance;
  }

  static isFresh(savedAt: number, clock: CacheClock, ttlMillis: number = TTL_MILLIS): boolean {
    return clock.now() - savedAt <= ttlMillis;
  }

  isFreshTimestamp(savedAt: number): boolean {
    return ApiCache.isFresh(savedAt, this.clock);
  }

  get(url: string): string | null {
    if (this.directory.length === '/api-cache'.length) {
      return null;
    }
    const path: string = this.pathFor(url);
    try {
      const envelope: CacheEnvelope = JSON.parse(fs.readTextSync(path)) as CacheEnvelope;
      if (!this.isFreshTimestamp(envelope.savedAt)) {
        this.remove(path);
        return null;
      }
      return envelope.body;
    } catch (_) {
      return null;
    }
  }

  set(url: string, body: string): void {
    if (this.directory.length === '/api-cache'.length) {
      return;
    }
    const envelope: CacheEnvelope = { body: body, savedAt: this.clock.now() };
    this.writeText(this.pathFor(url), JSON.stringify(envelope));
  }

  clear(): void {
    this.listFiles().forEach((name: string): void => this.remove(`${this.directory}/${name}`));
  }

  sizeBytes(): number {
    let total: number = 0;
    this.listFiles().forEach((name: string): void => {
      try {
        total += fs.statSync(`${this.directory}/${name}`).size;
      } catch (_) {
      }
    });
    return total;
  }

  private pathFor(url: string): string {
    return `${this.directory}/${sha256Hex(url)}.json`;
  }

  private ensureDirectory(): void {
    try {
      fs.mkdirSync(this.directory, true);
    } catch (_) {
    }
  }

  private listFiles(): string[] {
    try {
      return fs.listFileSync(this.directory);
    } catch (_) {
      return [];
    }
  }

  private cleanOldFiles(): void {
    this.listFiles().forEach((name: string): void => {
      const path: string = `${this.directory}/${name}`;
      try {
        const envelope: CacheEnvelope = JSON.parse(fs.readTextSync(path)) as CacheEnvelope;
        if (this.clock.now() - envelope.savedAt > TTL_MILLIS * 2) {
          this.remove(path);
        }
      } catch (_) {
        this.remove(path);
      }
    });
  }

  private writeText(path: string, value: string): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, value);
    } catch (_) {
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private remove(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (_) {
    }
  }
}
