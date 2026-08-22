# bililive 后端 API 契约（鸿蒙客户端实施用）

本文档是鸿蒙客户端需要对接的**全部**后端接口契约，从服务端源码与 iOS 客户端实现中提取。客户端（`net/APIClient.ets`）必须按此实现。

涉及两个服务：

- **主服务** bililive-go-UI：录播、视频库、历史、备份。基地址由用户配置（如 `http://192.168.1.10:8080`）
- **备份源站** bililive-server-update：公网配置备份（可选，如 `https://image.xumy.art`）

## 1. 通用约定

### 1.1 鉴权（仅主服务）

API Key 三种传递方式（优先级从高到低，客户端统一用 **Authorization: Bearer**）：

```
X-API-Key: <key>
Authorization: Bearer <key>
?_key=<key>          ← 仅用于媒体/缩略图等 URL 场景
```

- 是否开启鉴权：`GET /api/auth-status`（免认证）返回 `{"enable_api_key": bool, "api_key": "..."}`。客户端启动/测试连接时可先探测，但 iOS 客户端实际不主动探测，**统一直接带 Bearer 头**（未配置 Key 时不带）
- Key 形态：服务端配置的任意字符串，或 `blgo_` 开头的数据库用户 Key
- 错误响应：401 → `{"err_no":401,"err_msg":"未授权：缺少或无效的 API Key"}`；403 → `{"err_no":403,"err_msg":"无权限：API Key 无效、已禁用或已吊销"}`。客户端收到 401/403 统一抛「未授权」错误（对应 iOS ApiError.unauthorized）

### 1.2 响应包装

- 错误时返回 `{"err_no": <int>, "err_msg": <string>, "data": null}`（commonResp）
- **成功时多数列表/详情端点直接返回裸 JSON 数组或对象**（不包 commonResp）。客户端解析必须按端点区分：能拿到数组/对象就当成功，拿到 `err_no != 0` 的包装则当失败

### 1.3 路径编码（关键）

`relPath` / `folderPath`（如 `抖音/主播A/video.flv`）拼进 URL 路径时必须**逐段百分号编码**（对 `/` 分隔的每段分别 encodeURIComponent），并且：

- 空格及 `[]{}|\^"`<>#%` 等字符必须被编码（iOS 用自定义字符集排除了这些）
- 实现放 `APIClient` 内统一处理：`encodePathSegments(path: string): string`

### 1.4 签名 URL 机制

- 服务端在 `file_url` / `thumbnail_url` / `hls_url` 中直接下发带签名的**相对路径** URL（形如 `/files/xx?expires=1690000000&sig=abc...`），客户端拼上 base URL 即可用，**无需自己计算签名**
- `expires` 是绝对 unix 秒。过期后返回 401「签名已过期」→ 客户端需重新拉取列表（或调 `GET /api/signed-url` 续期）拿新 URL
- 默认 TTL 3600 秒。播放中途过期：播放器报错时重取列表刷新 URL
- 兜底规则：URL 上没有签名参数时，追加 `?_key={apiKey}`（已有 query 用 `&_key=`）

## 2. 主服务端点（全部在 base URL 下）

### 2.1 系统与认证

| 端点 | 方法 | 说明 |
|---|---|---|
| `/api/info` | GET | `{"app_name","app_version","build_time","git_hash","pid","platform","go_version"}`；用于连接测试 |
| `/api/auth-status` | GET | 免认证。`{"enable_api_key":bool,"api_key":"..."}` |
| `/api/auth/me` | GET | 校验当前 Key。200 返回 APIKeyUser：`{"id","name","key_suffix","enabled","created_at","last_used_at","revoked_at"}`；401/403 无效 |

API Key 用户管理（客户端本期不需要，列出备查）：`GET/POST /api/api-keys`（POST body `{"name"}` → 201 返回完整 `api_key`，仅此一次）、`PATCH/DELETE /api/api-keys/{id}`。

### 2.2 直播间

| 端点 | 方法 | 请求 | 响应 |
|---|---|---|---|
| `/api/lives` | GET | — | `LiveInfo[]`（下表） |
| `/api/lives` | POST | **body 是数组** `[{"url":"https://live.douyin.com/xxx","listen":true}]` | 成功添加的 `LiveInfo[]`；单项失败仅记日志不报错。URL 会被服务端自动做短链解析 |
| `/api/lives/{id}` | DELETE | 可选 body `{"delete_files":false}`（true 时连带异步删除该主播录播目录） | `{"err_no":0,"err_msg":"","data":"OK"}` |
| `/api/lives/{id}/start` | GET | — | 最新 `LiveInfo`（开始监听） |
| `/api/lives/{id}/stop` | GET | — | 最新 `LiveInfo`（停止监听） |
| `/api/resolve-url?url=...` | GET | url 需整体 encodeURIComponent | `{"url":"https://live.douyin.com/xxx"}`；400=不支持的平台，502=解析失败 |

`LiveInfo`（与 iOS Models/LiveRoom.swift 一致）：

```json
{"id":"...","live_url":"...","platform_cn_name":"抖音","host_name":"主播名","room_name":"房间名",
 "status":true,"listening":true,"recording":false,"recording_preparing":false,"initializing":false,
 "last_start_time":"...","last_start_time_unix":0,"audio_only":false,"nick_name":"","last_error":"",
 "available_streams":[],"available_streams_updated_at":""}
```

`status` = 是否开播（bool）。id 是服务端内部 ID（URL MD5）。

### 2.3 视频库与文件

| 端点 | 方法 | 响应 |
|---|---|---|
| `/api/video-library` | GET | `VideoRoomInfo[]`，按最新视频倒序；正在直播但无录播的房间返回占位卡（仅 `recording`/`url` 有值） |
| `/api/video-files/{folderPath}` | GET | `VideoFileInfo[]`，mod_time 倒序；folderPath 逐段编码 |
| `/api/thumbnail/{relPath}` | GET | `image/jpeg`（ffmpeg 取第 5 秒帧，宽 320）；无 ffmpeg 时 503 |
| `/api/file/{relPath}` | DELETE | 删除单个文件 |
| `/api/batch/file/delete` | POST | body `{"paths":["a.flv","b.flv"]}`（相对路径数组） |

`VideoRoomInfo`：`{"host_name","platform","folder_path","video_count","total_size","latest_video_at","latest_video","recording","url"}`，**id = folder_path**。

`VideoFileInfo`：

```json
{"name":"xxx.flv","rel_path":"抖音/主播A/xxx.flv","size":123456789,"mod_time":"2026-05-01 12:00:00",
 "file_url":"/files/...?expires=&sig=","thumbnail_url":"/api/thumbnail/...?expires=&sig=",
 "hls_url":"/api/stream/hls/...?expires=&sig=","recording":false,"playback_status":"ready"}
```

- `playback_status` ∈ `ready` | `recording` | `processing` | `unsupported`
- `hls_url` 仅 `.flv/.ts/.mkv` 有值；`file_url` 为直链（MP4/MOV 等）
- 所有 `*_url` 均为**相对路径**，客户端拼 base
- 可原生直拼回退的后缀（iOS `isNativePlayable`）：`.mp4 .m4v .mov .ts`

**播放 URL 决策链**（iOS `APIClient.playbackURL`，必须一致）：

```
hls_url（若非空） > file_url（若非空） > 本地回退：
  isNativePlayable(后缀) → {base}/files/{encodePathSegments(rel_path)}
  否则                    → {base}/api/stream/hls/{encodePathSegments(rel_path)}
所有最终 URL：无签名参数则追加 _key={apiKey}
```

缩略图 URL：`thumbnail_url` 非空直接用，否则 `{base}/api/thumbnail/{encodePathSegments(rel_path)}`；同样应用 `_key` 兜底。

`GET /api/signed-url?kind=file|thumbnail|hls&path=...&expires_in=` → `{"err_no":0,"data":{"url","expires","expires_in"}}`（续期用，客户端可选实现）。

### 2.4 HLS 流

- `/api/stream/hls/{relPath}` → `application/vnd.apple.mpegurl`。服务端实时用 ffmpeg 转封装（`-c copy`），503 = ffmpeg 失败
- m3u8 内分段 URI 已重写为**相对的** `/api/stream/hls-segment/{cache_key}/seg_xxx.ts?expires=&sig=`，播放器以 m3u8 URL 为基准解析即可（AVPlayer 原生支持 HLS）

### 2.5 观看历史（按 Key 用户隔离）

`WatchHistoryEntry`：`{"id":0,"api_key_user_id":"...","video_path":"抖音/主播A/a.flv","video_name":"a.flv","position_seconds":95.2,"duration_seconds":600.0,"updated_at":"2026-05-04 12:00:00"}`

| 端点 | 方法 | 说明 |
|---|---|---|
| `/api/history` | GET | 当前 Key 的全部历史，updated_at 倒序 |
| `/api/history` | POST | 上报进度。body 取 entry 的 `{video_path, video_name, position_seconds, duration_seconds}`（video_path 必填）。UPSERT，键 = 用户 + video_path。响应 `{"err_no":0,"err_msg":"ok"}` |
| `/api/history/{videoPath}` | GET | 单条；**404 = 无记录**；路径逐段编码 |
| `/api/history/{videoPath}` | DELETE | 删除单条 |

### 2.6 配置快照（备份导出用）

`GET /api/config` → 服务端配置 map。客户端只取：`rpc.bind`（如 `:8080`）、`out_put_path`、`app_data_path`、`live_rooms`（`[{"url","is_listening"}]`）。

### 2.7 备份（主服务侧）

| 端点 | 方法 | 说明 |
|---|---|---|
| `/api/backups` | POST | body 即备份包 JSON（§4）。校验：schemaVersion 必须 =1、rpc_bind 可解析、两个路径非空非根、房间 URL 非空。201 返回**裸对象** `{"id":"bgo_YYYYMMDD_8hex","created_at":"RFC3339"}` |
| `/api/backups/{id}` | GET | 返回原始备份包；404 `{"err_no":404,"err_msg":"备份不存在"}` |
| `/api/backups/restore` | POST | body `{"id":"..."}` 或 `{"package":{...内联整包}}` 二选一。同步执行（写配置+应用房间+可能重启）。返回 `{"status":"completed|restarting","job_id":"restore_xxx","message":"..."}` |
| `/api/backups/restore/status/{job_id}` | GET | 同上结构；404 = 任务不存在 |

## 3. 备份源站端点（bililive-server-update）

iOS 客户端只使用 **兼容端点**（v1 bundle 端点本期不用）：

| 端点 | 方法 | 说明 |
|---|---|---|
| `/api/backups` | POST | body 与主服务相同的 iOS 备份包（§4）。201 返回 `{"id":"bgo_YYYYMMDD_13位base32","created_at":"..."}`（仅两字段） |
| `/api/backups/{id}` | GET | 返回原始备份包 |

- 源站**不提供** restore：`POST /api/backups/restore` 固定 405、status 固定 404。**恢复动作必须发给主服务**
- 源站错误格式 `{"error":"...","code":<status>}`；上传 body 字段必须与契约完全一致（服务端严格解码，未知字段可能 400）
- 短 ID 形态：`bgo_` + UTC 日期 `YYYYMMDD` + `_` + 13 位小写 base32（字符集 a-z、2-7）；查询时服务端会强制小写并剥离非法字符

## 4. 备份包 JSON Schema（iOS 兼容，鸿蒙必须逐字段一致）

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-05-04T12:00:00Z",
  "iosConfig": {
    "serverURL": "http://192.168.1.10:8080",
    "lanURL": "http://192.168.1.10:8080",
    "publicURL": "https://live.example.com",
    "autoSwitchNetwork": true
  },
  "server": {
    "rpc_bind": ":8080",
    "out_put_path": "./recordings",
    "app_data_path": ".appdata",
    "live_rooms": [{"url": "https://live.douyin.com/xxx", "is_listening": false}]
  }
}
```

- **鸿蒙端读写都使用 `iosConfig` 字段名与字段集**（互通 iOS 备份；服务端将该对象视为任意 JSON）
- 序列化：pretty-print + **key 排序**；日期 ISO8601（`yyyy-MM-dd'T'HH:mm:ss'Z'`，UTC）
- **绝不包含**：API Key、Cookie、签名 URL、观看历史
- 解析时容忍字段缺失（可选字段置空/默认值）
- 本地导出文件名：`bililive-harmony-backup-{unix秒}.json`

## 5. 客户端行为约定（从 iOS 提取，与端点同等重要）

1. **LAN 探测**：智能网络切换时对 `{lanURL}/api/info` 发 HEAD 请求（带 Bearer），2 秒超时；失败后等 500ms 重试一次；可达 → 用 LAN，否则用公网。只填了一个地址则直接用之。切换后必须重建 APIClient（清 base URL 缓存）
2. **续播拉取**：`GET /api/history/{relPath}`，网络失败时回退拉全量 `/api/history` 后按 video_path 匹配
3. **恢复轮询**：restore 响应含 `job_id` 且 `status ∈ {pending, running, restarting}` 时，每 2 秒查一次 status，最多 20 次（40 秒）；**轮询中收到 404 视为重启完成**（服务重启后内存任务表丢失）；连接失败属预期，继续轮询
4. **上传目标选择**：备份上传优先源站（`appConfig.backupServerURL`），未配置则回落主服务；上传 404/405 → 提示「当前服务器暂不支持备份接口」但保留本地文件
5. 任何页面下拉刷新会触发一次 `refreshNetworkStatus()` 重测网络（仅智能切换模式）
