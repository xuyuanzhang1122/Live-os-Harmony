# REPORT-8：打磨与总验收

## 完成项

- [x] 按 iOS `LaunchScreenView.swift` 的实测节点实现一次性冷启动动画：直接复用 iOS 浏览器、手机、闪电三份原始 SVG，完成图标入场、闪电/白闪、标题副标题与整体淡出；内容页在动画期间并行预加载。
- [x] 完成触觉反馈核对，不新增触觉场景、不修改既有强度或触发契约；底栏切换、播放状态切换、2 倍速长按和锁定/解锁均保留既有反馈，异常继续静默降级。
- [x] 完成 MatePad/宽屏低风险适配：主要列表与设置页使用 960vp 内容限宽居中，视频库网格按宽度响应并限制为 4～5 列，播放器仅扩大部分控件可点击区域。
- [x] 完成深色模式静态走查：历史记录、网络配置、API Key 状态卡、进度轨道等改用系统颜色 token，未新增硬编码深色分支。
- [x] 修复设置页 API Key 摘要异步竞态；配置初始化完成后按需重读摘要，不改动 `ApiKeyPage` 的绑定逻辑。
- [x] 完成 HarmonyOS 分层应用图标：直接复用 iOS 1024×1024 浅色/深色 AppIcon，提供 layered image 包装与由原图缩放的 216×216 兼容图，不使用重新生成的品牌图形。
- [x] 新增 `README.md`、`AGENTS.md` 和 `TASKS/docs/parity-checklist.md`；README 保留截图占位并同时记录推荐/本次验收环境，parity checklist 共 70 项且均指向真实实现路径。
- [x] 完成全工程 TODO/FIXME、JSON 缺省兜底、ForEach 键值、长按上下文菜单、业务参数未改动等专项检查。
- [x] 新增 TASK-8 单元测试并注册到 `entry/src/test/List.test.ets`；全量 81 项测试通过。

## 实现说明

### 启动动画

- `LaunchDisplayGate` 使用模块级门闩保证每个应用进程只展示一次，避免页面重建或页签切换重复播放。
- 节奏节点为 0ms 图标入场、380ms 闪电与白闪、480ms 白闪退场、540ms 标题入场、2100ms 整体淡出、2300ms 结束，与 iOS 参考实现的观感节点对齐。
- 启动层以高层级覆盖已经构建的主界面；动画结束只移除覆盖层，不延迟主页初始化。

### 触觉与业务契约

- 仅核对并保留 `Haptics.selection/light/medium` 的既有调用，没有新增触觉反馈。
- 未改轮询间隔、长按手势阈值、2 倍速值、播放状态机或 API 契约参数。播放器变更仅涉及 44vp 点击区域。
- 长按菜单继续使用 `bindContextMenu(builder, ResponseType.LongPress)`；列表键值继续包含全部展示字段。

### 平板与深色模式

- About、API Key、历史、网络配置、房间、设置、存储、恢复备份、视频列表等页面统一使用 960vp 最大内容宽度居中。
- 视频库列数计算上限为 5，并用 1580vp 网格最大宽度控制单卡宽度；819vp 为 4 列，1000vp/1600vp 为 5 列，窄屏仍为 2 列。
- 半透明白色卡片/轨道改为 `comp_background_primary`、`comp_background_secondary` 等系统 token，文字沿用系统字体 token；播放器恒暗区域不作主题化处理。

### API Key 摘要竞态

- 根因是 `EntryAbility` 异步初始化配置时，`SettingsPage.aboutToAppear()` 可能先于 KeyStore 初始化完成执行，首次 `getApiKey()` 因而返回空值。
- `SettingsViewModel` 增加一次性“摘要待重读”判定，`SettingsPage` 监听 `config.apiKeyBound` 并仅在需要时重读摘要；不触碰 `ApiKeyPage` 的保存与展示流程。

### 图标与文档

- 启动 Logo 逐文件复制 iOS `SplashBrowser`、`SplashPhone`、`SplashLightning` 原始 SVG；只在 ArkUI 中设置尺寸、位移与动画，不重绘图形。
- 应用图标逐文件复制 iOS `AppIcon-1024-Light.png` / `AppIcon-1024-Dark.png` 作为浅色/深色 1024px 分层资源；216px 兼容图仅作高质量等比缩放，品牌图形未重新生成。
- README 中区分推荐 DevEco Studio 6.0.1 环境和本次实际验收的 DevEco Studio 6.1.1/API 24 环境，避免把本机版本写成唯一要求。
- `AGENTS.md` 明确目录、构建方式、`TASKS/docs/CONVENTIONS.md` 与 `API-CONTRACT.md` 入口，以及“行为对齐 iOS”的维护原则。
- parity checklist 的 M4/M5 真机观察项保留为待观察状态；设置页 Key 摘要标记为本任务已修复。

### 接口与规格偏差

- 未新增或修改 TASK-1 公共接口。
- 无功能规格偏差；未以重构方式扩大任务范围。

## 新增/修改文件清单

### 新增

- `AGENTS.md`
- `README.md`
- `TASKS/REPORT-8.md`
- `TASKS/docs/parity-checklist.md`
- `AppScope/resources/base/media/background.png`
- `AppScope/resources/base/media/foreground.png`
- `AppScope/resources/base/media/layered_image.json`
- `AppScope/resources/dark/media/app_icon.png`
- `AppScope/resources/dark/media/background.png`
- `AppScope/resources/dark/media/foreground.png`
- `entry/src/main/ets/pages/components/LaunchRules.ets`
- `entry/src/main/ets/pages/components/LaunchView.ets`
- `entry/src/main/resources/base/media/background.png`
- `entry/src/main/resources/base/media/foreground.png`
- `entry/src/main/resources/base/media/layered_image.json`
- `entry/src/main/resources/base/media/splash_browser.svg`
- `entry/src/main/resources/base/media/splash_lightning.svg`
- `entry/src/main/resources/base/media/splash_phone.svg`
- `entry/src/main/resources/dark/media/app_icon.png`
- `entry/src/main/resources/dark/media/background.png`
- `entry/src/main/resources/dark/media/foreground.png`
- `entry/src/test/Task8Polish.test.ets`

### 修改

- `AppScope/app.json5`
- `AppScope/resources/base/media/app_icon.png`
- `entry/src/main/module.json5`
- `entry/src/main/resources/base/media/app_icon.png`
- `entry/src/main/ets/pages/AboutPage.ets`
- `entry/src/main/ets/pages/ApiKeyPage.ets`
- `entry/src/main/ets/pages/HistoryPage.ets`
- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/pages/NetworkConfigPage.ets`
- `entry/src/main/ets/pages/PlayerPage.ets`
- `entry/src/main/ets/pages/RestoreBackupPage.ets`
- `entry/src/main/ets/pages/RoomListPage.ets`
- `entry/src/main/ets/pages/SettingsPage.ets`
- `entry/src/main/ets/pages/StorageManagementPage.ets`
- `entry/src/main/ets/pages/VideoLibraryPage.ets`
- `entry/src/main/ets/pages/VideoListPage.ets`
- `entry/src/main/ets/viewmodel/SettingsViewModel.ets`
- `entry/src/main/ets/viewmodel/VideoLibraryViewModel.ets`
- `entry/src/test/List.test.ets`

## 自验结果

- [x] `./hvigorw.bat assembleHap --daemon=false`：替换 iOS 原始图标/SVG 后重新执行，`BUILD SUCCESSFUL`（9.563s）。
- [x] `./hvigorw.bat test --daemon=false`：替换资源后重新执行，`BUILD SUCCESSFUL`（10.029s）；`Tests run: 81, Failure: 0, Error: 0, Pass: 81, Ignore: 0`。
- [x] TDD 红灯确认：新增测试初次因目标导出/模块尚不存在而编译失败；完成实现后转绿并纳入全量测试。
- [x] TODO/FIXME 扫描：生产 ArkTS 源码无遗留标记；任务依据类说明性注释未误删。
- [x] 启动动画文本、节点与“一次/进程”门闩静态检查通过。
- [x] 四类既有触觉触发点及异常静默降级检查通过。
- [x] 主要页面 960vp 限宽、视频网格 4～5 列、深色 token 检查通过。
- [x] 历史/房间列表键值与 `ResponseType.LongPress` 长按菜单回归检查通过。
- [x] 播放器差异检查确认未修改手势数值与业务参数。
- [x] parity checklist 恰为 70 项，所有列出的鸿蒙实现路径均存在。
- [x] 两套浅色/深色 1024px 图标资源与 iOS 原图 SHA-256 一致；216px 兼容图尺寸、三份启动 SVG 原文哈希及 layered image 引用检查通过。
- [x] `git diff --check` 通过；本地逐文件代码复核未发现 Critical/Important 问题。

## 遗留问题

- M4 真机观察：需继续以真实服务端核对房间启停/删除、历史播放和历史长按菜单的最终手感与回包表现。
- M5 真机观察：需继续核对 DocumentPicker、真实源短 ID 和真实进程重启后的轮询恢复。
- TASK-8 真机观察：启动动画节奏、横竖屏 MatePad 排版、系统深色模式和触觉强弱仍需在目标设备完成最终视觉/手感签收；代码、资源、构建、单测及静态验收均已通过。
- 编译仍会报告既有兼容性告警：3x API 从 API 13 起提供，以及音量/像素转换接口的弃用提示；项目已有兼容回退，本任务未改变其行为。
- 主控要求 `TASKS/tools/` 保持未跟踪，因此提交完成后该目录仍会出现在 `git status`；除该目录外，本任务文件全部显式提交。
