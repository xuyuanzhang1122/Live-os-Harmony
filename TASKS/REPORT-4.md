# REPORT-4：真机反馈修复与播放器完整手势契约对齐

## 完成项

- ✅ 沉浸与全屏铺底：播放页进入时通过 `window.getLastWindow()` 隐藏状态栏、导航栏和导航指示条，退出时恢复；失败时读取 SYSTEM avoid area（读取也失败则保守 padding）；根 Stack 使用 `expandSafeArea` 覆盖系统栏上下区域。
- ✅ 暂停/继续链路修复：按钮、页面 `togglePlayback`、Controller `play/pause` 和原有 `stateChange` 均有 hilog 打点；按钮使用 `HitTestMode.Block`，图标只依赖可观测 `playerState`，暂停/继续按 AVPlayer 实际状态执行。
- ✅ 图标修复：返回、播放、暂停、重播以及音量/亮度/锁定 HUD 已改用 `SymbolGlyph`，删除原 emoji 播放控制字符。
- ✅ 横滑 seek：起点只锁定一次，调用 `PlayerMath.horizontalSeekTarget`，10vp 后判定方向；SeekHUD 顶部显示方向与目标/总时长，松手交给既有 `ProgressTracker` seek 并按交互前状态恢复。
- ✅ 左亮右音：严格使用 `startValue - deltaY / 200`；窗口亮度仅作用当前窗口；媒体音量优先系统 AudioManager，受系统策略限制或抛错时回退 `PlayerController.setVolume`。
- ✅ 2x 四态手势：500ms 长按、28% 两侧区、30vp 且到达下 1/3 的下拉条件均直接复用 `PlayerMath`；锁定、解锁、未满足松手、菜单选速清锁和三种 HUD 文案已覆盖。
- ✅ HUD 与触觉：Seek/音量/亮度/速度共用单一 `hudMode`，保证互斥；结束后 1.2 秒淡出；播放/暂停轻触觉，锁定/解锁成功中触觉。
- ✅ 续播保护：单条历史失败后回退全量匹配；使用 5 秒规则和 clamp；最多 3 次 seek、每次等待 500ms、误差小于 3 秒才成功；决议前 `isResumeSettled` 禁止上报；成功文案为「已从 mm:ss 继续播放」。
- ✅ 历史上报：播放中 15 秒周期，以及暂停、seekDone、关闭前触发；duration<1s 跳过；无 API Key 仅提示一次并停止上报；成功 Toast 与续播 Toast 复用单条层。
- ✅ PiP：使用 API 11/12 `PiPWindow` 能力检测，创建 XComponent PiPController、保持播放、处理系统播放按钮，并在关页前停止、解绑；不支持时中文 Toast 降级。
- ✅ 防重入：倍速 Menu 的 `onChange` 使用写入门控，避免程序化 selected 回写再次调用 setSpeed；系统音量异步写入使用递增 token，旧写入不会覆盖新值。
- ✅ 基线能力保留：播放 HLS 回退仍以 `/playlist.m3u8` 结尾；fingerList 仍逐项寻找有效手指；`waitForInitialized` 未回退。
- ❌ 真机复验：hilog 打点已就绪但尚未采集 MatePad 新日志（主控环境亦无设备通道，待人工真机验收）。

- ✅ 编译与单元测试：主控环境代跑通过（见「自验结果」），修正两处编译错误后全绿。

## 实现说明（主控审核补充）

- 主控修正 1（SymbolGlyph 资源名）：实施使用了 iOS 点分风格符号名（如 `sys.symbol.pause.fill`），鸿蒙 `$r()` 仅接受三段式资源名，符号库为下划线风格。已按 SDK `sysResource.js` 符号表逐一替换为合法名：`chevron_left`、`pause_fill`、`play_fill`、`arrow_clockwise`、`speaker_fill`、`sun_max`、`arrow_down`、`lock_open`、`lock_fill`。后续任务引用系统符号时以该符号表为准。
- 主控修正 2（系统栏枚举）：`setWindowSystemBarEnable` 类型仅接受 `'status' | 'navigation'`，恢复时传入的 `'navigationIndicator'` 为非法值（若运行时校验拒绝会导致退出播放页后系统栏不恢复），已移除；导航指示条由 `setImmersiveModeEnabledState(false)` 一并恢复。

- 暂停问题根因判定：控制层此前是全屏 `HitTestMode.Transparent`，底层 Exclusive GestureGroup 仍参与同一触点仲裁；同时图标读取非状态对象 `controller.isPlaying`，不构成稳定的 State V2 UI 数据源。修复后按钮显式 Block，图标读取 `@Local playerState`，而动作守卫读取 AVPlayer 实际 state。新增日志按「button click → page toggle(ui/native/interacting) → controller request/complete → stateChange」完整覆盖验证链；由于本会话不能连接真机，最终设备日志证据仍需补采。
- 音量路径：API 12 的 `AudioVolumeManager` 不公开系统音量写接口，SDK 可用写接口为 `AudioManager.setVolume`；先尝试该系统媒体流接口，普通应用受系统策略限制抛错时自动回退 AVPlayer 单流音量。这是当前 SDK 下最贴近契约的实现。
- 系统栏路径：所用沉浸、系统 Bar、亮度、PiP 和音频接口均为 API 12 或更早；所有可能受设备能力/系统策略影响的调用均使用 try-catch/Promise catch 降级。
- PiP 使用当前 SDK `@kit.ArkUI` 导出的 `PiPWindow`（声明文件 `@ohos.PiPWindow.d.ts`，API 11/12），与任务书所指 PiPKit 为同一系统能力。
- 30 秒测试录播无法满足“片尾外至少 5 秒”之外的长时间周期场景时，仍可验证 15 秒上报一次；服务端无鉴权且客户端未绑定 Key 时按契约不应上报。
- 与任务书的偏差：自动构建、测试和真机日志采集受当前命令执行环境阻塞，尚不能声明验收全绿；因此未提交 git。
- 对 TASK-1 公共接口的任何变更：无。

## 新增/修改文件清单

- 修改：`entry/src/main/ets/pages/PlayerPage.ets`
- 修改：`entry/src/main/ets/player/PlayerController.ets`
- 修改：`entry/src/test/Task1Infrastructure.test.ets`
- 新增：`TASKS/REPORT-4.md`

## 自验结果

主控环境（Git Bash + `DEVECO_SDK_HOME="D:\DevEco Studio\sdk"`）代跑：

- `hvigorw.bat assembleHap --daemon=false`：**BUILD SUCCESSFUL**（修正两处编译错误后：SymbolGlyph 资源名 ×9、系统栏枚举 ×1）
- `hvigorw.bat test --daemon=false`：**BUILD SUCCESSFUL**，单测全部通过，覆盖率报告正常生成（`entry/.test/default/outputs/test/reports/`）
- 静态契约检查：确认 200vp、28%/72%、30vp、下 1/3、500ms、15s、5s、3次、500ms、3s、1.2s 和 2.2s 常量/调用均存在。
- 静态基线检查：`APIClient.buildPlaybackUrl` 的 HLS 回退保留 `/playlist.m3u8`；`firstFinger/eventLocalX/eventLocalY` 共用稀疏 fingerList 安全遍历；`PlayerController.waitForInitialized` 保留。
- 测试契约修正：既有播放 URL 测试期望已同步为 `/playlist.m3u8`，避免回退基线修复。
- 实施会话（pi 执行器受 WSL 阻塞）未能自跑的命令已由主控补齐，见上。

## 遗留问题

- 真机（MatePad）复验待人工执行，验收点：
  1. 进入播放页状态栏/导航条隐藏、顶部不叠字、退出后系统栏恢复（`setWindowSystemBarEnable` 恢复路径已修正，需确认导航指示条由 immersive 恢复覆盖）
  2. 暂停/继续按钮生效（hilog 过滤 `LiveOSPlayerPage|LiveOSPlayer`，证据链：button click → toggle(ui/native/interacting) → controller request/complete → stateChange）
  3. 黑背景铺满、底部无空白带；全部图标为 SymbolGlyph 渲染
  4. 横滑 seek（SeekHUD 顶部 `>>`/`<<`+时间）、左亮右音（200vp 满量程）、长按侧区 2x 四态、单击 SpeedHUD 期间不切控制栏
  5. 续播（进度>5s 重进续播+Toast）、15s 周期上报与服务端历史页可见、无 Key 提示一次
  6. PiP 按钮在平板上的能力检测结果（不支持时应弹 Toast 降级）
- 长按期间手指微移 >10vp 可能触发同组 PanGesture 抢占导致长按取消（Exclusive 组内竞争），真机若复现需调整手势距离参数——属可接受的 iOS 等价行为，暂不处理。
