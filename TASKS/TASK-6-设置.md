# TASK-6：设置全套（网络配置 / API Key / 存储 / 关于）

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md` 与 `TASKS/REPORT-1.md`。

## 前置条件

TASK-0、TASK-1 完成（本任务不依赖 TASK-2~5 的任何实现）。

> 主控调整：执行顺序提前为 0 → 1 → 2 → **6** → 3 → 4 → 5 → 7 → 8，目的是让用户在 TASK-2+6 完成后就能真机配置服务器并实测视频库。「恢复备份」子页仍为占位（TASK-7 填充），不受影响。

## 目标

实现第 4 页签「设置」主页面与全部子页：网络配置（含智能切换）、API Key 绑定、存储管理、关于与版本日志；以及备份源站 URL 配置行。

## 必读参考（iOS 源码）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\SettingsView.swift`（主页面 + NetworkConfigView + APIKeyView + StorageManagementView + AboutVersionView 都在此文件）

## 详细规格

### 1. 设置主页（pages/SettingsPage.ets，替换第 4 页签占位）

List 分组卡片样式（鸿蒙原生 List + 分组），**5 个分组与 iOS 一致**：

1. **服务器**
   - 「网络配置」行 → push NetworkConfigPage；副标题：智能模式显示「智能切换 · 局域网/公网」，手动显示当前 serverURL（无则「未配置」）
   - 「恢复备份」行 → push RestoreBackupPage（**页面本任务建占位**：「恢复备份将在 TASK-7 实现」，TASK-7 填充）
   - 「连接状态」行：右侧「测试」按钮 → `getServerInfo()`，成功显示 `app_name + app_version` + 网络 wifi/蜂窝图标（isOnLAN 用 wifi 图标，否则地球图标）；失败显示红色「连接失败」
   - 「服务器版本」行：显示最近一次 getServerInfo 的 app_version（无则 `-`）
2. **备份服务器（源站）**
   - URL 输入框行（直接编辑 `AppConfig.backupServerURL`，失焦保存）；footer：「配置后远端备份上传到该服务器，主服务器重装后仍可凭 ID 找回；留空则存主服务器」
3. **认证**
   - 「API Key」行 → push ApiKeyPage；副标题：未设置 / 已配置（••••+末 4 位——key_suffix 或本地 key 末 4 位）
   - footer：「在服务端 Web 设置页开启 API Key 后填入，各设备进度互不串扰」
4. **存储**
   - 「存储管理」行 → push StorageManagementPage；副标题：「已用 X.X MB」（两个缓存目录合计）
5. **关于**
   - 「版本」行 → push AboutPage（副标题 2.0.0）
   - 「GitHub」行 → 打开 `https://github.com/xuyuanzhang1122/bililive-harmony`（StartAbility 或复制链接二选一，报告注明）
   - 署名行：「由 Xumy 开发」

### 2. 网络配置页（pages/NetworkConfigPage.ets）

- 分段选择器（手动 / 智能切换）：
  - **手动**：单个服务器地址输入框（serverURL）
  - **智能**：局域网地址（lanURL，说明「在家或店里速度最快」）+ 公网地址（publicURL，说明「端口转发 / frp / cloudflare 均可」）
- 「当前连接」状态卡（智能模式）：实时显示 当前走 LAN 还是公网、实际 activeURL、探测中状态（刷新按钮手动重测 = `refreshNetworkStatus()`）
- 保存按钮 → 写 AppConfig（持久化）→ 触发 `refreshNetworkStatus()` → 底部「已保存」胶囊 1.5s 消失
- 输入校验：URL 必须 http/https 开头；智能模式两地址至少填一个才可保存

### 3. API Key 页（pages/ApiKeyPage.ets）

- 密码输入框 + 眼睛按钮切换明文/密文
- 「测试并绑定」按钮：**新建临时 APIClient（用输入的 key + 当前 activeURL）**调 `getAuthMe()`：
  - 成功 → `AppConfig.setApiKey()` 保存 + 显示 **BoundKeyCard**（毛玻璃卡片）：
    - 圆形头像块（用户名首字母，品牌色底）
    - 用户名、User ID
    - `•••• + key_suffix`（无 suffix 用本地 key 末 4 位）
    - 「已同步」云徽章
    - 两行说明：「此设备会只读取该用户的服务端观看历史」「退出播放器时把最新进度同步回后端」
  - 失败 → 红色错误区显示 ApiError 中文文案（401/403 → 「API Key 无效或未开启鉴权」）
- 「清除已保存的 Key」按钮（红色，确认弹窗）→ `clearApiKey()`，页面回到未绑定态
- 已绑定状态进入页面：直接显示 BoundKeyCard（key 从 AppConfig 读）

### 4. 存储管理页（pages/StorageManagementPage.ets）

- 两行：缩略图缓存（ThumbnailCache.sizeBytes）、接口数据缓存（ApiCache.sizeBytes），各显示 formatBytes
- 合计行
- 「清除所有缓存」按钮（红色）→ 确认弹窗 → 两个 `clearAll()/clear()` → 「已清除」toast 2 秒
- 清除后大小显示归零（重新统计）

### 5. 关于页（pages/AboutPage.ets）

版本日志列表（对照 iOS AboutVersionView，三条）：

- **2.0**（品牌色强调）：备份服务器（源站）支持；恢复备份自动写回配置并重启服务、双端重新同步；直播间页一键导出（本地文件 + 云端短 ID）；修复续播不精确；长按两侧下拉锁定 2 倍速；直播中标识自动刷新；适配新系统设计规范
- **1.2**：品牌启动动效；缩略图会话缓存；存储管理；进度条拖动修复
- **1.1**：毛玻璃主页；多用户 API Key 隔离；备份与进度双向同步重构；全局触觉反馈

（每条带图标 + 版本号 + 文案列表，视觉鸿蒙化即可，内容不改）

## 验收标准

- [ ] 5 分组结构与行项齐全，副标题动态正确（网络模式、Key 末 4 位、缓存大小、版本号）
- [ ] 连接测试走 getServerInfo，成功/失败态与图标正确；备份源站 URL 可编辑保存
- [ ] 网络配置：手动/智能切换、必填校验、保存胶囊、「当前连接」实时卡、保存触发 refreshNetworkStatus
- [ ] API Key：临时 client 测试（不用保存的 key 测试错误输入）、BoundKeyCard 完整、清除有确认
- [ ] 存储管理：统计准确（有数据时 >0）、清除生效、toast 反馈
- [ ] 关于页三条版本日志内容完整
- [ ] 恢复备份占位页存在（TASK-7 填充）
- [ ] 编译 + 测试全绿；git 提交 `TASK-6: 设置`

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
```

## 禁止事项

通用见 CONVENTIONS §11。另：恢复备份页只建占位；不改 AppConfig 公共接口（如需加字段在报告说明）。
