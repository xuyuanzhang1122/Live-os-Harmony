# TASK-2：视频库页 + 视频列表页

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md` 与 `TASKS/REPORT-1.md`（了解实际落地的接口签名）。

## 前置条件

TASK-0、TASK-1 完成。

## 目标

实现第 1 个页签「视频库」：主播房间网格 → 房间内视频文件列表两层结构，含轮询、下拉刷新、缩略图、删除，以及全局「未配置服务器」警告横幅。播放器本任务只留全屏模态壳（TASK-3 填充）。

## 必读参考（iOS 源码）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\VideoLibraryView.swift`
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\VideoListView.swift`
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\ViewModels\VideoLibraryViewModel.swift`
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\ContentView.swift`（警告横幅）

## 详细规格

### 1. 视频库页（pages/VideoLibraryPage.ets，替换 Index 第 1 页签占位）

**布局**
- 自适应网格（Grid/GridRow）：按可用宽度计算列数，**每列宽度落在 160~300vp 区间**（列数 = floor(width/210) 左右的实现即可，但必须保证最窄 ≥160vp、最宽 ≤300vp 的近似约束；窄屏手机 2 列，MatePad 横屏 4~5 列）
- 卡片（对应 iOS 卡片）：16:9 封面缩略图（圆角、`ThumbnailCache.load` 异步加载，加载前显示深灰渐变占位）；左上角「直播中」红色角标（`recording=true` 时）；下方：主播名（host_name）、副标题「N 个视频 · 已用 X.XGB」（video_count、total_size 经 Formats.formatBytes）；正在直播但无录播的占位房间（video_count=0）也显示卡片，封面用占位图 + 「暂无录播」
- 点击卡片 → push `VideoListPage`（传 folder_path 与 host_name）

**数据与刷新（VideoLibraryViewModel）**
- 加载策略 = **缓存优先**：先取 ApiCache 旧数据渲染，同时发网络请求刷新（对应 iOS cache-first）
- **10 秒轮询**：页面可见期间每 10s 拉一次；onPageShow 立即拉一次；onPageHide 停止轮询（用 CONVENTIONS §3 的统一轮询模式）
- **下拉刷新**：Refresh 组件；手动刷新时调用 `ThumbnailCache.invalidateSession()`（拿新缩略图）并触发 `AppConfig.refreshNetworkStatus()`（API-CONTRACT §5.5）
- 状态：加载中（骨架或菊花）、空态「暂无录播」（含说明文案）、错误态（显示 ApiError 中文文案 + 重试按钮）

### 2. 视频列表页（pages/VideoListPage.ets，NavDestination push）

**行布局**（对应 iOS VideoListView 行）
- 左侧 16:9 缩略图（约 120vp 宽）；右侧：文件名（name，超长省略）、「大小 · 日期」副标题（size、mod_time）；**已看进度**：从 `getHistoryAll()` 构建 `historyByPath`（键 video_path），有记录时显示细进度条 + 「已看 N%」
- `recording=true` 或 `playback_status='recording'`：右上红色「录制中」角标
- 点击行 → 打开播放器（本任务为 `bindContentCover` 全屏黑底占位页：居中显示文件名 + 「播放器将在 TASK-3 实现」，任意点击关闭。**接口留好**：`openPlayer(file: VideoFileInfo)` 状态与 cover 绑定，TASK-3 直接替换内容）

**删除**
- 行 `swipeAction`（右滑露删除按钮 → 确认弹窗 → `APIClient.deleteFile(rel_path)`，成功后行消失并 toast「已删除」）
- 编辑模式：右上「编辑」进入多选（复选框），底部「删除(N)」→ 确认弹窗 → `batchDeleteFiles(paths)`，成功 toast「已删除 N 个文件」，退出编辑模式

**刷新**：onPageShow 拉取（文件列表 + 历史进度）；下拉刷新；10 秒轮询（录制中文件的大小/角标能更新）

### 3. 未配置服务器警告横幅（pages/Index.ets 内）

- `AppConfig.activeURL` 为空时，页面顶部显示毛玻璃横幅（`backgroundBlurStyle`）：「未配置服务器，请前往设置」+ 跳转按钮 → 切到「设置」页签；activeURL 有效时隐藏（带过渡动画）

### 4. 空态文案（与 iOS 对齐）

- 视频库空：标题「暂无录播」+ 副文案「去「直播间」页签添加主播，开播后自动录制」
- 视频列表空：「该主播还没有录像」

## 验收标准

- [ ] 网格自适应：窄屏 ≥2 列、MatePad 横屏 ≥4 列，最窄列宽 ≥160vp（代码中体现列宽约束逻辑）
- [ ] 卡片信息齐全：封面、直播中角标、主播名、视频数+总大小；占位房间正确显示
- [ ] 缩略图经 ThumbnailCache 加载（有占位与失败兜底，不阻塞滚动）
- [ ] 10s 轮询 / onPageShow 即时刷新 / 下拉刷新三通道生效；下拉刷新触发 invalidateSession + refreshNetworkStatus
- [ ] 视频列表行含已看进度（percent 来自服务端历史）；录制中角标正确
- [ ] 单行删除（带确认）与批量删除（多选+确认）可用，调用正确端点
- [ ] 播放器占位 cover 存在且 openPlayer 接口就绪（供 TASK-3 替换）
- [ ] activeURL 为空时警告横幅显示并可跳设置；配置后隐藏
- [ ] 编译通过 + TASK-1 单元测试不回归；git 提交 `TASK-2: 视频库`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：本任务不实现播放器任何真实逻辑；不实现直播间/历史/设置页签（保持占位）。
