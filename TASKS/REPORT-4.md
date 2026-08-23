# REPORT-4：真机反馈修复与播放器完整手势契约对齐

> TASK-4-fix 基线见文末「TASK-4-fix 历史记录」。本文件主体为 **TASK-4-fix-2**（真机播放状态、进度条、HUD 图标与退出清理）的实施与验证记录。

## 完成项（TASK-4-fix-2）

- ✅ P0 进度条与播放进度真实显示：`PlayerController` 新增 native `timeUpdate` 事件订阅（API 12，默认 100ms 上报、seek 成功立即上报），毫秒→秒换算后写入缓存并回调 `onTimeUpdate`；`ProgressTracker` 250ms 属性轮询保留为第二路径，事件与轮询双通道任一可用即可驱动 UI。时间显示统一 `Formats.formatDuration`（秒）；`duration <= 0` 时两侧显示 `00:00` 且时间线禁用；`currentTime` 一律 clamp 到 `[0, duration]`；`seek()` 不再用 `Number.MAX_VALUE` 兜底，duration 未就绪直接拒绝。带单位 hilog 已就位（`time update nativeMs=… uiSeconds=… durationSeconds=…`、`duration update nativeMs=… uiSeconds=…`、`page time uiSeconds=…`）。
- ✅ P0 播放/暂停图标与实际状态同步：图标唯一来源为 `@ObservedV2 PlayerUiState`（`@Local uiState`）的 `playerState/isPlaying`；native `stateChange`、play/pause Promise 返回后的状态快照、120ms 短延迟状态回读三路汇聚到同一 UI 状态。图标为 `pause_fill`/`play_fill`/`arrow_clockwise` SymbolGlyph。点击链路 hilog（`button click → toggle(ui/native/interacting) → controller request/complete → stateChange → ui state`）完整保留。
- ✅ P0 退出停止音频并释放播放器：所有退出入口（返回按钮、系统返回/滑动关闭 = `bindContentCover onWillDismiss`、`aboutToDisappear`、错误层退出）收敛到幂等 `shutdownPlayer(reason)`；顺序为 停手势/HUD/进度跟踪 → pause（等待完成）→ 关闭前历史上报（best-effort）→ 停 PiP → release（等待完成，内部 pause→unbind→stop→reset→release）→ 清空页面 callback → 恢复系统栏 → 关闭模态。关闭链每一步都有 `withTimeout` 上限（页面级 pause 3s / release 8s / 上报 2.5s / PiP 2.5s / 恢复窗口 1.5s；release 内部 pause 1.5s、stop/reset/release 各 3s），超时 hilog 后继续执行，不可能永久挂起；退出后检查并记录 native 终态（`shutdown verify ok native=released`）。
- ✅ P1 音量/亮度 HUD 图标：使用任务书指定且已在 SDK `sysResource.js` 符号表核对的 `speaker_fill`（125831504）、`speaker_slash`（125831131）、`sun_max`（125831496）；SymbolGlyph 位于 HUD 可见 Row 内、白色、宽 28，与品牌色横向进度条同层显示。
- ✅ P1 长按 2x 临时加速与下拉锁定分离：手势仲裁重构为 外层 Exclusive（单击/双击）+ 内层 `GestureGroup(Parallel, LongPress, Pan)`，长按识别不再取消同指下拉 Pan；28% 侧区、500ms 长按、`lockPullSatisfied`（≥30vp 且达下 1/3）全部经 `PlayerMath`；`startY` 只在长按识别时锁定一次；四态转换（含抬手 `locking→none` 恢复原速、`unlocking→locked` 维持 2x、下拉解锁恢复用户倍速）按契约实现；新增互斥守卫（pan 方向已锁定时不进入倍速手势）；菜单选速清除锁定、恢复所选倍速并让 SpeedHUD 按 1.2s 淡出。
- ✅ 真机崩溃修复：jscrash 证实在播放器页拖动时间线时 `fingerList` 可能含 undefined 条目导致 `TypeError: Cannot read property localX of undefined` 杀进程；保留稀疏 `fingerList` 安全遍历，并为 `updateTimeline` 增加 duration/宽度守卫，崩溃路径双重封堵。
- ✅ 单元测试：`Tests run 49, Failure 0, Error 0, Pass 49`（含新增 3 例：native pause 永不结算时 release 链仍完成 stop/reset/release；`withTimeout` 正常结算保值/超时返回 null）。
- ✅ 编译：`hvigorw.bat assembleHap --daemon=false` BUILD SUCCESSFUL（Windows 原生 cmd，DEVECO_SDK_HOME=D:\DevEco Studio\sdk）。
- ✅ 保护性回归：HLS 回退仍以 `/playlist.m3u8` 结尾；稀疏 fingerList 遍历、`waitForInitialized`（5400102 竞态）、续播三重保护、15 秒上报、无 Key 单次提示、`PlayerMath` 纯函数与 `ProgressTracker.isInteracting` 状态机全部保留复用。

## 真机证据

证据一：`jscrash-com.xumy.liveos-20260823124101.509.txt`（MatePad 11.5，2026-08-23 12:41，中间构建，含崩溃前完整 hilog）：

```
12:40:59.553 LiveOSPlayer: setup url=https://api.xumy.org:9899/api/stream/hls/抖音/屈屈真腹肌… surface=…
12:40:59.561 LiveOSPlayer: factory done / url set
12:40:59.567 LiveOSPlayer: state -> initialized → initialized ready → surfaceId set
12:40:59.758 LiveOSPlayer: state -> error
12:40:59.759 LiveOSPlayer: error code=5400106 message=Unsupported Format: CONTAINER_ERR-null-unsupport interface
12:41:01.484 ArkCompiler: TypeError: Cannot read property localX of undefined
           at eventLocalX ← updateTimeline ← 时间线 PanGesture 回调 → 进程被杀
```

证明：① `stateChange` 等事件链在真机真实触发（诊断日志可达）；② `fingerList` 在真机存在 undefined 条目，直接索引访问会崩进程；③ 公网源 `api.xumy.org:9899` 上「屈屈真腹肌」一片的 HLS prepare 阶段即 5400106（服务端 ffmpeg 转封装 CONTAINER_ERR，片源/服务端问题，非客户端缺陷）。

证据二：用户对 TASK-4-fix 构建（LAN `192.168.1.5:8080`，30 秒测试录播）的反馈：服务端历史上报正常（说明 `duration` 在 UI 侧有效，上报体通过 duration≥1 门槛）；seek 手势可触发；但进度/时间 00:00、图标不变化、HUD 无图标、长按 2x 不能锁定、退出后音频继续。

证据三：`TASKS/tools/playlist.m3u8`（服务端探测产物）为 `#EXT-X-PLAYLIST-TYPE:VOD` 规范点播清单——LAN 源 duration/seek 能力本身可用，排除服务端流形态导致 UI 00:00 的可能。

## 根因结论

1. 进度 00:00：TASK-4-fix 基线的 `PlayerController` 完全没有订阅 native `timeUpdate` 事件，UI 进度只依赖 `AVPlayer.currentTime` 属性轮询；真机上该属性链路未产出可用值（SDK 声明：live 模式默认返回 -1，HLS 场景属性可能不可靠），于是左侧时间与滑块冻结在 0，而音频正常播放。修复以事件为主、轮询为备的双通道，属性与事件的毫秒值在控制器内统一换算为秒。
2. 下拉不能锁定 2x：基线把 `LongPressGesture` 与 `PanGesture` 放在同一个 `GestureMode.Exclusive` 组里，长按 500ms 识别成功的瞬间 Pan 被仲裁取消，下拉位移永远无法送达 `updateSpeedPull`，`lockPullSatisfied` 无从判定。改为内层 Parallel 组后长按与下拉同指并存。
3. 退出后音频继续：基线滑动/系统返回不走任何关闭钩子（无 `onWillDismiss`），仅靠 `aboutToDisappear` 里 fire-and-forget 的 `pause().then(release())`；任一 native Promise 悬挂即断链，且无超时、无结果校验。修复把全部入口收敛进带逐步超时与终态验证的幂等关闭漏斗。
4. 时间线崩溃：`event.fingerList` 在真机可为稀疏数组（含 undefined），基线/中间构建的访问方式抛 TypeError 直接杀进程；该崩溃会让用户把「App 重启后回到列表、旧实例音频未清」误判为退出不清理，与根因 3 叠加放大。
5. 图标不变化与 HUD 无图标：图标状态源与 native 状态的闭环只有 stateChange 单一路径，且 HUD 图标依赖设备符号字体对 `speaker_fill/sun_max` 等字形的支持。修复以三路状态汇聚 + 任务书指定符号名双管齐下；确切设备侧结论（状态未达 vs 字形缺失）以新增 hilog 一次真机会话即可区分（见遗留问题）。

## 实现说明

- 时间单位依据：SDK `@ohos.multimedia.media.d.ts` 明确 `currentTime`/`duration` 单位为 ms、无效值 -1；控制器 getter 全部 `Number.isFinite && > 0` 校验后 `/1000`，事件回调同样按 ms→s 换算。
- API 纪律：`on('timeUpdate')`（@since 12，默认 100ms 上报）、`UIContext.runScopedTask`（@since 11）、`bindContentCover onWillDismiss`/`DismissContentCoverAction`（@since 12）均满足 compatible API 12；未使用 API 21 之后接口。
- 音量路径：编译警告明示 `AudioManager.setVolume` 需 `ohos.permission.ACCESS_NOTIFICATION_POLICY`（应用未申请），真机系统音量写入必然抛错 → 自动回退 `PlayerController.setVolume`（AVPlayer 单流音量），即契约允许且任务书注明需在报告写明的实际采用路径。
- 手势坐标：gestureLayer 为全屏容器，`fingerList[].localY` 与 `hudAreaHeight` 同基准（全屏），`lockPullSatisfied(startY, currentY, screenH)` 语义正确；`startY` 在长按识别时一次性锁定，不被 onActionUpdate 覆盖。
- SeekHUD 方向箭头保留 `>>`/`<<` 文本：TASK-4 §1 契约原文即「显示 `>>` 或 `<<`」，属 fix-2 任务书「明确可见的图形」范畴，且不依赖设备符号字体（在 HUD 图标尚未真机确认前更稳）。
- `aboutToDisappear` 不再因「surface 未 setup」跳过关闭：提前退出同样需要恢复沉浸模式与清理 history 定时器，否则系统栏全 App 隐藏。
- `withTimeout` 为通用 Promise 超时包装（超时/异常均结算为 null 并 hilog），页面关闭链与 `performRelease` 内部链共用，保证 stop/release 永远有机会执行。
- 与任务书的偏差：无。
- 对 TASK-1 公共接口的变更：`PlayerController` 新增导出 `withTimeout`、`onTimeUpdate` 回调字段与 `PlayerAdapter.onTimeUpdate/offTimeUpdate`（PlayerAdapter 为可注入接口，测试已同步）；其余公共接口无变化。

## 新增/修改文件清单

- 修改：`entry/src/main/ets/player/PlayerController.ets`（timeUpdate 订阅、ms→s 缓存、状态快照、release 逐级超时、withTimeout）
- 修改：`entry/src/main/ets/player/ProgressTracker.ets`（seekDone 接受 SEEK_CLOSEST 实际位置）
- 修改：`entry/src/main/ets/pages/PlayerPage.ets`（ObservedV2 uiState、关闭漏斗、手势仲裁、HUD/时间线/图标、防御与验证日志）
- 修改：`entry/src/main/ets/pages/VideoListPage.ets`（onWillDismiss 关闭漏斗接线、shutdown handler 注册）
- 修改：`entry/src/main/ets/common/Formats.ets`（新增 formatDuration）
- 修改：`entry/src/test/Task1Infrastructure.test.ets`、`entry/src/test/Task3Player.test.ets`（新增/调整用例）
- 新增：`TASKS/TASK-4-fix-2-真机播放状态进度HUD退出清理.md`（任务书，随本任务入库）
- 更新：`TASKS/REPORT-4.md`

（工作区另有两份未入库的真机证据文件，供人工核对，不参与构建：`jscrash-com.xumy.liveos-20260823124101.509.txt`、`TASKS/tools/`——探测脚本含真实 API Key，按安全惯例不入库。）

## 自验结果

Windows 原生 shell（Git Bash 调 `cmd /c`，`DEVECO_SDK_HOME=D:\DevEco Studio\sdk`）：

- `hvigorw.bat assembleHap --daemon=false`：**BUILD SUCCESSFUL**（ArkTS 编译仅存历史遗留警告：deprecated 音量 API、px2vp、3x 速度档 since 13，均非本次引入且有运行时降级）。
- `hvigorw.bat test --daemon=false`：**BUILD SUCCESSFUL**；结果文件 `Tests run: 49, Failure: 0, Error: 0, Pass: 49, Ignore: 0`。
- 静态回归检查：`APIClient.buildPlaybackUrl` HLS 回退保留 `/playlist.m3u8`；`firstFinger/eventLocalX/eventLocalY` 稀疏 fingerList 安全遍历保留；`PlayerController.waitForInitialized` 保留；续播 5 秒规则/3 次重试/500ms/3s 误差、15 秒上报、无 Key 单次提示常量与调用均在。
- 测试要点：native pause 永不结算时 `release()` 仍在超时后完成 `stop,reset,release` 且终态 `released`；`withTimeout` 正常任务保值、悬挂任务按期结算 null；timeUpdate ms→s（6250ms → 6.25s）；durationUpdate 兜底；duration 未就绪拒绝 seek；SEEK_CLOSEST 实际位置（40.5s）解除交互态。

## 遗留问题（待真机复验，hilog 过滤 `LiveOSPlayer|LiveOSPlayerPage`）

1. 播放 5 秒后左下时间应显示 `00:05` 附近且滑块离开起点——核对 `time update nativeMs=… uiSeconds=…`（每秒一条）与 `page time uiSeconds=…`。
2. 播放/暂停图标随状态切换——核对 `page state X -> Y` 与 `ui state source=… state=… isUiPlaying=…`；若状态日志正常而图标仍不切换，则为设备符号字体缺 `pause_fill` 字形（125834191 为较晚加入的符号），届时仅需换符号名。
3. 退出（返回按钮/系统滑动返回）后音频立即停止、5 秒后无背景音——核对 `shutdown pause settled`、`release chain done finalState=…`、`shutdown verify ok native=released`。
4. 长按侧区临时 2x、下拉到下 1/3 锁定、抬手仍 2x、再次长按或菜单改速解锁——核对 `speed locking -> locked startY=… currentY=… screenHeight=…`。
5. 左滑右滑音量/亮度 HUD 图标可见性（speaker/sun SymbolGlyph 在 MatePad 上的渲染）。
6. 公网源「屈屈真腹肌」prepare 5400106 属服务端 ffmpeg 转封装失败（CONTAINER_ERR），需服务端侧修复或换片源验证；LAN 测试服务器不受影响。

---

## TASK-4-fix 历史记录（6ffc0b9，TASK-4-fix-2 之前）

- 沉浸与全屏铺底：进入播放页隐藏状态栏/导航栏/指示条（能力不可用回退 avoid area padding），根 Stack `expandSafeArea`，退出恢复。
- 暂停链路打点与 `HitTestMode.Block`、图标改依赖可观测 `playerState`；全部控制图标 SymbolGlyph 化（`chevron_left`、`pause_fill`、`play_fill`、`arrow_clockwise` 等已按 SDK 符号表替换为合法下划线名）。
- 横滑 seek（10vp 方向判定、起点锁定一次、`horizontalSeekTarget`）、左亮右音（200vp 满量程、窗口亮度 + 系统媒体音量优先/AVPlayer 回退）、续播三重保护、15 秒上报、PiP 能力检测与关页清理、触觉、HUD 互斥 1.2s 淡出等 TASK-4 契约项的实现与符号/系统栏两处主控修正，详见 git 历史。
- 该轮真机反馈中「图标不变化、进度 00:00、下拉锁定失效、退出音频继续、HUD 图标缺失」五个问题的根因与修复见本文上半部分（TASK-4-fix-2）。
