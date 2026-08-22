# TASK-1：基础设施（数据模型 / 网络层 / 缓存 / 全局配置）

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md`（本任务的直接规格来源）。

## 前置条件

TASK-0 完成（工程可编译）。

## 目标

搭建全部与 UI 无关（或弱相关）的基础设施：数据模型、APIClient 全端点、两级缓存、AppConfig 与智能网络切换、纯函数工具与单元测试。**本任务的质量决定后续所有任务，接口签名必须严格按本文书实现。**

## 必读参考

- `TASKS/docs/API-CONTRACT.md`（全部）
- iOS 对应源码（字段与行为基准）：
  - `D:\...\bililive-ios\Live OS\Live OS\Models\Common.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\Models\LiveRoom.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\Models\VideoLibrary.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\Models\BackupModels.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\Network\APIClient.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\Network\CacheManager.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\Network\ThumbnailCache.swift`
  - `D:\...\bililive-ios\Live OS\Live OS\ViewModels\AppConfig.swift`
  - （`D:\...` 前缀 = `D:\Users\Xumy\Downloads\bili-honmey`，路径含空格需引号）

## 详细规格

### 1. model/（纯数据类，字段名与 iOS JSON 一致）

**Common.ets**
- `ApiError`：枚举或类，含 `unauthorized`（401/403）、`invalidURL`、`network`、`decoding`、`server(Int)`、`unsupported`；每个带中文文案（参照 Common.swift 的文案）
- `APIResponse<T>`：`{err_no, err_msg, data}`（仅用于需要解包装的端点）
- `ServerInfo`：`app_name, app_version, build_time, git_hash, pid, platform, go_version`
- `APIKeyUser`：`id, name, key_suffix, enabled, created_at, last_used_at, revoked_at`（可选字段用可空类型）
- `ResolveURLResult`：`{url}`

**LiveRoom.ets**
- `LiveInfo`：按 API-CONTRACT §2.2 的 JSON 全字段（布尔/数字/字符串可空）
- `AddLiveRequest`：`{url: string, listen: boolean}`

**VideoLibrary.ets**
- `VideoRoomInfo`：全字段；提供 `roomId()` = `folder_path`
- `VideoFileInfo`：全字段；静态/成员方法 `isNativePlayable()`：后缀 ∈ `.mp4 .m4v .mov .ts`（对 `name` 或 `rel_path` 判断，大小写不敏感）
- `PlaybackStatus`：字符串联合类型 `ready | recording | processing | unsupported`

**HistoryEntry.ets**
- `WatchHistoryEntry`：`id, api_key_user_id, video_path, video_name, position_seconds, duration_seconds, updated_at`

**BackupModels.ets**
- `BackupDeviceConfig`（序列化为 `iosConfig` 字段，**字段名不改**）：`serverURL, lanURL, publicURL, autoSwitchNetwork`
- `BackupServerConfig`（序列化为 `server` 字段）：`rpc_bind, out_put_path, app_data_path, live_rooms: BackupLiveRoom[]`
- `BackupLiveRoom`：`{url, is_listening}`
- `BackupPackage`：`{schemaVersion: number =1, exportedAt: string, iosConfig: BackupDeviceConfig, server: BackupServerConfig}`
- `BackupIdResult`：`{id, created_at}`
- `RestoreResult`：`{status, job_id, message}`
- 序列化器：`toJson()` pretty（2 空格缩进）+ **对象 key 字典序**；`exportedAt` 用 UTC ISO8601（`yyyy-MM-dd'T'HH:mm:ss'Z'`）；反序列化容忍缺字段
- 从服务端配置 map 构造：`BackupPackage.fromServerConfig(device: BackupDeviceConfig, cfg: Map/object)`，取 `rpc.bind / out_put_path / app_data_path / live_rooms[{url,is_listening}]`

### 2. net/APIClient.ets（唯一 HTTP 出口）

构造与生命周期：
- `constructor(baseURL: string, apiKey?: string)`；每次请求带 `Authorization: Bearer {key}`（key 空则不带）
- 统一超时 15s；统一错误映射：HTTP 401/403 → `ApiError.unauthorized`；解析失败 → `decoding`；网络失败 → `network`
- 通用 `request<T>(method, path, body?, opts?)`：path 为相对 base 的路径（可含已编码段）；响应先尝试按 T 解析，若解出 `{err_no != 0}` 包装则抛错
- `encodePathSegments(path)`：按 `/` 分段逐段 `encodeURIComponent`（空格与特殊字符全部编码），公开为静态方法供测试

端点方法（签名固定，后续任务按此调用）：

```
getServerInfo(): ServerInfo                      // GET /api/info
getAuthMe(): APIKeyUser                          // GET /api/auth/me
getLives(): LiveInfo[]                           // GET /api/lives
addLives(reqs: AddLiveRequest[]): LiveInfo[]     // POST /api/lives  ⚠ body 是数组
deleteLive(id: string, deleteFiles: boolean)     // DELETE /api/lives/{id}  body {delete_files}
startListen(id): LiveInfo                        // GET /api/lives/{id}/start
stopListen(id): LiveInfo                         // GET /api/lives/{id}/stop
resolveUrl(raw: string): string                  // GET /api/resolve-url?url={enc} → data.url
getVideoLibrary(): VideoRoomInfo[]               // GET /api/video-library
getVideoFiles(folderPath): VideoFileInfo[]       // GET /api/video-files/{encodePathSegments}
getHistoryAll(): WatchHistoryEntry[]             // GET /api/history
getHistoryEntry(videoPath): WatchHistoryEntry|null  // GET /api/history/{enc}，404 → null（不抛错）
postHistory(e: WatchHistoryEntry)                // POST /api/history
deleteHistoryEntry(videoPath)                    // DELETE /api/history/{enc}
deleteFile(relPath)                              // DELETE /api/file/{enc}
batchDeleteFiles(paths: string[])                // POST /api/batch/file/delete  body {paths}
getServerConfig(): object                        // GET /api/config（原始 map）
uploadBackup(target: 'main'|'backup', pkg: BackupPackage): BackupIdResult
   // target=backup 时用 AppConfig 的 backupServerURL 作为 base（构造独立请求），POST /api/backups
fetchBackupPackage(target: 'main'|'backup', id: string): BackupPackage  // GET /api/backups/{id}
restoreBackup(body: RestoreRequestBody): RestoreResult  // POST /api/backups/restore（仅主服务）
getRestoreStatus(jobId): RestoreResult|null      // GET /api/backups/restore/status/{jobId}，404→null
```

URL 构造方法（固定）：

```
static buildThumbnailUrl(base, apiKey, file: VideoFileInfo): string
   // 优先 file.thumbnail_url；否则 /api/thumbnail/{enc}；appendKeyIfUnsigned
static buildPlaybackUrl(base, apiKey, file: VideoFileInfo): string
   // 决策链见 API-CONTRACT §2.3：hls_url > file_url > 后缀回退；appendKeyIfUnsigned
static appendKeyIfUnsigned(url: string, apiKey: string): string
   // 无 expires&sig 签名参数时追加 _key（已有 query 用 & 拼接）
```

### 3. net/ApiCache.ets

- 目录 `cacheDir/api-cache/`；键 = 请求 URL 的 SHA-256 hex；值 = 原始 JSON 字符串 + 写入时间戳
- `get(url): string|null`（TTL 30 分钟，过期返回 null）、`set(url, body)`、`clear()`、`sizeBytes(): number`
- 单例；首次初始化时清理「存在时长 > 2×TTL」的文件（对应 iOS 启动清理）

### 4. cache/ 目录

**LruCache.ets**：泛型内存 LRU（容量按条目数 + 可选字节预算双限制；超出逐出最旧）

**ThumbnailCache.ets**：
- 两级：内存 LruCache（最多 100 张，字节预算 50MB）+ 磁盘 `cacheDir/thumbnails/{sha256(url)}.jpg`
- **会话已加载门控**：URL 本次会话内成功加载过（内存或网络）才允许命中磁盘缓存——保证「手动刷新能拿到新图」（对应 iOS 策略，务必实现）
- `invalidateSession()`：清空会话集合 + 内存 LRU（手动刷新时调用；磁盘文件保留）
- `load(url): Promise<PixelMap|null>`：内存 →（会话内已加载过则）磁盘 → 网络下载（经 APIClient 同鉴权语义：直接 GET url，无签名时已带 `_key`）→ 存两级
- `clearAll()`、`sizeBytes()`（内存+磁盘）

### 5. config/ 目录

**AppConfig.ets**（`@ObservedV2` 单例，`getInstance(context)` 首次传入 UIAbilityContext）：
- 持久化字段（preferences 文件 `config`，变更即写）：`serverURL, lanURL, publicURL, autoSwitchNetwork, backupServerURL`（默认全空/false）
- API Key：Asset Store Kit 存储（alias `api_key`），任何失败回退 preferences（键 `api_key_fallback`）；对外仅 `getApiKey()/setApiKey()/clearApiKey()` 异步接口
- 运行态 `@Trace activeURL: string`（当前生效 base）、`@Trace isOnLAN: boolean`、`@Trace apiKeyBound: boolean`、`@Trace serverInfo: ServerInfo|null`
- `refreshNetworkStatus(): Promise<void>`：按 iOS 逻辑解析 activeURL——
  1. 手动模式（autoSwitchNetwork=false）：activeURL = serverURL
  2. 智能模式：lanURL 与 publicURL 均非空 → LAN 探测（见 NetworkMonitor）定 isOnLAN；只有一个非空 → 直接用它；都空 → activeURL=''
  3. activeURL 变化时清空缓存的 APIClient 实例（下次请求重建）
- `getClient(): APIClient`：基于 activeURL + 当前 key 的惰性单例
- 启动时从持久化恢复 → 执行一次 refreshNetworkStatus

**NetworkMonitor.ets**：
- `@ohos.net.connection` 注册网络变化监听（网络类型变化时回调触发 `refreshNetworkStatus`）
- `probeLanReachable(lanURL, apiKey): Promise<boolean>`：HEAD `{lanURL}/api/info`，2 秒超时，带 Bearer；失败 → 等 500ms 重试一次；任一次成功即 true

### 6. common/Formats.ets 与 player/PlayerMath.ets（纯函数，本任务一并实现并测试）

**Formats.ets**：`formatBytes(n)`（B/KB/MB/GB，1 位小数）、`formatClock(seconds)`（mm:ss 或 h:mm:ss）、`formatSpeedLabel(v)`（`0.50x/0.75x/1.00x/...`，两位小数 + x）、`formatRelativeTime(isoOrDateTime)`（刚刚/N 分钟前/N 小时前/日期）

**PlayerMath.ets**（供 TASK-3/4 使用，先建好并测试）：
- `clamp(v, min, max)`
- `seekRangeFor(durationSeconds: number|null): number`：duration 无效 → 90；否则 `clamp(duration*0.15, 30, 300)`
- `horizontalSeekTarget(startSeconds, deltaX, screenWidth, duration): number`：`start + delta/width * seekRangeFor(duration)`，clamp 到 [0, duration]
- `shouldResume(position, duration): boolean`：`position > 5 && position < duration - 5`（片头片尾 5 秒内不续播）
- `resumeTarget(position, duration): number`：clamp(position, 0, duration-1)
- `isSideZone(x, width): boolean`：`x < width*0.28 || x > width*0.72`
- `lockPullSatisfied(startY, currentY, screenHeight): boolean`：`(currentY - startY) >= 30 && currentY >= screenHeight*2/3`（真实下拉 ≥30vp 且到达下 1/3）

### 7. 单元测试（entry/src/test/，hypium 本地测试）

至少覆盖：
- `encodePathSegments`：中文/空格/`[]{}|\^"#%<>` 字符、多级路径、保留 `/` 分隔
- `buildPlaybackUrl` 决策链全分支：有 hls_url / 仅 file_url / 无 URL 时 mp4 与 flv 后缀回退 / `_key` 追加与不追加（已有签名时不加）
- `buildThumbnailUrl`：有 thumbnail_url / 回退 / _key
- `BackupPackage` 序列化：key 排序、iosConfig 字段名、round-trip、缺字段容忍
- PlayerMath 全部函数边界值（null duration、5 秒边界、30/300 clamp、侧区 28% 边界、下拉 30vp 边界）
- ApiCache 的 TTL 判定（可用注入时钟）

## 验收标准

- [ ] 上述全部文件存在，公共接口签名与任务书一致（主控将逐条比对）
- [ ] `hvigorw.bat assembleHap` 编译通过；`hvigorw.bat test`（或 IDE）单元测试全部通过
- [ ] APIClient 覆盖 API-CONTRACT §2/§3 全部客户端所需端点，无遗漏（api-keys 管理、SSE、signed-url 可不做，但 restore/status、backups 上传下载必须做）
- [ ] `addLives` 请求体是 JSON 数组；`getHistoryEntry` 对 404 返回 null 不抛异常
- [ ] AppConfig 智能切换的 URL 决策与「切换后重建 client」逻辑实现且被单元/逻辑覆盖（probeLan 网络部分允许仅集成验证）
- [ ] ThumbnailCache 的「会话内已加载才命中磁盘」门控存在
- [ ] Asset Store Kit 优先 + preferences 回退的 API Key 存取实现
- [ ] PlayerMath 与 Formats 全部函数存在且有测试
- [ ] git 提交 `TASK-1: 基础设施`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：本任务不写任何页面 UI（Index 占位保持 TASK-0 原样）；不对真实服务器发请求做验证（留待集成）。
