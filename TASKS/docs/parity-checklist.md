# Live OS iOS ↔ HarmonyOS 功能对齐核对表

状态说明：`✅` 表示鸿蒙实现与自动化/静态验收完成；`⚠️` 表示实现完成但仍保留指定真机里程碑观察项。

## 全局

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 冷启动品牌动画 | 首次启动约 2.3s，左右图标、闪电、闪光、标题、淡出 | `entry/src/main/ets/pages/components/LaunchView.ets`、`entry/src/main/ets/pages/components/LaunchRules.ets`、`entry/src/main/ets/pages/Index.ets` | ✅ |
| 启动期间预加载 | 启动画面叠加，不阻塞主内容创建 | `entry/src/main/ets/pages/Index.ets` | ✅ |
| 四页签顺序 | 视频库、直播间、历史、设置 | `entry/src/main/ets/pages/Index.ets` | ✅ |
| 页签独立导航 | 每页签保留独立 Navigation 栈 | `entry/src/main/ets/pages/Index.ets` | ✅ |
| 页签触觉 | 切换页签产生 selection 反馈，失败静默 | `entry/src/main/ets/pages/Index.ets`、`entry/src/main/ets/common/Haptics.ets` | ✅ |
| 品牌色 | 青绿强调色 | `entry/src/main/resources/base/element/color.json` | ✅ |
| 深浅色 | 内容页随系统主题，播放器恒暗 | `entry/src/main/ets/pages/Index.ets`、`entry/src/main/ets/pages/HistoryPage.ets`、`entry/src/main/ets/pages/PlayerPage.ets`、`entry/src/main/resources/dark/element/color.json` | ✅ |
| 未配置服务器提示 | 首页浮动警告并可跳设置 | `entry/src/main/ets/pages/Index.ets` | ✅ |
| 平板内容限宽 | 大屏列表/设置不过宽拉伸 | `entry/src/main/ets/pages/VideoListPage.ets`、`entry/src/main/ets/pages/RoomListPage.ets`、`entry/src/main/ets/pages/HistoryPage.ets`、`entry/src/main/ets/pages/SettingsPage.ets` | ✅ |
| 自适应应用图标 | 复用 iOS 浅色/深色正式 AppIcon | `AppScope/resources/base/media/layered_image.json`、`AppScope/resources/base/media/foreground.png`、`AppScope/resources/base/media/background.png`、`AppScope/resources/dark/media/foreground.png`、`AppScope/resources/dark/media/background.png` | ✅ |

## 视频库

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 缓存优先加载 | 先显示缓存，再请求网络 | `entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets` | ✅ |
| 页面轮询 | 可见时立即刷新并每 10 秒轮询 | `entry/src/main/ets/pages/VideoLibraryPage.ets` | ✅ |
| 手动刷新 | 失效缩略图会话、重测网络、重新请求 | `entry/src/main/ets/pages/VideoLibraryPage.ets`、`entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets` | ✅ |
| 响应式网格 | 手机 2 列，MatePad 4 列，宽屏最多 5 列 | `entry/src/main/ets/pages/VideoLibraryPage.ets`、`entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets` | ✅ |
| 房间卡片 | 缩略图、主播、数量、大小、直播中角标 | `entry/src/main/ets/pages/VideoLibraryPage.ets` | ✅ |
| 缩略图缓存 | 内存+磁盘缓存、会话门控 | `entry/src/main/ets/cache/ThumbnailCache.ets`、`entry/src/main/ets/pages/components/CachedThumbnail.ets` | ✅ |
| 进入视频列表 | 点击房间 push 对应主播视频 | `entry/src/main/ets/pages/VideoLibraryPage.ets`、`entry/src/main/ets/pages/Index.ets` | ✅ |

## 视频列表

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 视频信息行 | 16:9 缩略图、文件名、大小、日期、录制状态 | `entry/src/main/ets/pages/VideoListPage.ets` | ✅ |
| 观看进度 | 超过 5 秒才显示百分比和进度条 | `entry/src/main/ets/pages/VideoListPage.ets`、`entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets` | ✅ |
| 列表刷新 | 可见时立即刷新、10 秒轮询、支持下拉 | `entry/src/main/ets/pages/VideoListPage.ets` | ✅ |
| 单项删除 | 左滑、二次确认、按相对路径删除 | `entry/src/main/ets/pages/VideoListPage.ets`、`entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets` | ✅ |
| 批量删除 | 编辑、多选、确认、一次批量请求 | `entry/src/main/ets/pages/VideoListPage.ets`、`entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets` | ✅ |
| 播放入口 | 点击文件进入同一全屏播放器 | `entry/src/main/ets/pages/VideoListPage.ets`、`entry/src/main/ets/pages/Index.ets` | ✅ |

## 直播间

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 三态状态灯 | 红录制、绿监听、灰停止 | `entry/src/main/ets/pages/RoomListPage.ets`、`entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ✅ |
| 监听启停 | 乐观更新、服务端回填、失败回滚 | `entry/src/main/ets/pages/RoomListPage.ets`、`entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ⚠️ 已实现，待 M4 真实服务启停观察 |
| 删除直播间 | 左滑确认，可选同时删除录像 | `entry/src/main/ets/pages/RoomListPage.ets` | ⚠️ 已实现，待 M4 真机滑动/确认观察 |
| 多行添加 | 保留行号、逐行解析、忽略空行 | `entry/src/main/ets/pages/RoomListPage.ets`、`entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ✅ |
| 短链解析门控 | 仅标准 live.douyin.com 免解析 | `entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ✅ |
| 单次批量提交 | 有效条目组成一个 addLives 数组 | `entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ✅ |
| 行内容实时重绘 | 展示字段变化会改变 ForEach key | `entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ✅ |
| 刷新与轮询 | 缓存优先、可见时 10 秒轮询、下拉刷新 | `entry/src/main/ets/pages/RoomListPage.ets`、`entry/src/main/ets/viewmodel/RoomListViewModel.ets` | ✅ |

## 观看历史

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 未绑定 Key 空态 | 引导绑定并跳转设置 | `entry/src/main/ets/pages/HistoryPage.ets` | ✅ |
| 无历史空态 | 显示独立空状态 | `entry/src/main/ets/pages/HistoryPage.ets` | ✅ |
| 历史加载 | 页签激活即时加载，不做轮询 | `entry/src/main/ets/pages/HistoryPage.ets`、`entry/src/main/ets/viewmodel/HistoryViewModel.ets` | ✅ |
| 历史卡片 | 缩略图、名称、主播、相对时间、进度 | `entry/src/main/ets/pages/HistoryPage.ets` | ✅ |
| 历史进度 | 位置/时长钳制到 0～100 | `entry/src/main/ets/viewmodel/HistoryViewModel.ets` | ✅ |
| 历史播放 | 合成媒体文件并复用全屏播放器 | `entry/src/main/ets/viewmodel/HistoryViewModel.ets`、`entry/src/main/ets/pages/HistoryPage.ets`、`entry/src/main/ets/pages/Index.ets` | ⚠️ 已实现，待 M4 真实历史端到端观察 |
| 长按删除 | 长按上下文菜单、确认、按 video_path 删除 | `entry/src/main/ets/pages/HistoryPage.ets` | ⚠️ 已实现，待 M4 真机长按观察 |

## 设置

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 设置分组 | 服务器、源站、认证、存储、关于 | `entry/src/main/ets/pages/SettingsPage.ets` | ✅ |
| Key 摘要 | 显示已绑定 Key 尾号，初始化完成后刷新 | `entry/src/main/ets/pages/SettingsPage.ets`、`entry/src/main/ets/viewmodel/SettingsViewModel.ets` | ✅ |
| 连接测试 | getServerInfo 展示应用名、版本和链路 | `entry/src/main/ets/pages/SettingsPage.ets` | ✅ |
| 备份源站 | 内联编辑、失焦规范化并持久化 | `entry/src/main/ets/pages/SettingsPage.ets`、`entry/src/main/ets/config/AppConfig.ets` | ✅ |
| 手动网络 | 校验 http/https 后保存并重测 | `entry/src/main/ets/pages/NetworkConfigPage.ets`、`entry/src/main/ets/viewmodel/SettingsViewModel.ets` | ✅ |
| 智能网络 | LAN/公网配置、2 秒探测和重试 | `entry/src/main/ets/pages/NetworkConfigPage.ets`、`entry/src/main/ets/config/NetworkMonitor.ets` | ✅ |
| API Key 绑定 | 临时客户端验证成功后才持久化 | `entry/src/main/ets/pages/ApiKeyPage.ets` | ✅ |
| API Key 安全存储 | Asset Store Kit 优先、preferences 降级 | `entry/src/main/ets/config/ApiKeyStore.ets`、`entry/src/main/ets/config/AppConfig.ets` | ✅ |
| 缓存管理 | 分项统计、合计、确认清除、残留提示 | `entry/src/main/ets/pages/StorageManagementPage.ets`、`entry/src/main/ets/viewmodel/SettingsViewModel.ets` | ✅ |
| 版本日志 | 展示 2.0、1.2、1.1 功能列表 | `entry/src/main/ets/pages/AboutPage.ets` | ✅ |

## 播放器

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 媒体 URL 决策 | HLS 优先、MP4/后缀回退、携带 Key | `entry/src/main/ets/net/APIClient.ets`、`entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| AVPlayer 生命周期 | create→url→surface→prepare→play | `entry/src/main/ets/player/PlayerController.ets` | ✅ |
| 状态与时间同步 | native 事件为主、属性轮询兜底，ms→s | `entry/src/main/ets/player/PlayerController.ets`、`entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 时间线交互 | 冻结预览、seekDone 后按原状态恢复 | `entry/src/main/ets/player/ProgressTracker.ets`、`entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 单击/双击 | 单击显隐控制层，双击播放暂停 | `entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 横滑 seek | 10vp 方向锁定，按屏宽映射 | `entry/src/main/ets/pages/PlayerPage.ets`、`entry/src/main/ets/player/PlayerMath.ets` | ✅ |
| 亮度/音量 | 左亮右音，系统音量失败回退单流音量 | `entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 2 倍速锁定 | 侧区长按、下拉锁定/解锁、恢复用户倍速 | `entry/src/main/ets/pages/PlayerPage.ets`、`entry/src/main/ets/player/PlayerMath.ets` | ✅ |
| 续播 | 超过 5 秒、三次重试、500ms 间隔、3 秒误差 | `entry/src/main/ets/pages/PlayerPage.ets`、`entry/src/main/ets/player/PlayerMath.ets` | ✅ |
| 进度上报 | 播放中每 15 秒，关闭前 best-effort | `entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 画中画 | 能力可用时创建 PiP，关闭播放器时同步清理 | `entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 关闭漏斗 | 暂停、上报、PiP、release、窗口恢复，全部超时保护 | `entry/src/main/ets/pages/PlayerPage.ets`、`entry/src/main/ets/player/PlayerController.ets`、`entry/src/main/ets/pages/Index.ets` | ✅ |
| 等比显示 | 按视频真实宽高比 contain，横竖屏不拉伸 | `entry/src/main/ets/pages/PlayerPage.ets` | ✅ |
| 控件与触觉 | 控件命中区至少 44vp；状态 light，锁定/解锁 medium | `entry/src/main/ets/pages/PlayerPage.ets`、`entry/src/main/ets/common/Haptics.ets` | ✅ |

## 备份与恢复

| 功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态 |
|---|---|---|---|
| 备份包互通 | UTC 时间、排序 JSON、缺字段容忍 | `entry/src/main/ets/model/BackupModels.ets`、`entry/src/main/ets/viewmodel/BackupViewModel.ets` | ✅ |
| 并行导出 | 本地文件与远端上传同时开始 | `entry/src/main/ets/pages/components/BackupExportSheet.ets` | ⚠️ 已实现，待 M5 DocumentViewPicker 真机观察 |
| 上传目标 | 有源站走源站，否则走主服务并降级提示 | `entry/src/main/ets/pages/components/BackupExportSheet.ets`、`entry/src/main/ets/net/APIClient.ets` | ✅ |
| 短 ID 找回 | 按 ID 获取/恢复并可复制完整 ID | `entry/src/main/ets/pages/RestoreBackupPage.ets`、`entry/src/main/ets/viewmodel/BackupViewModel.ets` | ⚠️ 已实现，待 M5 真实源站观察 |
| 本地文件恢复 | 选择 JSON、预览、确认后整包恢复 | `entry/src/main/ets/pages/RestoreBackupPage.ets` | ⚠️ 已实现，待 M5 文件选择器观察 |
| 重启轮询 | 每 2 秒、最多 20 次，404 视为完成 | `entry/src/main/ets/viewmodel/BackupViewModel.ets` | ⚠️ 已实现，待 M5 真实重启窗口观察 |
| 写回设备配置 | 写回四项网络配置，不写 API Key | `entry/src/main/ets/pages/RestoreBackupPage.ets` | ✅ |
| 敏感字段排除 | 不导出 API Key、Cookie、观看历史 | `entry/src/main/ets/model/BackupModels.ets`、`entry/src/test/Task7Backup.test.ets` | ✅ |
