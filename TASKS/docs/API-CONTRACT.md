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


## 5. 2026-10-03 播放解析与逐项删除补充

本节按当前服务端源码核对；旧列表、备份的裸对象规则不变，不做全局 data 解包。

### 播放解析

`GET /api/playback/resolve/{逐段编码的 relPath}` 使用 Bearer 鉴权，返回 commonResp：

```json
{"err_no":0,"err_msg":"","data":{"status":"ready","protocol":"file","mime_type":"video/mp4","url":"/files/clip.mp4?expires=123&sig=abc"}}
```

- 只接受 `ready / processing / recording / failed`。ready 必须有非空 URL；processing 才继续轮询；recording 和 failed 展示 error 并结束。
- `retry_after_seconds` 缺失或非数字默认 2 秒；有限数字限制在 1–10 秒，允许小数。退出页面必须取消，网络失败或契约错误不能变成无限重试。
- 两端保留 HTTP(S) 绝对 URL；相对地址拼接配置的基地址（保留反向代理子路径）。已有 `expires + sig` 或 `_key` 不再追加 Key；否则使用 `_key` 回退。不得重新生成或覆盖服务端签名。
- 仅 HTTP 405 或标准端点缺失 404（`404 page not found`）允许旧列表地址回退。JSON 文件不存在、401/403、网络失败、未知状态及缺少 data/URL 必须报错。
- 签名过期后的重新解析/续播、端到端超时与真机首帧仍需后续验证；本节不表示已验收。

双端共用服务端仓库 `docs/contracts/playback-resolve-fixtures.json` 的 15 个样例。鸿蒙执行 `node --test TASKS/tests/*.cjs`，iOS 执行 `bash Tests/run-playback-contract.sh`。测试要求三个仓库保持当前同级目录布局。

### 批量删除

`POST /api/batch/file/delete` 请求 `{"paths":["a.flv","b.flv"]}`，返回：

```json
{"err_no":0,"err_msg":"","data":[{"path":"a.flv","success":true,"message":"成功"},{"path":"b.flv","success":false,"message":"正在录制"}]}
```

HTTP 请求成功不代表所有文件删除成功。双端 API 返回逐项结果，ViewModel 只移除本次请求中明确 success 的路径，并同步列表缓存；失败或遗漏的路径继续选中，保留逐项原因，页面报告真实成功数量。非法、重复结果以及请求失败不能修改本地文件列表。iOS 列表缓存键对房间路径中的斜杠与百分号编码，避免相对路径变成缓存子目录。


## 视频库权威统计（2026-10-03 过渡契约）

`GET /api/video-library` 仍返回裸房间数组，原 `total_size` 是服务器核验的字节和。新增可选兼容字段：`total_size_text`（服务器统一十进制展示文本）、`statistics_status`（verified/unavailable/pending）、`statistics_checked_at`（Unix 秒）。两端优先原样显示文本；unavailable 必须显示统计暂不可用，不能展示部分和或旧数字。旧服务器缺字段时，仅把服务器给出的字节值按同一十进制规则展示，不自行累加视频大小。

过渡服务端每次扫描房间普通视频文件，忽略隐藏文件/目录及符号链接；遍历失败不发布部分计数。目录级失败可返回 HTTP 500，客户端即使有缓存也报告刷新失败。响应 Cache-Control: no-store。此过渡实现将在主计划 T2 接入持久录播目录后替换为数据库查询，不作为永久请求扫描方案。当前原始 FLV 和 MP4 若同时存在，会同时占用并计入空间；T2 将单列派生资产统计口径。


## T2 持久目录接管统计

当前 `/api/video-library` 从 SQLite 录播目录查询，HTTP 不遍历媒体目录；服务端启动、30 秒后台核验及录制/pipeline/文件变更事件更新。`statistics_checked_at` 表示该快照最后成功核验时间，不是请求时刻。无目录或首次核验未完成返回 HTTP 503，不退回猜测扫描。核验失败保留旧记录供恢复，但以 unavailable 状态和零计数/大小展示，禁止当作当前值。

`video_count` 为逻辑录播数量，可信 FLV→MP4 关联只计一次；`total_size` 为仍保留的主视频文件字节和，源和主 MP4 同时存在时都占空间。`derived_size` 单列已登记持久派生资产的物理字节，不混入主视频。来源版本改变会使旧派生产物失效；客户端继续直接显示服务端大小文本。
