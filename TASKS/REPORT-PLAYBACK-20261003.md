# REPORT-PLAYBACK：播放器与解析契约修复

日期：2026-10-03。

## 完成项

- ✅ 播放解析按 commonResp.data 解包，并校验 ready/processing/recording/failed 四种状态；ready 必须提供 URL。
- ✅ resolver 和旧接口列表媒体 URL 共用 APIClient.buildMediaUrl：基地址拼接、已有签名保留、无签名 Key 回退。
- ✅ 旧服务端端点不存在时，surface 已就绪也会启动播放；地址先到或 surface 先到均只启动一次。
- ✅ 鉴权、网络和契约错误明确显示，不会被通用 fallback 吞掉；文件不存在的 JSON 404 与端点缺失的标准 404 区分。
- ✅ processing 的无效轮询值回退 2 秒；有效数字限制在既定 1–10 秒区间。
- ✅ 准备阶段统一完成出口：原生 prepare 返回且 prepared 事件到达才能播放，取消、错误和整体 30 秒期限均能结束等待。
- ✅ 所有原生 Promise 的拒绝均及时处理；晚到结果不再产生游离拒绝或启动已取消的播放。
- ✅ 异步原生错误保留真实 code，并避免 setup catch 二次回报 -1；stateChange(error) 不抢先制造无代码的错误。
- ✅ 所有播放器回调均绑定播放器实例和生命周期 token，旧会话的状态、错误、时间、时长等回调不能污染新会话。
- ✅ 恢复服务端发布包同一提交并发完成且已删源的正例，与不同来源冲突负例同时保留。
- ✅ 修正 HLS 生命周期测试模拟器的启动依赖，保留原 3 秒测试期限，未修改服务端运行逻辑。

## 实现说明

播放器原先把 prepared 等待器与原生 prepare 分成两次 await，导致第一阶段结束前 prepared 拒绝无人处理。现在准备阶段返回不拒绝的 PrepareResult，成功、取消和失败都经同一个完成函数清理计时器与本会话等待器。旧会话晚到的 native 操作结果只作用于已完成的局部状态。

前一次修复只对状态与错误回调做会话检查。新增回归再次发现旧 durationUpdate 能把新会话的 120 秒改成 900 秒，随后将全部回调统一绑定会话身份。

公用 API 仅新增 buildMediaUrl、playbackRetrySeconds、canFallbackPlayback 三个静态方法，保留原方法名称和调用接口。resolvePlayback 的返回类型保持 PlaybackResolveResult，但 ready URL 现已规范化为可播放的绝对地址。

服务端测试原模拟器临时生成 shell 脚本。诊断捕获到部分超时发生在脚本执行第一行启动标记之前，管理器仍在等待真实子进程；改为复用当前测试二进制模拟 ffmpeg/ffprobe，继续走生产启动、参数、清单和 Wait 路径。在 -race 模式下，模拟器默认退出睡眠造成约 1 秒额外延迟，三次调用累计超出 3 秒。测试仅追加 GORACE 的 atexit_sleep_ms=0，不关闭竞态检测，也不延长任务期限。

本轮保留工作区中已有的所有服务端 JIT-HLS 修改和先前客户端修复，不部署、不自动提交。

## 新增/修改文件清单

鸿蒙：

- 修改 entry/src/main/ets/net/APIClient.ets：响应校验、统一 URL、轮询与 fallback 判断。
- 修改 entry/src/main/ets/pages/PlayerPage.ets：共用地址就绪流程和错误显示。
- 修改 entry/src/main/ets/player/PlayerController.ets：准备阶段统一完成与全回调会话隔离。
- 修改 entry/src/test/Task3Player.test.ets：恢复原取消场景，并补晚到拒绝、会话重建、错误顺序测试。
- 新增 entry/src/test/PlaybackContract.test.ets；修改 List.test.ets 注册。
- 新增 TASKS/tests/playback-regression.cjs：执行实际 ETS 源码的 18 项隔离回归。

服务端本轮只修改测试：

- src/pkg/playbackasset/publish_test.go：恢复并加强幂等正例。
- src/servers/hls_lifecycle_test.go：模拟器配置及超时诊断。
- 新增 src/servers/hls_fixture_test.go：受控测试子进程入口。

## 自验结果

- 修改前，源码回归 15 项中 12 项失败；修复后扩展为 18 项全部通过。
- `node --test --test-reporter=tap TASKS/tests/playback-regression.cjs`：18 项通过。可设置 DEVECO_HOME 指向本机 DevEco Contents 目录；仅开发期依赖其现有 TypeScript 编译器，无新增应用运行依赖。
- `DEVECO_HOME=/Applications/DevEco-Studio.app/Contents bash ./hvigorw test --daemon=false`：构建成功；读取实际 Hypium 报告，95 项通过，0 失败/错误。
- HLS 单片、立即失败、部分失败三个场景连续 15 轮，共 45 次通过，原超时不变。
- `go test ./src/servers ./src/pkg/playbackasset -count=3 -timeout=120s`：通过。
- `go test -race ./src/servers ./src/pkg/playbackasset -count=1 -timeout=120s`：通过。
- `make test`：服务端完整测试通过。
- `make dev`：通过。
- `go vet -tags=dev ./src/servers ./src/pkg/playbackasset`：通过。
- Diff 空白与 TODO/FIXME 扫描：通过。

## 遗留问题

- HAP 构建在 SignHap 阶段失败，现有工程签名文件仍使用 Windows 路径；未修改签名材料或安装 HAP。
- 本机未安装 golangci-lint，make lint 无法运行；不能宣称该检查通过。
- 既有三倍速 SDK 13 / 兼容 API 12 警告仍在。
- 本轮是代码与本地回归验证，没有对指定 5.2GB 视频进行修改后真机冷缓存验收。原始播放故障是否彻底消失必须由合法签名的应用与隔离服务器实测确认。
- 永久 MP4/HLS 资产准备、iOS 与鸿蒙的新统一 API 方案仍是后续完整计划的工作，本轮不宣称这些整体改造已完成。
