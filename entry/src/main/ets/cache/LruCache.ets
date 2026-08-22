interface LruEntry<V> {
  value: V;
  bytes: number;
}

export class LruCache<K, V> {
  private readonly capacity: number;
  private readonly byteBudget: number | null;
  private readonly entries: Map<K, LruEntry<V>> = new Map<K, LruEntry<V>>();
  private totalBytes: number = 0;

  constructor(capacity: number, byteBudget: number | null = null) {
    this.capacity = Math.max(0, Math.floor(capacity));
    this.byteBudget = byteBudget === null ? null : Math.max(0, Math.floor(byteBudget));
  }

  get(key: K): V | undefined {
    const entry: LruEntry<V> | undefined = this.entries.get(key);
    if (entry === undefined) {
      return undefined;
    }
    this.entries.delete(key);
    this.entries.set(key, entry);
    return entry.value;
  }

  set(key: K, value: V, bytes: number = 0): void {
    const existing: LruEntry<V> | undefined = this.entries.get(key);
    if (existing !== undefined) {
      this.totalBytes -= existing.bytes;
      this.entries.delete(key);
    }
    const normalizedBytes: number = Math.max(0, Math.floor(bytes));
    const entry: LruEntry<V> = { value: value, bytes: normalizedBytes };
    this.entries.set(key, entry);
    this.totalBytes += normalizedBytes;
    this.evictIfNeeded();
  }

  delete(key: K): boolean {
    const existing: LruEntry<V> | undefined = this.entries.get(key);
    if (existing === undefined) {
      return false;
    }
    this.totalBytes -= existing.bytes;
    return this.entries.delete(key);
  }

  clear(): void {
    this.entries.clear();
    this.totalBytes = 0;
  }

  size(): number {
    return this.entries.size;
  }

  sizeBytes(): number {
    return this.totalBytes;
  }

  private evictIfNeeded(): void {
    while (this.entries.size > this.capacity ||
      (this.byteBudget !== null && this.totalBytes > this.byteBudget)) {
      const first: IteratorResult<K> = this.entries.keys().next();
      if (first.done) {
        return;
      }
      this.delete(first.value);
    }
  }
}
