# REPORT-5：直播间管理 + 观看历史

## 完成项

- ✅ 直播间状态展示完成：状态灯严格按红=录制中、绿=监听中未录制、灰=未监听，并使用外层半透明圆形成微光；行内包含主播、房间名、平台、初始化/停止/监听状态及直播中标记。
- ✅ 监听启停完成：启动/停止按钮先乐观更新行状态，请求分别调用 `startListen(id)` / `stopListen(id)`，成功后以服务端 `LiveInfo` 回填，失败自动回滚；单元测试覆盖启动、停止与失败回滚。
- ✅ 直播间删除完成：左滑显示红色「删除」，确认弹窗包含默认不勾选的「同时删除该主播的全部录像文件」，调用 `deleteLive(id, deleteFiles)` 后移除行并 toast；测试验证 `delete_files=true` 透传。
- ✅ 多行添加完成：按原始行号拆分并忽略空行，抖音链接/短链直接提交，其他输入逐行 `resolveUrl`；有效项统一组成一个 `AddLiveRequest[]`，只调用一次 `addLives`，成功数 toast、解析/批量失败逐行反馈。
- ✅ 服务端静默跳过提示完成：当返回数量少于提交数量时，以规范化后的 `LiveInfo.live_url` 匹配标准 `live.douyin.com` 提交行，未匹配行提示「第 X 行添加未生效」；不会把可能被服务端改写的短链误报为具体失败行。
- ✅ 直播间刷新完成：复用 TASK-2 模式实现 ApiCache 缓存优先、页签 active 时即时拉取、仅 active 时运行 10 秒轮询、工具栏刷新与下拉刷新；下拉刷新会先执行 `refreshNetworkStatus()`。
- ✅ 历史卡片完成：使用 `CachedThumbnail` / `ThumbnailCache` 加载由 `video_path` 构造的签名兜底缩略图 URL，显示视频名、路径第一段主播信息、`formatRelativeTime` 更新时间及品牌色细进度条。
- ✅ 历史进度边界完成：`position_seconds / duration_seconds` 严格 clamp 到 0–100；非有限数或 `duration_seconds <= 0` 返回 0，避免 NaN 宽度；单元测试覆盖正常、越界和无效值。
- ✅ 历史播放入口完成：点击卡片合成各媒体 URL 为空的 `VideoFileInfo`，由 `Index.historyTab` 的 `onPlayFile` 直接写入 `activePlayerFile`，复用现有全屏 `PlayerPage` 和后缀回退/续播链；未新增播放器宿主，未修改 `Index.onBackPress`。
- ✅ 历史删除完成：卡片 `bindMenu` 长按菜单提供「删除这条记录」，二次确认后调用 `deleteHistoryEntry(video_path)` 并移除行。
- ✅ 两种历史空态完成：未绑定 Key 显示指定引导文案和「去设置」按钮（直接切换 `selectedTab = 3`）；已绑定无记录显示指定空态文案。历史页按 active 即时拉取和下拉刷新，不做轮询。
- ✅ 页签生命周期完成：`RoomListPage` / `HistoryPage` 均使用 `@Require @Param active` + `@Monitor('active')`，Index 分别传入 `selectedTab === 1` / `selectedTab === 2`；直播间非当前页签时停止轮询。
- ✅ 测试注册与回归完成：新增 TASK-5 测试已在 `List.test.ets` 注册；结果为 `Tests run: 66, Failure: 0, Error: 0, Pass: 66, Ignore: 0`。
- ✅ 编译通过：`hvigorw.bat assembleHap --daemon=false` 输出 `TYPE CHECK SUCCESSFUL` 与 `BUILD SUCCESSFUL`。
- ✅ 范围约束满足：未实现导出备份、SSE 或 TASK-7 及以后功能；未修改 API 契约、网络层、模型、播放器关闭漏斗，`TASKS/tools/` 保持未跟踪且不纳入提交。

## 实现说明

- 关键设计决策：直播间与历史拆分为各自的 State V2 ViewModel；网络、缓存和可测试的展示规则集中在 ViewModel，页面只负责 active 生命周期与交互接线。
- 关键设计决策：停止监听的乐观态同时清除 `status`、`recording`、`recording_preparing` 与 `initializing`，避免请求期间仍显示红色录制灯；请求失败使用完整原始 `LiveInfo` 回滚。
- 关键设计决策：批量添加的解析失败与整批请求失败都保留原始输入行号；对服务端静默跳过只匹配标准直播 URL。短链可能被服务端转换为标准 URL，无法可靠反推具体输入行，因此不制造错误归因。
- 关键设计决策：历史 ViewModel 在 base URL 或 API Key 身份变化时立即清空旧条目，避免网络失败期间短暂显示另一 Key 用户的历史。
- 关键设计决策：历史卡片按任务书原文使用 `video_path` 第一段作为主播显示值；播放器文件的 `mod_time` 保留 `updated_at` 原字符串，其余媒体 URL 置空，让既有 `APIClient.buildPlaybackUrl` 走后缀回退链。
- 与任务书的偏差：服务端 `addLives` 契约不会返回静默跳过项的错误原因，且短链可能被规范化，故无法对所有静默失败给出准确行号；标准直播 URL 已按返回 `live_url` 匹配提示，短链不做不可靠推断。其余无偏差。
- 对 TASK-1 公共接口的任何变更：无。

## 新增/修改文件清单

- 新增：`entry/src/main/ets/pages/RoomListPage.ets`
- 新增：`entry/src/main/ets/pages/HistoryPage.ets`
- 新增：`entry/src/main/ets/viewmodel/RoomListViewModel.ets`
- 新增：`entry/src/main/ets/viewmodel/HistoryViewModel.ets`
- 新增：`entry/src/test/Task5RoomHistory.test.ets`
- 新增：`TASKS/REPORT-5.md`
- 修改：`entry/src/main/ets/pages/Index.ets`
- 修改：`entry/src/test/List.test.ets`

## 自验结果

- `hvigorw.bat assembleHap --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`，`BUILD SUCCESSFUL in 9 s 203 ms`，HAP 打包与签名任务完成。
- `hvigorw.bat test --daemon=false`：通过；Hvigor 输出 `BUILD SUCCESSFUL in 9 s 478 ms`，并从 `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 核对 `Tests run: 66, Failure: 0, Error: 0, Pass: 66, Ignore: 0`。
- TDD 证据：首次测试因 TASK-5 ViewModel 尚不存在而编译失败；静默跳过识别、停止监听录制态清理、Key 身份切换清理均先观察到目标断言失败，再以最小实现转绿。
- 验收静态检查：两个页签均由 Index 传入 active；直播间唯一轮询间隔为 10000ms 且 deactivate 清理；历史入口唯一通过 `onPlayFile` 写入 `activePlayerFile`；新增文件不含 `bindContentCover`、自建 `PlayerPage`、导出备份或 SSE。
- ArkTS 与范围检查：新增实现未使用状态管理 V1 装饰器、`any`/`unknown` 或运行时三方依赖；`git diff --check` 无空白错误；未修改 `TASKS/docs/`、APIClient、模型及 iOS/服务端工程。
- 编译警告均来自既有播放器代码（3x 倍速 API 13、废弃音量接口、`px2vp`），本任务新增文件无编译警告。

## 遗留问题

- 需在 API 21 真机连接真实服务验证左滑、ConfirmDialog 勾选、bindSheet 多行输入、长按菜单和实际缩略图加载的触控/系统组件表现；编译与纯逻辑回归已通过。
- 服务端对 `addLives` 单项失败只写日志、不返回逐项错误；短链静默失败无法从当前契约可靠定位到具体输入行。
