import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { sha256Hex } from '../common/Sha256';
import { LruCache } from './LruCache';

const MEMORY_COUNT_LIMIT: number = 100;
const MEMORY_BYTE_LIMIT: number = 50 * 1024 * 1024;

export class ThumbnailCache {
  private static instance: ThumbnailCache | null = null;
  private readonly directory: string;
  private readonly memory: LruCache<string, image.PixelMap> =
    new LruCache<string, image.PixelMap>(MEMORY_COUNT_LIMIT, MEMORY_BYTE_LIMIT);
  private readonly sessionLoaded: Set<string> = new Set<string>();

  constructor(cacheDir: string = '') {
    this.directory = `${cacheDir}/thumbnails`;
    if (cacheDir.length > 0) {
      try {
        fs.mkdirSync(this.directory, true);
      } catch (_) {
      }
    }
  }

  static getInstance(cacheDir: string = ''): ThumbnailCache {
    if (ThumbnailCache.instance === null ||
      (cacheDir.length > 0 && ThumbnailCache.instance.directory === '/thumbnails')) {
      ThumbnailCache.instance = new ThumbnailCache(cacheDir);
    }
    return ThumbnailCache.instance;
  }

  static canUseDisk(url: string, sessionLoaded: Set<string>): boolean {
    return sessionLoaded.has(url);
  }

  async load(url: string): Promise<image.PixelMap | null> {
    const memoryValue: image.PixelMap | undefined = this.memory.get(url);
    if (memoryValue !== undefined) {
      this.sessionLoaded.add(url);
      return memoryValue;
    }
    if (ThumbnailCache.canUseDisk(url, this.sessionLoaded)) {
      const diskValue: image.PixelMap | null = await this.loadDisk(url);
      if (diskValue !== null) {
        this.memory.set(url, diskValue, diskValue.getPixelBytesNumber());
        return diskValue;
      }
    }
    const response: ArrayBuffer | null = await this.download(url);
    if (response === null) {
      return null;
    }
    try {
      const source: image.ImageSource = image.createImageSource(response);
      const pixelMap: image.PixelMap = await source.createPixelMap();
      this.memory.set(url, pixelMap, pixelMap.getPixelBytesNumber());
      this.sessionLoaded.add(url);
      this.writeBuffer(this.pathFor(url), response);
      return pixelMap;
    } catch (_) {
      return null;
    }
  }

  invalidateSession(): void {
    this.sessionLoaded.clear();
    this.memory.clear();
  }

  clearAll(): void {
    this.invalidateSession();
    this.listFiles().forEach((name: string): void => {
      try {
        fs.unlinkSync(`${this.directory}/${name}`);
      } catch (_) {
      }
    });
  }

  sizeBytes(): number {
    let diskBytes: number = 0;
    this.listFiles().forEach((name: string): void => {
      try {
        diskBytes += fs.statSync(`${this.directory}/${name}`).size;
      } catch (_) {
      }
    });
    return this.memory.sizeBytes() + diskBytes;
  }

  private pathFor(url: string): string {
    return `${this.directory}/${sha256Hex(url)}.jpg`;
  }

  private async loadDisk(url: string): Promise<image.PixelMap | null> {
    const buffer: ArrayBuffer | null = this.readBuffer(this.pathFor(url));
    if (buffer === null) {
      return null;
    }
    try {
      return await image.createImageSource(buffer).createPixelMap();
    } catch (_) {
      return null;
    }
  }

  private async download(url: string): Promise<ArrayBuffer | null> {
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 15000,
      connectTimeout: 15000,
      usingCache: false
    };
    try {
      const response: http.HttpResponse = await request.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 400 || !(response.result instanceof ArrayBuffer)) {
        return null;
      }
      return response.result;
    } catch (_) {
      return null;
    } finally {
      request.destroy();
    }
  }

  private readBuffer(path: string): ArrayBuffer | null {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(file.fd).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      return buffer;
    } catch (_) {
      return null;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  private writeBuffer(path: string, buffer: ArrayBuffer): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buffer);
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

  private listFiles(): string[] {
    if (this.directory.length === '/thumbnails'.length) {
      return [];
    }
    try {
      return fs.listFileSync(this.directory);
    } catch (_) {
      return [];
    }
  }
}
