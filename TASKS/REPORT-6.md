# REPORT-6：设置全套（网络配置 / API Key / 存储 / 关于）

## 完成项

- ✅ 设置主页完成：使用原生 List 分组卡片呈现服务器、备份服务器（源站）、认证、存储、关于 5 个分组，网络模式、Key 尾号、缓存用量和版本副标题均动态显示。
- ✅ 服务器功能完成：连接测试调用 `getServerInfo()`；成功显示应用名、版本与 LAN wifi/公网地球图标，失败显示红色「连接失败」，并保留最近一次有效服务器版本。
- ✅ 备份源站配置完成：`backupServerURL` 可内联编辑，失焦后去除首尾空格并写入 AppConfig 持久化字段，说明文案与任务书一致。
- ✅ 网络配置完成：支持手动/智能切换、http/https 校验、智能模式至少一个地址校验、实时当前连接卡、手动重测、保存触发 `refreshNetworkStatus()` 和 1.5 秒「已保存」胶囊。
- ✅ API Key 完成：密码输入与显隐切换、临时 `APIClient(activeURL, inputKey)` 验证、验证成功后持久化、完整 BoundKeyCard、401/403 专用中文错误及带确认的清除操作均已实现。
- ✅ 存储管理完成：分别统计 ThumbnailCache 与 ApiCache、显示合计、确认后清除并重新统计；仅在余量为零时提示「已清除」，否则提示「部分缓存未能清除」。
- ✅ 关于页完成：2.0、1.2、1.1 三组版本日志的全部指定文案、图标和品牌色强调均已呈现。
- ✅ 恢复备份严格为占位：页面仅显示「恢复备份将在 TASK-7 实现」，未实现任何 TASK-7 行为。
- ✅ TASK-2 授权小修完成：`VideoListPage` 删除操作改为 `swipeAction.end`，手指左滑露出右侧删除按钮。
- ✅ 编译与测试通过：`assembleHap` 输出 `TYPE CHECK SUCCESSFUL`、`BUILD SUCCESSFUL`；Hypium 28 个用例全部通过，无失败或错误。
- ✅ 范围约束满足：未实现 TASK-3/4/5/7/8 的功能、页面或文件，未引入运行时三方依赖。

## 实现说明

- 设置子页保存或清除后通过内部刷新事件更新主页摘要，避免 Navigation 保留根组件时 Key 尾号与缓存用量滞后；没有修改 AppConfig 公共接口。
- 网络配置实际变化时清空旧的 `serverInfo`，防止新服务器地址旁继续显示上一个服务器的名称和版本；重新测试成功后再写入新信息。
- API Key 已绑定进入页的行为对齐 iOS `APIKeyView.refreshCurrentUser()`：从 AppConfig 读取已保存 Key，并向当前服务器刷新完整用户信息；服务器可用时直接显示 BoundKeyCard，离线失败时保留 Key、错误提示与清除入口，不缓存可能过期的身份元数据。
- GitHub 行选择复制链接到系统剪贴板并显示 toast。理由是无需依赖设备上浏览器 Ability 匹配，手机和平板行为一致；复制失败时 toast 直接显示完整 URL。
- 当前 SDK 没有可用的 `sys.symbol.globe` 资源，因此公网状态使用 Unicode 地球图标 `🌐`，LAN 状态使用系统 wifi SymbolGlyph，语义与 iOS 一致。
- 与任务书的偏差：无。
- 对 TASK-1 公共接口的任何变更：无。

## 新增/修改文件清单

- 新增：`entry/src/main/ets/pages/SettingsPage.ets`
- 新增：`entry/src/main/ets/pages/NetworkConfigPage.ets`
- 新增：`entry/src/main/ets/pages/ApiKeyPage.ets`
- 新增：`entry/src/main/ets/pages/StorageManagementPage.ets`
- 新增：`entry/src/main/ets/pages/AboutPage.ets`
- 新增：`entry/src/main/ets/pages/RestoreBackupPage.ets`
- 新增：`entry/src/main/ets/viewmodel/SettingsViewModel.ets`
- 新增：`TASKS/REPORT-6.md`
- 修改：`entry/src/main/ets/pages/Index.ets`
- 修改：`entry/src/main/ets/pages/VideoListPage.ets`
- 修改：`entry/src/test/Task1Infrastructure.test.ets`

## 自验结果

- `.\hvigorw.bat assembleHap --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`，`BUILD SUCCESSFUL`，未签名 HAP 打包成功。唯一警告为工程既有的 `No signingConfig found for product default`。
- `.\hvigorw.bat test --daemon=false`：通过；28 个本地 Hypium 用例全部 Success，Failure 0、Error 0、Ignore 0，`BUILD SUCCESSFUL`。
- 新增测试覆盖：手动/智能网络 URL 校验与至少一个地址约束、API Key 尾号优先级、401/403 中文错误映射、两类缓存容量合计、缓存残留时不误报完全清除。
- 静态契约检查：连接测试仅调用 `getServerInfo()`；Key 验证先创建临时 APIClient 并在成功后调用 `setApiKey()`；缓存页调用指定的 `sizeBytes()`、`clearAll()`、`clear()`；恢复备份仅含 TASK-7 占位；删除滑动仅使用 `end`。
- 范围与质量检查：`git diff --check` 无空白错误；AppConfig、APIClient 与数据模型公共签名未改变；未新增第三方依赖。

## 遗留问题

- 工程尚未配置签名，当前只能生成未签名 HAP；需在 DevEco Studio 配置自动签名后，真机核对手机/平板布局、毛玻璃、密码显隐、剪贴板、键盘失焦保存、左滑删除和 1.5/2 秒提示时序。
- 连接测试、智能 LAN 探测、API Key 身份信息及有实际文件占用时的缓存清理，需要连接真实 bililive 服务和真机文件系统完成端到端验证。
