# TASK-4：播放器完整手势 / 续播 / 进度上报 / 画中画

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md` 与 `TASKS/REPORT-3.md`。

## 前置条件

TASK-0 ~ TASK-3 完成。

## 目标

补齐播放器与 iOS 版逐帧对齐的全部高级能力：横滑快进快退（SeekHUD）、左侧竖滑亮度 / 右侧竖滑音量（HUD）、**长按两侧下拉锁定 2 倍速状态机**、续播三重保护、15 秒进度上报、同步 Toast、播放状态触觉、画中画。

## 必读参考（iOS 源码）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\PlayerView.swift`（重点：PlayerGestureView 手势区、SpeedGestureMode 状态机、applyResumeWhenReady、上报逻辑）
- 纯函数已在 TASK-1 `player/PlayerMath.ets` 实现（seekRangeFor / horizontalSeekTarget / shouldResume / resumeTarget / isSideZone / lockPullSatisfied），**直接调用，不得重复实现**

## 详细规格

### 1. 横向拖动快进快退（对应 iOS 横滑 seek）

- PanGesture 起点：**锁定起始播放时间** + `ProgressTracker.beginInteracting()`（暂停 + 冻结）
- 拖动中：`目标 = PlayerMath.horizontalSeekTarget(锁定起点, deltaX, 屏宽, duration)`，实时同步到时间线显示（不真正 seek）
- 结束：`endInteracting(目标)` → 自动 seek + 恢复播放
- **SeekHUD**：顶部居中显示 `>>` 或 `<<`（按方向）+ `目标时间 / 总时长`（等宽字体，formatClock）；拖动结束淡出
- 判定：横向手势需与竖向手势区分（位移方向判定阈值 ~10vp），未达阈值不进入任何 HUD

### 2. 竖向拖动（左半屏 = 亮度，右半屏 = 音量）

- 公式（两侧相同）：`newValue = clamp(起始值 - deltaY / 200, 0, 1)`（200vp 满量程，向上滑增大）
- **亮度（左侧起手）**：`window.getLastWindow().setWindowBrightness(v)`（窗口亮度，无需权限）
- **音量（右侧起手）**：优先 `audio` 的 VolumeManager.setVolume（STREAM MEDIA）；若该 API 受限或抛错 → **回退 `PlayerController.setVolume(v)`**（仅影响本播放流），并在报告注明采用路径
- HUD：顶部居中、互斥显示——喇叭/太阳图标 + 横向进度条（品牌色填充）；手势结束淡出
- HUD 互斥规则：Seek / 音量 / 亮度三种 HUD 同时最多显示一个

### 3. 长按两侧下拉锁定 2 倍速（四态状态机，最复杂手势）

状态 `SpeedGestureMode ∈ none | locking | unlocking | locked`：

- **长按开始（≥500ms）**：触点在**左右各 28% 侧区**（`PlayerMath.isSideZone`）才生效：
  - 当前未锁定（none/locking）→ 进入 `locking`：立即 `setSpeed(2.0)`（临时加速）、显示 SpeedHUD、隐藏控制栏、轻触觉
  - 当前已锁定（locked/unlocking）→ 进入 `unlocking`：SpeedHUD 换文案
  - 中间区域（72% 中部）长按：忽略
- **长按持续移动**：`PlayerMath.lockPullSatisfied(startY, currentY, screenH)`（真实下拉 ≥30vp **且** 指尖到达屏幕下 1/3）首次满足时触发：
  - `locking` → `locked`（中触觉）：此后松手**保持 2x**
  - `unlocking` → 恢复基础倍速 + 回到 `none`（中触觉）
- **长按结束**：
  - `locking` 未达锁定条件 → 恢复进入前的倍速，回 `none`
  - `locked` / `unlocking`（未达解锁条件）→ 维持 2x，回 `locked`
  - SpeedHUD 延迟 1.2s 淡出
- **SpeedHUD 文案**（底部居中、毛玻璃）：
  - locking：「下拉锁定 2 倍速」（向下箭头）
  - locked：「已锁定 2 倍速」（锁图标）
  - unlocking：「下拉解锁 2 倍速」（开锁图标）
- **倍速菜单显式选择任何速度 → 清除锁定状态**（回 none，基础倍速更新为所选值）
- 单击手势在 SpeedHUD 显示期间不切换控制栏（对应 iOS 忽略规则）
- 手势互斥：横滑/竖滑/长按下拉三种手势互不并发（复用 iOS shouldRecognizeSimultaneously=false 语义）

### 4. 续播（三重保护，逐条实现）

打开播放器、播放器就绪后：

1. 拉取续播点：`getHistoryEntry(rel_path)`；**失败回退** `getHistoryAll()` 后按 video_path 匹配
2. 等待 duration 有效；目标 = `PlayerMath.resumeTarget(position, duration)`
3. **规则**：`PlayerMath.shouldResume(position, duration)` 为 false（片头 ≤5s 或片尾 ≤5s 内）→ 不续播
4. **seek 校验重试**：seek 后读实际位置，误差 <3s 判成功；失败重试，**最多 3 次、每次等待 500ms**；全部失败则不续播（从头播）
5. 成功 → Toast「已从 mm:ss 继续播放」2.2 秒（formatClock）
6. **isResumeSettled 门控**：续播决议（成功应用或确认不续播）之前**禁止任何进度上报**——防止把服务端旧进度覆盖成 0 秒

### 5. 进度上报（对齐 iOS 节奏）

- 播放中每 **15 秒**上报一次；此外：暂停时、每次 seek 完成后、关闭播放器前（onBeforeClose 钩子）
- body：`{video_path: rel_path, video_name: name, position_seconds, duration_seconds}`（`postHistory`）
- 成功后显示同步 Toast「已同步到服务端」（与续播 Toast 复用 Toast 层，不叠加同时只显示一条）
- **未绑定 API Key**：显示一次「未绑定 API Key，无法同步历史」Toast，之后不再上报（也不写本地）
- duration 无效（<1s）时跳过上报

### 6. 画中画（PiP）

- 顶部 PiP 按钮：特性检测可用性（`@kit.PiPKit` PiPWindow，XComponent 场景；API 12+，平板支持以系统能力为准）→ 可用则点击进入 PiP（小窗继续播放），不可用则隐藏按钮或点击 toast「当前设备不支持画中画」
- 关闭播放器时若在 PiP 中，先关闭 PiP
- PiP 期间播放不中断；从 PiP 返回全屏正常恢复

### 7. 触觉与细节

- 播放状态变化（play↔pause）轻触觉（Haptics.light）
- 2x 锁定：长按开始轻触觉，锁定/解锁成功中触觉（Haptics.medium）
- 状态栏：播放页沉浸（隐藏状态栏或全屏沉浸模式，退出恢复）

## 验收标准

- [ ] 横滑 seek：起点锁定（非累加）、屏宽全滑 = seekRangeFor(duration)、HUD 方向与时间显示正确、松手 seek+恢复
- [ ] 左亮右音：公式/ HUD 互斥 / 音量受限时走 avPlayer.volume 回退（报告注明实际采用路径）
- [ ] 2x 锁定状态机四态全部可达：侧区外忽略、未下拉松手恢复、下拉≥30vp 且达下 1/3 才锁定、locked 松手保持 2x、unlocking 下拉解锁恢复、菜单选速解锁；三种 HUD 文案正确
- [ ] 续播：5 秒规则 / clamp / 3 次重试 500ms 间隔 / 误差 3s 判定 / isResumeSettled 门控 / 成功 Toast
- [ ] 上报：15s 周期 + 暂停/seek/关闭三触发点 + 无 Key 时提示一次后不上报
- [ ] PiP：特性检测 + 可用则能进出 + 关页清理；不支持设备优雅降级
- [ ] 单击在 SpeedHUD 显示期间不切控制栏；控制栏隐藏不吞手势（不回归 TASK-3）
- [ ] 退出播放器无定时器/播放器/PiP 泄漏
- [ ] 编译 + 测试全绿；git 提交 `TASK-4: 播放器完整手势`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：手势数值参数（200vp 满量程、28% 侧区、30vp 下拉、下 1/3、500ms、15s、5s、3 次、3s 误差、1.2s 淡出）为 iOS 提取契约，**不得自行调整**。
