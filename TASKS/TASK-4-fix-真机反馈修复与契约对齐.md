# TASK-4-fix：真机反馈修复 + TASK-4 契约对齐

> 角色：实施工程师（Codex）。开工前必读（按顺序）：
> 1. `TASKS\docs\CONVENTIONS.md`（含 API 使用纪律）
> 2. `TASKS\docs\API-CONTRACT.md`（§5 客户端行为约定）
> 3. `TASKS\REPORT-1.md`、`TASKS\REPORT-3.md`
> 4. **`TASKS\TASK-4-播放器完整手势.md`（本修复的契约本体，其全部规格与验收标准在本任务中持续有效）**

## 背景

TASK-3 完成后经历两轮真机联调，工作区已积累一批改动并由主控提交为基线 `404e142`（未经 TASK-4 验收）：其中包含两处真机修复（勿回退，见下）与一轮**偏离契约的 TASK-4 预实现**。真机（MatePad 11.5，2456×1600）截图验收又暴露 3 个 UI 缺陷。

本任务 = **修复 3 个真机问题 + 把预实现对齐 TASK-4 契约并补齐缺失功能**，一次性达到 TASK-4 验收标准。

## 一、真机截图反馈（三问题，全部必修）

### 1. 播放页顶部标题行与系统状态栏重叠
- 现象：`bindContentCover` 全屏模态打开后，顶栏（‹ 返回 + 标题 + 画中画）与系统状态栏（时间/电量）叠字。
- 契约依据：TASK-4 §7「状态栏：播放页沉浸（隐藏状态栏或全屏沉浸模式，退出恢复）」——此条此前未实施。
- 修复规格：进入播放页时**隐藏系统状态栏与导航指示条**（`window.getLastWindow()` + 系统 Bar 控制接口；注意 CONVENTIONS API 纪律：>API 12 的接口必须 `canIUse`/try-catch 特性检测），退出播放页时恢复。能力不可用时**回退避让方案**：根布局用 avoid area 实测高度做顶部 padding，并在报告注明采用路径。

### 2. 暂停/继续按钮点击无效
- 现象：底部圆形播放/暂停按钮点击后，播放行为与图标均无变化。
- 排查要求（**必须给出验证依据，禁止盲改**）：
  1. `togglePlayback()` 与按钮 onClick 加 hilog 打点，确认真机点击是否到达（排除 `gestureLayer` 全屏手势——含双击/单击 GestureGroup 与预实现的 PanGesture(distance 12)——在手势仲裁中抢占按钮事件）；
  2. 检查按钮 `.enabled()` 门控与 `playerState` 实际取值（onStateChange 打点）；
  3. 检查 `PlayerController.pause()/play()` 状态守卫与 AVPlayer 真实状态是否一致（含 HUD 拖动 seek 后状态是否卡住）。
- 修复标准：暂停后画面与时间轴停走、图标切换为播放；继续后恢复。根因结论写入 REPORT-4。

### 3. 按钮使用 emoji 字符 + 页面底部约半指宽空白带
- 图标规格（CONVENTIONS §7「图标优先 SymbolGlyph，资源必须真实存在可编译」）：
  - `‹` → `$r('sys.symbol.chevron.left')`
  - `❚❚` → `$r('sys.symbol.pause.fill')`；`▶` → `$r('sys.symbol.play.fill')`
  - `↻`（重播）→ `$r('sys.symbol.arrow.clockwise')`
  - HUD 喇叭/太阳/锁等图标在实现 HUD 时一并 SymbolGlyph 化
- 底部空白：与问题 1 同源（模态内容未延伸到系统栏下方）。根 Stack（`PlayerPage.build()` 最外层）加 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])` 使背景铺满整屏；同时底部控制栏 padding 计入导航指示条高度（若问题 1 采用"隐藏指示条"路径且成功，则无需额外 padding，报告注明）。

## 二、基线中已就绪的能力（勿回退、勿重做）

- `APIClient.buildPlaybackUrl`：HLS 地址以 `/playlist.m3u8` 结尾——服务端 v2.0.2-rc1 的配套契约，**禁止改回**。
- `PlayerPage.eventLocalX`：遍历稀疏 fingerList——修复多指触摸 JS 崩溃，**保留防崩结构**。
- PlayerController 的 `waitForInitialized`（5400102 竞态修复，历史提交）。
- 真机联调服务端：`http://192.168.1.5:8080`（无鉴权），视频库有测试录播「抖音/测试主播」（30 秒，可验证 seek/暂停/续播/上报全链路）。

## 三、预实现与 TASK-4 契约的已知偏差（以 TASK-4 任务书为准逐项对齐）

1. **续播**：现为「0.95 阈值 + 单次 seek + Toast」。缺：失败回退 `getHistoryAll()` 按 video_path 匹配；改用 `PlayerMath.shouldResume / resumeTarget`（5 秒规则）；seek 校验 3 次×500ms 重试、误差 <3s 判定；`isResumeSettled` 门控（决议前禁止任何上报）；成功 Toast 文案「已从 mm:ss 继续播放」。
2. **进度上报**：现仅关闭时上报。补：播放中每 15 秒；暂停时、每次 seek 完成后两个触发点；未绑定 API Key 时提示一次「未绑定 API Key，无法同步历史」后不再上报；同步 Toast「已同步到服务端」与续播 Toast 复用同一 Toast 层、互斥不叠加；duration<1s 跳过。
3. **HUD 形态**：现为中央浮层。改为 TASK-4 §1/§2/§3 规格：SeekHUD 顶部居中（`>>`/`<<` + 目标时间/总时长，等宽字体）；音量/亮度 HUD 顶部居中（喇叭/太阳图标 + 横向进度条，品牌色填充）；SpeedHUD 底部居中毛玻璃；三种 HUD 互斥、1.2s 淡出。
4. **手势数值**：竖滑现按屏高比例换算——必须改为契约公式 `clamp(起始值 - deltaY / 200, 0, 1)`（200vp 满量程）；横滑必须 `PlayerMath.horizontalSeekTarget(锁定起点, deltaX, 屏宽, duration)`，全滑量程 = `seekRangeFor(duration)`；横向/竖向判定阈值 ~10vp。
5. **音量路径**：现直接走 `PlayerController.setVolume`。契约优先 VolumeManager（STREAM MEDIA），受限/抛错才回退播放流音量，报告注明实际采用路径。
6. **缺失功能（按 TASK-4 任务书完整实现）**：长按两侧 2 倍速四态状态机（28% 侧区 `isSideZone`、下拉 ≥30vp 且达下 1/3 `lockPullSatisfied`、500ms 长按、四态转换、菜单选速解锁、SpeedHUD 三文案）；画中画（`@kit.PiPKit` 特性检测 + 可用进出/关页清理 + 不支持则禁用提示）；触觉（播放态切换轻触觉、锁定/解锁中触觉，复用 common/Haptics）。
7. **手势互斥**：横滑/竖滑/长按下拉不并发；单击在 SpeedHUD 显示期间不切控制栏（TASK-4 §3）。

## 验收标准

- [ ] 真机问题 1：顶部与状态栏不再叠字（隐藏或避让，退出恢复）
- [ ] 真机问题 2：暂停/继续真实生效且图标随状态切换；REPORT-4 写明根因与验证依据
- [ ] 真机问题 3：全部按钮 SymbolGlyph 化（编译可过）；黑背景铺满整屏、底部无空白带；控制栏不被手势条遮挡
- [ ] `TASKS\TASK-4-播放器完整手势.md` 的验收标准清单**逐条满足**（REPORT-4 完成项须同时覆盖该清单与本任务书三问题）
- [ ] 基线能力无回退（.m3u8 地址 / fingerList 防崩 / 5400102 等待逻辑）
- [ ] 自验命令通过；git 提交 `TASK-4-fix: 真机反馈修复与契约对齐`

## 自验命令

CONVENTIONS §10 标准命令；若环境提示找不到 SDK，主控实测可用命令：

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
DEVECO_SDK_HOME="D:\DevEco Studio\sdk" cmd //c "hvigorw.bat --mode module -p module=entry@default -p product=default assembleHap --no-daemon"
```

## 汇报

完成后写 `TASKS\REPORT-4.md`（CONVENTIONS §12 固定结构；尚无 REPORT-4，本次创建）。

## 禁止事项

通用见 CONVENTIONS §11。另：
- 禁止提前实施 TASK-5（直播间与历史）及以后任务的任何功能
- 手势/续播/上报的全部数值参数为 iOS 提取契约，不得调整
- 问题 2 的修复必须有验证依据（打点日志或代码链路证明），禁止无依据猜测式修改
