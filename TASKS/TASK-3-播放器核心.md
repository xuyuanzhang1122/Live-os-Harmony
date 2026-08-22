# TASK-3：播放器核心（AVPlayer / 控制层 / 基础手势 / 错误态）

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md` 与 `TASKS/REPORT-2.md`。

## 前置条件

TASK-0 ~ TASK-2 完成。

## 目标

实现可用的全屏播放器：AVPlayer + XComponent 渲染、暗色主题、顶部/底部控制层、自定义时间线（拖动/点按 seek）、倍速菜单、单击切换控制栏、双击播放暂停、错误态与重播层。**TASK-4 再补横滑 seek 手势、音量/亮度手势、2x 锁定、续播与上报、PiP——本任务把扩展点留好。**

## 必读参考（iOS 源码，1090 行，重点读结构）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\PlayerView.swift`
- 播放 URL 决策：`APIClient.buildPlaybackUrl`（TASK-1 已实现，直接调用）
- 鸿蒙播放器官方范式：AVPlayer（`@ohos.multimedia.media`）+ XComponent（SURFACE 模式取 surfaceId 赋给 `avPlayer.surfaceId`）+ 状态机（idle→initialized→prepared→playing→paused→completed→stopped→released）

## 详细规格

### 1. player/PlayerController.ets

封装 AVPlayer 全生命周期，向 UI 暴露回调式接口：

- `setup(url: string, surfaceId: string)`：创建 → url → surfaceId → prepare → play
- `play()/pause()/seek(seconds)/setSpeed(rate: number)/setVolume(0~1)`
- 状态查询：`duration: number`、`currentTime: number`、`state`（映射 AVPlayer 9 态 + error）、`isPlaying`
- 回调：`onStateChange`、`onError(code, msg)`、`onSeekDone`、`onDurationReady`
- `release()`：stop → reset → release，幂等
- 所有 AVPlayer 事件（'stateChange'/'error'/'seekDone'/'durationUpdate'/'speedDone'/'volumeChange'/'bufferingUpdate'）正确解绑

### 2. player/ProgressTracker.ets（本任务建好，TASK-4 深度使用）

- 250ms 定时器读 `currentTime` 推给 UI
- **isInteracting 语义（必须实现，iOS ProgressTracker 同款）**：`beginInteracting()` → 暂停播放并冻结当前显示时间；`endInteracting(targetSeconds)` → `seek(target)`，seekDone 后**恢复播放**（仅当进入交互前正在播放）

### 3. pages/PlayerPage.ets（替换 TASK-2 的占位 cover）

**页面结构（自底向上，对应 iOS 分层）**
1. 黑色背景 + 封面缩略图放大模糊垫底（Image blur 40、透明度 0.4，无封面则纯黑）
2. XComponent（SURFACE 模式，onLoad 拿 surfaceId 后 `PlayerController.setup`），aspect-fit 全屏
3. 暗角：顶部 120vp 黑色渐变 + 底部 160vp 黑色渐变（不拦截触摸）
4. **手势层**：透明全屏组件（本任务实现单击/双击，见 §5；其余手势 TASK-4 加）
5. **HUD 层**（本任务建空容器，TASK-4 填充 Seek/音量/亮度 HUD）
6. **Toast 层**（建空容器 + 单条 toast 能力：底部上方 132vp、毛玻璃胶囊、2.2s 自动消失）
7. 播放结束覆盖层：半透明黑 + 居中圆形重播按钮（毛玻璃圆），点击 → replay（seek 0 + play）
8. **控制层**（显隐切换，见 §4）

**进入方式**：`openPlayer(file: VideoFileInfo)`（TASK-2 已留接口）；播放 URL = `AppConfig.getClient()` 的 `buildPlaybackUrl(base, apiKey, file)`。

### 4. 控制层（显隐 = chromeVisible）

- 顶部：返回按钮（关闭播放器）｜ 文件名 + 副标题（大小，formatBytes）
- 底部：
  - 自定义时间线：`当前时间 | 进度条 | 总时长`（时间用等宽字体 formatClock）
  - 进度条：轨道（缓冲条 40% 白 + 品牌色主进度 + 14vp 圆形拖点）；**命中区域上下外扩 10vp**；`PanGesture(minimumDistance: 0)` 实现点按即跳 + 拖动
  - 拖动语义走 ProgressTracker：drag 开始 `beginInteracting()`（暂停 + 冻结），拖动中实时更新显示位置，结束 `endInteracting(target)`
  - 播放/暂停按钮（状态切换，completed 时显示重播图标）
  - 倍速 Menu：0.5 / 0.75 / 1.0 / 1.25 / 1.5 / 2.0 / 3.0；当前速度打勾；文案 `formatSpeedLabel`（0.50x、1.00x…）；选择即 `setSpeed`（TASK-4 会在此追加「清除 2x 锁定」逻辑）
- 顶部 PiP 按钮位预留（本任务显示但禁用，TASK-4 启用）
- **chromeVisible=false 时控制层完全不吃事件**（`.hitTestBehavior(HitTestMode.None)`，对应 iOS allowsHitTesting(false)）

### 5. 手势（本任务部分）

- **单击**：切换 chromeVisible（true↔false）
- **双击**：播放/暂停切换；若已结束（completed）→ 重播
- 单击必须等双击判定失败才触发（TapGesture count=1 与 count=2 组合或延时判定，任选可靠实现）
- 手势层与控制层互斥：控制层可见时其按钮区域事件不被手势层抢走

### 6. 错误态

- 无播放 URL（rel_path 为空等）或 PlayerController onError → 全屏错误层：
  - `playback_status === 'recording'` → 「正在录制，请稍后」
  - `playback_status === 'processing'` → 「正在处理，请稍后」
  - 其他 → 「视频暂时无法播放」
  - 仅一个「退出」按钮（对应 iOS：错误态只有退出）

### 7. 生命周期

- 关闭播放器：暂停 → `release()` → 关闭 cover（进度保存钩子 `onBeforeClose` 留空实现，TASK-4 填）
- 页面 aboutToDisappear 必须释放定时器与播放器
- 全页强制暗色视觉（黑底、白字）；横竖屏均可（不强制旋转）

## 验收标准

- [ ] 能从视频列表点开视频播放（MP4 直链与 HLS 两种路径都走 buildPlaybackUrl 决策）
- [ ] 播放/暂停/重播可用；AVPlayer 各状态正确流转，退出无泄漏（release 幂等）
- [ ] 自定义时间线：拖动（暂停→冻结→松手 seek→恢复）、点按即跳、缓冲条显示、时间显示正确
- [ ] 倍速菜单 7 档可用，当前档打勾，速度实际生效
- [ ] 单击切换控制栏、双击暂停；控制栏隐藏时不吞手势
- [ ] 错误态三种文案 + 退出按钮；结束重播层可用
- [ ] Toast 容器可用（任意文案 2.2s 消失）；HUD 容器就位
- [ ] ProgressTracker 的 isInteracting 语义实现正确（TASK-4 依赖）
- [ ] 编译 + 已有测试全绿；git 提交 `TASK-3: 播放器核心`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：本任务不做续播/上报/横滑手势/音量亮度/2x 锁定/PiP（TASK-4）；不改 TASK-1 公共接口。
