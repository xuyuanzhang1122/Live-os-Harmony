# TASK-4-fix-2：真机播放状态、进度条、HUD 图标与退出清理

> 角色：实施工程师（Claude/Codex）。只执行本任务书，不要让主控代写代码。
> 完成后必须写/更新 `TASKS/REPORT-4.md`，并在自验通过后提交：
> `TASK-4-fix-2: 修复真机播放状态、进度条、HUD 与退出清理`

## 开工前必读

按顺序阅读：

1. `TASKS/docs/CONVENTIONS.md`
2. `TASKS/docs/API-CONTRACT.md`（§5）
3. `TASKS/REPORT-1.md`
4. `TASKS/REPORT-3.md`
5. `TASKS/TASK-4-播放器完整手势.md`
6. `TASKS/TASK-4-fix-真机反馈修复与契约对齐.md`
7. `TASKS/REPORT-4.md`

## 当前真机反馈（MatePad 11.5）

以下是安装 `TASK-4-fix` 后的真实结果：

- 服务端历史进度上报正常。
- 横向 seek 手势可以触发，但底部进度条始终显示 `00:00`，进度条没有可见进度。
- 播放/暂停按钮图标不随状态变化；之前报告声称使用 `playerState`，但真机仍看不到变化。
- 音量/亮度 HUD 没有图标。
- 长按加速可以触发，但不能锁定 2 倍速；需要区分“长按临时加速”和“下拉锁定”。
- 由于没有有效进度条，无法判断是否重播或播放完成。
- 从滑动手势/播放页退出后，音频仍然继续播放，说明退出清理没有形成可靠的 pause → release 闭环。

## 目标

只修复上述真机反馈，不实施 TASK-5（直播间与历史）及以后的功能。

---

## P0：进度条与播放进度必须真实显示

### 现象

页面左下时间和右下总时长都显示 `00:00`，滑块始终在最左端；seek 手势实际可用但 UI 不反映进度。

### 必查链路

从 native AVPlayer 到 UI 逐层打点/验证：

1. `PlayerController.currentTime` 的单位。确认 Harmony AVPlayer 的 `currentTime` 是毫秒还是秒，不能只凭类型猜测。
2. `PlayerController.duration` 的单位和触发时机。
3. `PlayerController.onTimeUpdate` 是否真实注册并触发。检查是否在 `setup()` 完成后注册，是否在 `release()` 前取消。
4. `ProgressTracker.start()` 是否启动了轮询，`source.currentTime` / `source.duration` / `source.isPlaying` 是否有效。
5. `PlayerPage` 的 `this.currentTime`、`this.duration` 是否在 ArkUI @Local 状态中更新。
6. 进度条组件的 `value`、`total`、`onChange` 是否采用正确单位和取值范围。

### 修复要求

- 页面显示时间必须使用秒：`Formats.formatDuration(currentTime)` 与 `Formats.formatDuration(duration)`。
- 进度滑块取值范围必须是 `[0, duration]`，且 duration 未就绪时禁用，不得用 `Number.MAX_VALUE` 作为 UI total。
- `duration <= 0` 时显示 `00:00 / 00:00` 并禁用滑块；duration 就绪后立即刷新。
- `currentTime` 必须 clamp 到 `[0, duration]`，避免 seek 到末尾时超过总时长。
- seek 过程中 UI 应即时反映目标位置；`seekDone` 后以 native 实际位置回写。
- 必须保留 TASK-4 的 ProgressTracker / isInteracting 防重入设计，不得另造一套计时器状态机。
- 对 `currentTime`、`duration`、`onTimeUpdate` 增加带单位的 hilog，例如：
  - `time update nativeMs=... uiSeconds=... durationSeconds=...`
  - `duration update nativeMs=... uiSeconds=...`

### 验收

- 播放 5 秒后，左侧时间至少显示 `00:05` 附近，滑块明显离开起点。
- seek 到中间后，滑块移动到中间，左侧时间变化。
- 播放结束后显示接近总时长，进入 completed 状态并能重播。

---

## P0：播放/暂停图标与实际状态同步

### 现象

真机看到按钮图标没有变化，说明 UI 状态没有跟 AVPlayer 真实状态形成可靠闭环。

### 必查链路

1. 记录按钮点击时的 `playerState`、`controller.state`、native player state。
2. 记录 `controller.play()` / `controller.pause()` 调用前后状态，以及 native `stateChange` 回调。
3. 检查 `PlayerState` 字符串值是否完全一致：`prepared`、`playing`、`paused`、`completed`（注意 `complete`/`completed` 混用风险）。
4. 检查按钮 `SymbolGlyph` 是否在 ArkUI 中能根据 @Local 状态重新构建；不要依赖闭包捕获的旧值。
5. 检查 `onStateChange` 是否在页面 `aboutToDisappear` 后仍写 UI，避免旧 callback 干扰。

### 修复要求

- 以一个明确的、可观察的 `@Local isUiPlaying: boolean` 或严格一致的 `@Local playerState` 作为图标唯一来源。
- native `stateChange`、play/pause Promise 成功返回、必要时的短延迟状态回读，必须最终汇聚到同一 UI 状态。
- `playing` 显示 `pause_fill`；`paused/prepared` 显示 `play_fill`；`completed` 显示 `arrow_clockwise`。
- 不得通过 emoji、Text 字符绘制播放图标。
- 点击按钮不能被 gestureLayer/透明全屏层抢占；按钮区域必须可点击。
- 报告中必须写明真机 hilog 的根因证据，不接受“猜测是状态不同步”。

### 验收

- 播放中显示暂停图标。
- 点暂停后画面和进度停止，图标变播放。
- 点继续后画面和进度恢复，图标变暂停。
- 播放完成显示重播图标，点后从 0 播放。

---

## P0：退出播放页必须停止音频并释放播放器

### 现象

滑动手势退出/关闭播放页后，音频仍然继续播放。

### 必查链路

1. 确认关闭入口是否都走同一个 `closePlayer()`：返回按钮、系统返回、播放完成返回、模态关闭回调。
2. 确认 `aboutToDisappear()` 是否触发，以及是否可能在 `bindContentCover` 关闭前被取消。
3. 当前实现中的：
   - `tracker.stop()`
   - `controller.pause()`
   - `controller.release()`
   是异步链，必须确认 pause 完成后才 release，并记录每一步结果。
4. 检查 `PlayerController.release()` 是否解绑所有 native listener、取消轮询/定时器、清理 surface、将 state 置为 released。
5. 检查旧播放器实例是否可能被新的 `setup()` 生命周期 token 放过，造成后台继续播放。

### 修复要求

- 实现一个幂等的 `shutdownPlayer(reason: string): Promise<void>`，所有退出入口只调用它或调用最终会触发它的唯一路径。
- 顺序必须是：停止手势/进度跟踪 → pause 并等待完成 → release 并等待完成 → 清空页面 callback/引用 → 恢复系统栏 → 关闭模态。
- 使用 `shutdownStarted`/生命周期 token 防止重复关闭和旧回调复活播放器。
- pause/release 失败必须 hilog，但不能阻塞页面关闭；要保证 best-effort release。
- 页面退出后再次检查 native state，不能仍为 `playing`。

### 验收

- 播放中点击返回，音频立即停止。
- 播放中执行系统返回/滑动返回，音频立即停止。
- 退出后等待 5 秒，后台无音频继续播放、无进度上报定时器持续运行。
- 再次打开另一个视频，不会同时听到旧视频声音。

---

## P1：音量/亮度 HUD 必须有图标

### 现象

滑动调节音量/亮度时，HUD 有数值或进度，但没有喇叭/太阳图标。

### 修复要求

- 不使用 emoji 或普通 Text 代替图标。
- 音量 HUD 使用已在 SDK 符号表确认存在的：`$r('sys.symbol.speaker_fill')`；音量为 0 可使用 `speaker_slash`。
- 亮度 HUD 使用已确认存在的：`$r('sys.symbol.sun_max')`。
- SymbolGlyph 必须实际放在 HUD Builder 的可见 Column/Row 中，设置白色或品牌色，尺寸不为 0，不能被透明度/条件分支隐藏。
- SeekHUD 的方向箭头也必须是 SymbolGlyph 或明确可见的图形，不得使用不可见/非法资源。

### 验收

- 左侧竖滑看到太阳图标。
- 右侧竖滑看到喇叭图标。
- 图标和横向进度条同时可见。

---

## P1：长按 2 倍速临时状态与下拉锁定分离

### 当前现象

长按加速可以用，但不能锁定 2 倍速。

### 契约状态机（不得改数值）

- 侧区：左 28% 或右 28%。
- 长按：500ms。
- 下拉锁定：手指向下累计至少 30vp，且当前位置到达屏幕下 1/3，调用 `lockPullSatisfied(startY, currentY, screenHeight)`。
- `none → locking`：侧区长按识别。
- `locking → locked`：满足下拉条件后锁定 2x，触觉反馈 + SpeedHUD「已锁定 2x」。
- `locking → none`：抬手但未满足下拉，恢复原速。
- `locked → unlocking`：再次侧区长按或菜单选择其他倍速。
- `unlocking → none`：抬手，恢复用户选择倍速。

### 必查点

1. `LongPressGesture` 与 `PanGesture` 是否在同一 `GestureGroup` 中互相取消。
2. PanGesture 的起始坐标是否在 LongPressGesture 的 side zone 内。
3. `startY` 是否是长按开始位置，而不是每次 onActionUpdate 被覆盖。
4. `currentY` 是否以屏幕坐标而不是局部错误坐标计算。
5. `speedGestureMode` 绑定的是 `@Local` 状态，HUD 是否据此刷新。
6. 抬手事件是否真的执行 `locking → none` 或 `locked → unlocking`，不能只靠 timeout。

### 修复要求

- 修复手势仲裁，使同一侧的 LongPress + 下拉 Pan 能协同工作；控制层按钮区域仍不能被手势层抢占。
- 长按临时 2x 与下拉锁定 2x 必须分别验证：
  - 仅长按不下拉：播放期间 2x，抬手后恢复原速。
  - 长按并下拉到下 1/3：保持 2x，抬手后仍 2x，显示锁定状态。
- 解锁后恢复用户在倍速菜单中选择的倍速，而不是硬编码 1x。

### 验收

- 仅长按：临时 2x，抬手恢复。
- 长按下拉：锁定 2x，抬手仍 2x。
- 再次长按或菜单改速：解锁，状态 HUD 消失，倍速正确恢复。

---

## 保护性回归检查

不得回退：

- HLS 播放地址以 `/playlist.m3u8` 结尾。
- 稀疏 `fingerList` 的安全遍历，不能重新使用固定索引访问。
- `waitForInitialized` 的 5400102 竞态修复。
- 续播、15 秒历史上报、无 Key 单次提示。
- `PlayerMath` 纯函数和 `ProgressTracker.isInteracting` 状态机必须继续复用。

## 自验要求

必须在 Windows 原生 shell 执行，不要经过 WSL/pi 包装：

```bat
cd /d D:\Users\Xumy\Downloads\bili-honmey\bililive-harmony
set DEVECO_SDK_HOME=D:\DevEco Studio\sdk
cmd /c "hvigorw.bat assembleHap --daemon=false"
cmd /c "hvigorw.bat test --daemon=false"
```

必须得到：

- `BUILD SUCCESSFUL`
- 单元测试任务成功
- 更新 `TASKS/REPORT-4.md`：列出真机证据、根因、改动、命令结果、遗留问题
- git 提交指定 commit message

## 禁止事项

- 不改 `bililive-go-UI`、`bililive-ios`。
- 不实施 TASK-5 及以后任务。
- 不伪造真机日志、构建结果或测试结果。
- 不把“服务端历史上报正常”当作播放器 UI/生命周期已经正常。
