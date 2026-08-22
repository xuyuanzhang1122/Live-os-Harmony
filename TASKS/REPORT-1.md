# REPORT-1：基础设施

## 完成项

- ✅ 数据模型齐全：`Common`、`LiveRoom`、`VideoLibrary`、`HistoryEntry`、`BackupModels` 已覆盖 TASK-1 与 API-CONTRACT 规定字段、可空值和辅助方法。
- ✅ 备份互通实现：`BackupPackage` 支持 UTC 秒级 ISO8601、2 空格 pretty JSON、对象键字典序、缺字段容忍、round-trip，以及从 object/Map 服务端配置构造。
- ✅ APIClient 全端点完成：任务书固定的 21 个异步端点方法与 4 个 URL/编码静态方法均存在，统一使用 15 秒超时、Bearer 鉴权和错误映射。
- ✅ API 关键语义完成：`addLives` 直接序列化数组请求体；路径逐段编码；历史和恢复状态的 404 返回 null；备份源站使用 `backupServerURL` 且不携带主服务 Bearer。
- ✅ 媒体 URL 决策完成：播放严格采用 `hls_url > file_url > 后缀回退`，缩略图优先服务端 URL，只有同时存在 `expires` 与 `sig` 才视为已签名，否则追加编码后的 `_key`。
- ✅ API JSON 缓存完成：`cacheDir/api-cache` 使用 URL 的 SHA-256 hex 文件名、30 分钟 TTL、启动清理 2 倍 TTL 旧文件，并提供单例、读写、清空和大小统计。
- ✅ 两级缩略图缓存完成：内存 LRU 限制 100 张/50MB，磁盘使用 `thumbnails/{sha256}.jpg`，会话门控、手动会话失效、全清空与内存+磁盘大小统计均已实现。
- ✅ AppConfig 完成：State V2 `@ObservedV2/@Trace/@Monitor` 单例、preferences 即时持久化、Asset Store Kit 优先与 preferences 回退、activeURL 决策和 APIClient 惰性重建均已实现。
- ✅ 智能网络完成：注册系统网络变化，双地址模式以带 Bearer 的 2 秒 HEAD 探测 LAN，失败等待 500ms 后重试一次；并用刷新令牌避免并发探测旧结果覆盖新配置。
- ✅ 纯函数工具完成：Formats、PlayerMath 全部任务书函数和严格边界已实现；28%/72% 侧区边界避免浮点乘法误差。
- ✅ 单元测试通过：16 个 Hypium 用例覆盖 URL 编码/构造、备份序列化与缺字段、所有 PlayerMath 分支、全部 Formats、SHA-256、ApiCache 注入时钟 TTL、LRU、缩略图会话门控及 AppConfig 决策/实际 client 重建。
- ✅ 范围约束满足：未修改 `pages/Index.ets`，未新增 TASK-2 及以后页面、功能或文件，也未对真实服务器发请求。
- ✅ 编译通过：`hvigorw.bat assembleHap --daemon=false` 输出 `TYPE CHECK SUCCESSFUL` 和 `BUILD SUCCESSFUL`。

## 实现说明

- 关键设计决策：缓存文件名使用纯 ArkTS 同步 SHA-256 实现，避免为同步磁盘 API 引入异步散列生命周期，也不增加任何运行时三方依赖；标准向量 `sha256("abc")` 已测试。
- 关键设计决策：备份 JSON 使用按字典序声明并赋值的专用序列化 DTO，再交给 `JSON.stringify(..., null, 2)`；这样在 ArkTS 禁止动态索引对象的约束下仍能稳定输出递归有序键。
- 关键设计决策：`APIClient` 由 AppConfig 注册备份地址提供器，备份目标通过独立 base URL 请求且显式关闭鉴权，既避免 AppConfig/APIClient 模块循环依赖，也保持主服务与源站的鉴权边界。
- 关键设计决策：本机 API 24 声明中 Asset Store 核心 `add/query/remove` 均保留 API 11 重载，所用 TextEncoder/TextDecoder、preferences、HTTP、fs、image、connection 接口均不高于 API 12；所有 Asset Store 调用仍按任务书以 try/catch 降级到 `api_key_fallback`。
- 关键设计决策：API-CONTRACT 的 `VideoFileInfo.mod_time` 示例为日期字符串，而 iOS 与当前服务端源码为 Unix 数字；模型采用 `number | string` 兼容两种实际载荷，行为方法不依赖该字段。`available_streams_updated_at` 同理兼容契约示例和服务端 int64。
- 关键设计决策：AppConfig 启动时初始化两类磁盘缓存、恢复 preferences 与 API Key、启动网络监听，最后执行一次网络状态刷新；网络探测仅在智能模式且 LAN/公网地址都存在时发生。
- 与任务书的偏差：无。
- 对 TASK-1 公共接口的任何变更：无；TASK-0 的无参 `AppConfig.getInstance()` 仍可调用，TASK-1 新增的首次 `context` 参数实现为可选参数以兼容本地纯逻辑测试和既有调用。

## 新增/修改文件清单

- 新增：`entry/src/main/ets/model/Common.ets`
- 新增：`entry/src/main/ets/model/LiveRoom.ets`
- 新增：`entry/src/main/ets/model/VideoLibrary.ets`
- 新增：`entry/src/main/ets/model/HistoryEntry.ets`
- 新增：`entry/src/main/ets/model/BackupModels.ets`
- 新增：`entry/src/main/ets/net/APIClient.ets`
- 新增：`entry/src/main/ets/net/ApiCache.ets`
- 新增：`entry/src/main/ets/cache/LruCache.ets`
- 新增：`entry/src/main/ets/cache/ThumbnailCache.ets`
- 新增：`entry/src/main/ets/common/Sha256.ets`
- 新增：`entry/src/main/ets/config/ApiKeyStore.ets`
- 新增：`entry/src/main/ets/config/NetworkMonitor.ets`
- 新增：`entry/src/main/ets/player/PlayerMath.ets`
- 新增：`entry/src/test/Task1Infrastructure.test.ets`
- 新增：`TASKS/REPORT-1.md`
- 修改：`entry/src/main/ets/common/Formats.ets`
- 修改：`entry/src/main/ets/config/AppConfig.ets`
- 修改：`entry/src/main/ets/entryability/EntryAbility.ets`
- 修改：`entry/src/main/module.json5`
- 修改：`entry/src/test/List.test.ets`

## 自验结果

- `hvigorw.bat assembleHap --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`，`BUILD SUCCESSFUL in 8 s 724 ms`，HAP 打包成功。唯一警告为任务环境预期的 `No signingConfig found for product default`。
- `hvigorw.bat test --daemon=false`：通过；16 个本地测试用例无失败/错误，输出 `BUILD SUCCESSFUL in 8 s 149 ms`，并生成本地测试报告。
- 静态文件检查：13 个任务书必需基础设施文件全部存在。
- APIClient 契约检查：21 个固定端点方法和 4 个固定 URL/编码方法全部存在；`addLives` 为数组 body，两个 404-null 分支均有显式逻辑。
- 范围检查：`git diff -- entry/src/main/ets/pages/Index.ets` 为空；没有 TASK-2 及以后页面实现。
- ArkTS 纪律检查：未使用状态管理 V1 装饰器，未引入 `any`/`unknown`，未增加运行时三方依赖，`git diff --check` 无空白错误。

## 遗留问题

- 按任务书禁止事项未连接真实服务；Bearer、LAN 切换、备份源站和媒体下载需在后续集成任务使用测试服务验证。
- Asset Store Kit、preferences 持久化、网络变化监听、PixelMap 解码和磁盘缓存需在 API 21 真机验证系统能力与生命周期表现。
- HAP 仍为未签名产物，需要用户在 DevEco Studio 中配置自动签名后安装到设备。
