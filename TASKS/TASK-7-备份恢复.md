# TASK-7：备份导出与恢复（含云备份短 ID 找回）

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md`（重点 §2.6、§2.7、§3、§4、§5）与 `REPORT-1.md`、`REPORT-6.md`。

## 前置条件

TASK-0 ~ TASK-6 完成。

## 目标

实现备份体系：直播间页「导出备份」Sheet（本地文件 + 云上传短 ID）、设置页「恢复备份」页（按 ID 找回 / 本地文件恢复 + 预览确认 + 重启轮询 + 配置写回）。**备份包格式与 iOS 完全互通。**

## 必读参考（iOS 源码）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\RoomListView.swift`（BackupExportSheet 部分）
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\SettingsView.swift`（RestoreBackupView + BackupPreview）
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Models\BackupModels.swift`
- 模型与序列化 TASK-1 已实现（BackupPackage 等），直接用

## 详细规格

### 1. 导出备份 Sheet（挂到直播间页工具栏，补上 TASK-5 预留的「导出备份」按钮）

bindSheet 底部弹层，打开后**两步并行**：

**步骤 A：组包并保存本地**
1. `getServerConfig()` 取服务端快照（rpc.bind / out_put_path / app_data_path / live_rooms）
2. 设备侧配置取自 AppConfig（serverURL/lanURL/publicURL/autoSwitchNetwork → `iosConfig` 四字段，**字段名不改**）
3. `BackupPackage.fromServerConfig(...)` 组包（exportedAt = 当前 UTC ISO8601）
4. `DocumentViewPicker.save` 保存 JSON 文件，文件名 `bililive-harmony-backup-{unix秒}.json`（用户取消不视为失败）

**步骤 B：云上传**
- 目标选择：`backupServerURL` 非空 → 源站（`uploadBackup('backup', pkg)`）；为空 → 主服务（`uploadBackup('main', pkg)`）
- 成功：显示备份 ID（大字号等宽）+ 「复制」按钮（`@ohos.pasteboard` 复制完整 ID）+ 状态文案：
  - 源站：「已上传到备份服务器」
  - 主服务：「已上传到主服务器（建议配置备份服务器）」
- 失败（404/405 或网络错误）：显示「当前服务器暂不支持备份接口，已保留本地文件」；本地文件流程不受影响
- 上传中显示 loading 态

### 2. 恢复备份页（pages/RestoreBackupPage.ets，替换 TASK-6 占位）

两种入口 Tab/分段切换：

**按短 ID 恢复**
1. 输入框粘贴备份 ID（如 `bgo_20260504_abcd2345efgh6`）
2. 「找回并恢复」：
   - `backupServerURL` 非空：`fetchBackupPackage('backup', id)` 从源站取包 → `restoreBackup({package: 整包})` 发给**主服务**
   - 为空：直接 `restoreBackup({id})` 让主服务自己取
3. 进入轮询（见下）

**按本地文件恢复**
1. `DocumentViewPicker.select` 选 JSON → 解析 `BackupPackage`（解析失败 toast「不是有效的备份文件」）
2. **预览卡**（对应 iOS BackupPreview）：导出时间、服务器模式（rpc_bind / 输出目录）、直播间数量、（若 iosConfig 非空）设备配置摘要
3. 「恢复这个备份」→ `restoreBackup({package: 整包})` → 进入轮询

**重启轮询（规则精确实现）**
- restore 响应含 `job_id` 且 `status ∈ {pending, running, restarting}` → 每 **2 秒**查 `getRestoreStatus(jobId)`，最多 **20 次**（40 秒）
- **轮询中收到 404（getRestoreStatus 返回 null）→ 视为重启完成**（服务重启后内存任务表丢失，这是与后端的约定行为）
- 连接失败（网络错误）→ 属预期，继续轮询不中断
- `status = completed` 或上述「404 判完成」→ 恢复成功流；20 次耗尽 → 「恢复超时，请手动检查服务器」
- 轮询期间 UI 显示进行中状态（转圈 + 服务端 message）

**恢复成功后（applyDeviceConfig，对齐 iOS applyIOSConfig）**
1. 把包内 `iosConfig` 写回 AppConfig：serverURL/lanURL/publicURL/autoSwitchNetwork（**保留现有 API Key 不动**）
2. 立即 `refreshNetworkStatus()` 重测网络
3. toast 服务端返回的 message（如「配置已写入，正在重启服务」/「服务已恢复」）
4. 返回设置页，各页签数据下次显示时自动用新配置

## 验收标准

- [ ] 导出：并行两步、本地文件名格式正确、JSON 为排序 key + iosConfig 字段名（与 TASK-1 序列化一致）
- [ ] 上传目标选择正确（源站优先/主服务回落）；两种成功文案区分；404/405 降级文案；复制 ID 可用
- [ ] 按 ID：源站取包+主服务恢复 / 无源站直接 id 恢复，两条路径端点正确
- [ ] 本地文件：选择→解析→预览卡（导出时间/模式/房间数）→确认恢复
- [ ] 轮询：2s×20、404=完成、连接失败继续、超时提示
- [ ] 恢复成功写回 iosConfig 四字段且保留 API Key、触发 refreshNetworkStatus、toast 服务端 message
- [ ] 用 iOS 导出的备份 JSON 可在鸿蒙端解析并恢复（字段互通，报告注明已用样例验证解析）
- [ ] 编译 + 测试全绿；git 提交 `TASK-7: 备份恢复`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：绝不往备份包写入 API Key/Cookie/签名 URL/观看历史；不改备份包 schema 字段名（互通 iOS 是硬约束）。
