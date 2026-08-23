# REPORT-7：备份导出与恢复（含云备份短 ID 找回）

## 完成项

- ✅ 导出备份 Sheet 完成：直播间工具栏新增「导出备份」，组包后以 `Promise.all` 并行启动 `DocumentViewPicker.save` 本地保存与远端上传；文件名为 `bililive-harmony-backup-{unix秒}.json`，序列化沿用 TASK-1 的排序 key 实现。
- ✅ 上传目标与降级完成：`backupServerURL` 非空时上传源站，否则回落主服务；两种成功文案区分，404/405/网络错误统一显示「当前服务器暂不支持备份接口，已保留本地文件」，完整备份 ID 可通过 `@ohos.pasteboard` 复制。
- ✅ 按短 ID 恢复完成：有源站时执行源站取包后向主服务提交整包；无源站时从主服务预取包供设备配置写回，同时恢复请求严格使用 `restoreBackup({ id })`。
- ✅ 主服务预取降级完成：无源站且预取包失败时仍继续 `restoreBackup({ id })` 与轮询；服务端恢复成功后跳过无法完成的设备配置写回，但仍执行 `refreshNetworkStatus()` 并返回设置页。
- ✅ 本地文件恢复完成：支持 `DocumentViewPicker.select` 选择 JSON、无效文件 toast「不是有效的备份文件」、导出时间/端口绑定/输出目录/直播间数量及可选设备配置预览，并在确认后向主服务提交整包。
- ✅ 重启轮询完成：仅在含 `job_id` 且状态为 pending/running/restarting 时每 2 秒轮询，最多 20 次；状态端点 404（APIClient 返回 null）判定完成，网络连接失败继续，其他错误立即呈现，耗尽后固定提示「恢复超时，请手动检查服务器」。
- ✅ 恢复成功处理完成：有备份包时写回 serverURL/lanURL/publicURL/autoSwitchNetwork 四字段，不调用任何 API Key 写入或清除接口；随后立即重测网络、toast 最终服务端 message，并通过当前 `NavPathStack` 返回设置页。
- ✅ iOS 互通与 omitempty 防御完成：测试使用字段齐全的 iOS 兼容样例和最小字段样例验证解析；服务端快照、备份包和恢复响应的可缺字段均使用 `??` 默认值，不会把 API Key/Cookie/观看历史写入备份 JSON。
- ✅ 测试注册完成：新增 `Task7Backup.test.ets` 并在 `entry/src/test/List.test.ets` 注册，10 个 TASK-7 用例覆盖端点、降级、轮询、文件名、敏感字段排除及 iOS JSON 解析。
- ✅ 编译与测试通过：`assembleHap` 与 `test` 均输出 `TYPE CHECK SUCCESSFUL`、`BUILD SUCCESSFUL`；独立只读代码审查最终结论为 Ready: Yes。
- ✅ 范围约束满足：未修改 TASK-1 公共模型/APIClient/AppConfig 接口，未修改既有路由，未实施 TASK-8 的启动动画、触觉补全、平板走查、图标或 README。

## 实现说明

- 无源站的 ID 恢复先尝试 `fetchBackupPackage('main', id)`，取得 `iosConfig` 后仍以 `{ id }` 请求主服务恢复；这是任务书与 iOS 行为之间规格缝隙的兼容方案。按主控补充，预取失败不阻塞恢复，成功后仅跳过设备配置写回。
- 导出流程先读取一次服务器配置并生成不可变备份包，再同时启动文件选择/写入与上传任务；任一路径取消或失败不会取消另一条路径。
- `DocumentViewPicker` 返回空 URI 或抛出取消结果时只记录「已取消保存本地文件」或静默返回，不进入失败提示；真正文件写入错误与 JSON 解析错误分别处理。
- 恢复页通过 `NavDestination.onReady` 获取现有 `NavPathStack`，恢复成功后直接 pop，避免改动主控已注册的无参路由。
- 轮询仅吞掉 `ApiErrorType.NETWORK`；404 已由现成 `APIClient.getRestoreStatus()` 归一化为 null，避免把权限、解析或其他服务端错误误判为重启中的正常断连。
- 与任务书的偏差：无。
- 对 TASK-1 公共接口的任何变更：无。

## 新增/修改文件清单

- 新增：`entry/src/main/ets/pages/components/BackupExportSheet.ets`
- 新增：`entry/src/main/ets/viewmodel/BackupViewModel.ets`
- 新增：`entry/src/test/Task7Backup.test.ets`
- 新增：`TASKS/REPORT-7.md`
- 修改：`entry/src/main/ets/pages/RoomListPage.ets`
- 修改：`entry/src/main/ets/pages/RestoreBackupPage.ets`
- 修改：`entry/src/test/List.test.ets`

## 自验结果

- `.\hvigorw.bat assembleHap --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`，`BUILD SUCCESSFUL in 9 s 109 ms`，HAP 打包完成。输出警告仅来自既有播放器的 API 13 提示与弃用接口，本任务文件无新增编译警告。
- `.\hvigorw.bat test --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`，全部已注册 Hypium 用例无失败，`BUILD SUCCESSFUL in 9 s 678 ms`。测试源码共 78 个 `it` 声明，其中 TASK-7 新增 10 个。
- TDD 证据：新增测试首次运行因 `BackupViewModel` 尚不存在而按预期失败；实现后用例转绿。轮询测试注入即时 delay，核对 20 次调用的每次参数均为 2000ms。
- iOS 互通：字段齐全样例验证 `schemaVersion/exportedAt/iosConfig/server.rpc_bind/out_put_path/app_data_path/live_rooms/is_listening`；最小样例验证缺失字段归一化为空字符串、false 与空数组。
- 敏感信息检查：测试向原始服务端快照注入 `api_key/cookie/history`，最终 `BackupPackage.toJson()` 不含测试秘密值。
- 独立只读审查：复核端点目标、鉴权边界、导出并行、轮询、降级与测试覆盖，最终未发现 Critical/Important/Minor 问题，结论 Ready: Yes。
- 范围检查：`git diff -- entry/src/main/ets/pages/Index.ets README.md AppScope entry/src/main/resources` 为空；`TASKS/tools/` 保持用户原有未跟踪状态且不纳入提交。

## 遗留问题

- 需要在 API 21 真机连接实际主服务与备份源站，验证 DocumentViewPicker 文件 URI 写入/读取、系统取消返回、剪贴板、服务真实重启的 404/断连窗口及恢复后的 Navigation 返回体验。
- 无源站且主服务预取备份包失败时，按主控指定降级为继续服务端恢复并跳过设备侧 `iosConfig` 写回；此路径会保留现有设备网络配置。
