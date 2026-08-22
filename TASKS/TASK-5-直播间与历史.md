# TASK-5：直播间管理 + 观看历史

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md` 与 `TASKS/REPORT-1.md`、`REPORT-4.md`。

## 前置条件

TASK-0 ~ TASK-4 完成（历史页点击进播放器依赖 TASK-3/4 的 PlayerPage）。

## 目标

实现第 2 页签「直播间」与第 3 页签「观看历史」。

## 必读参考（iOS 源码）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\RoomListView.swift`
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\ViewModels\RoomListViewModel.swift`
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\HistoryView.swift`（含 HistoryViewModel 与 HistoryEntry 定义）

## 详细规格

### 1. 直播间页（pages/RoomListPage.ets，替换第 2 页签占位）

**列表行**
- 状态灯（霓虹圆点 + 微光效果）：**红 = recording（录制中）｜ 绿 = listening（监听中未开播）｜ 灰 = 未监听**
- 主信息：host_name（主播名，加粗）、room_name · platform_cn_name 副标题
- 状态文字与开关：`listening=false` 显示「停止」+ 启动按钮；`listening=true` 显示「监听中」（`status=true` 开播时附加「直播中」标记）；按钮调用 `startListen(id)` / `stopListen(id)`，点击后乐观更新 + 请求完成后用返回的 LiveInfo 刷新该行
- `initializing` 状态显示「初始化中」
- **左滑操作**（swipeAction）：红色「删除」→ 确认弹窗（含勾选框「同时删除该主播的全部录像文件」，默认不勾）→ `deleteLive(id, deleteFiles)`，成功移除行并 toast

**工具栏**：「+」（添加直播间，bindSheet）、「刷新」。**「导出备份」按钮本任务不做**（TASK-7 加入）。

**添加直播间 Sheet**（bindSheet，底部弹层）
- 多行 `TextArea` 占位文案：「粘贴直播间链接或抖音分享文案，每行一个」
- 提交逻辑（对齐 iOS）：
  1. 按行拆分、去空行
  2. 每行处理：**非抖音链接先调 `resolveUrl(line)`** 解析成标准直播间 URL（抖音链接/短链直接提交，服务端会解析；resolve 失败的行单独提示，不阻塞其他行）
  3. 全部汇总成数组一次 `addLives([{url, listen:true}...])`
  4. 结果反馈：成功 N 个 toast；失败行列出（「第 X 行添加失败：原因」）
  5. 成功后收起 Sheet 并刷新列表

**刷新**：10s 轮询 + onPageShow 即时 + 下拉刷新 + ApiCache 缓存优先（同 TASK-2 模式）。

### 2. 观看历史页（pages/HistoryPage.ets，替换第 3 页签占位）

**卡片行**
- 左侧 16:9 缩略图：`ThumbnailCache` 加载 `buildThumbnailUrl`（由 video_path 构造：`/api/thumbnail/{enc}` + `_key` 兜底；注意历史条目没有现成 thumbnail_url 字段）
- 中部：video_name（主）、主播名（video_path 第一段）、更新时间（formatRelativeTime）
- 底部细进度条：position_seconds/duration_seconds 百分比（品牌色）
- **点击 → 打开播放器**：由 HistoryEntry 合成 `VideoFileInfo`（name=video_name、rel_path=video_path、size=0、mod_time=updated_at、各 url 置空——buildPlaybackUrl 会走后缀回退链），复用 TASK-3/4 的 PlayerPage 全屏 cover（入口与视频列表一致）
- **长按 → 上下文菜单**（bindMenu 或自定义 popup）：「删除这条记录」→ 确认 → `deleteHistoryEntry(video_path)`，行消失

**空态**
- 未绑定 API Key（apiKeyBound=false）：引导空态「未绑定 API Key」+ 说明「绑定后可同步各设备的观看历史与进度」+ 按钮「去设置」→ 切到设置页签
- 已绑定但无记录：「暂无观看记录」+ 副文案「看过的视频会出现在这里，进度多端同步」

**刷新**：onPageShow 拉取 + 下拉刷新（10s 轮询可不做，历史变化低频，对齐 iOS 即可——iOS 历史页无轮询）。

## 验收标准

- [ ] 状态灯三色规则正确（红=录制/绿=监听/灰=停止）；启停按钮乐观更新并回填最新 LiveInfo
- [ ] 左滑删除 + 「同时删除录像」勾选 → 正确端点与 body（delete_files）
- [ ] 添加 Sheet：多行输入、非抖音先 resolveUrl、数组体一次提交、逐行失败反馈
- [ ] 直播间页 10s 轮询 + 缓存优先 + 下拉刷新
- [ ] 历史卡片：缩略图（video_path 构造 URL）、进度条、相对时间齐全
- [ ] 点击历史卡片能进播放器并正常续播（合成 VideoFileInfo + 后缀回退链生效）
- [ ] 长按删除历史记录可用
- [ ] 两种空态（未绑 Key 引导 / 无记录）文案与跳转正确
- [ ] 编译 + 测试全绿；git 提交 `TASK-5: 直播间与历史`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：不做「导出备份」入口（TASK-7）；不实现 SSE（iOS 用轮询，保持一致）。
