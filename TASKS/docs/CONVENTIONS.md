# bililive-harmony 全局工程约定

所有任务书共享本约定。与任务书冲突时，以任务书为准；两者都未覆盖时，选择最贴近 iOS 参考实现的方案并在报告中说明。

## 1. 工程基本信息

| 项 | 值 |
|---|---|
| 工程根目录 | `D:\Users\Xumy\Downloads\bili-honmey\bililive-harmony\` |
| 应用名 | Live OS（显示名「Live OS」，支持中文环境） |
| Bundle Name | `com.xumy.liveos` |
| 模型 | Stage 模型，单 entry 模块 |
| 语言 | ArkTS（严格遵循 ArkTS 语法约束，见官方 ArkTS-coding-style） |
| 版本 | **实际环境**（TASK-0 核准）：DevEco Studio 6.1.1（安装于 `D:\DevEco Studio`），仅内置 API 24 SDK；Hvigor 拒绝显式 compileSdk 21，故**不写 compileSdkVersion（跟随 IDE = API 24）**；`targetSdkVersion = "6.0.1(21)"`；`compatibleSdkVersion = "5.0.0(12)"`。工程级 oh-package.json5 不声明 hvigor devDependencies（用 IDE 内置，ohpm 公共仓库无 6.24.x 包） |
| API 使用纪律 | compatible 为 API 12，但 compileSdk 是 24——编译器**不会**拦截 >12 的 API。因此：**任何 API 12 之后引入的接口必须做运行时特性检测/降级**（可用 `canIUse` 或 try-catch 包裹），且不得使用 API 21 之后才存在的接口（目标设备 MatePad 为 API 21） |
| 中文资源目录 | 限定词目录用 `zh_CN`（`zh-CN` 非法，资源编译器会报错） |
| 最低设备 | Huawei MatePad 11.5（2456×1600，约 819×533vp，平板横竖屏自适应）+ 普通手机 |

## 2. 目录结构（最终形态，各任务按需填充）

```
bililive-harmony/
├── AppScope/                      # app.json5、应用级资源
├── build-profile.json5            # 工程级构建配置（签名由用户在 IDE 配）
├── oh-package.json5               # 依赖（仅 hvigor 插件，不引入运行时三方依赖）
├── hvigor/ + hvigorw.bat          # 构建脚本
├── entry/
│   ├── build-profile.json5        # 模块构建配置
│   ├── oh-package.json5
│   └── src/
│       ├── main/
│       │   ├── module.json5       # 权限：INTERNET、VIBRATE；backgroundModes: audioPlayback
│       │   ├── resources/         # base + zh-CN + dark 模式资源
│       │   └── ets/
│       │       ├── entryability/EntryAbility.ets
│       │       ├── model/         # 纯数据模型（与 iOS Models/ 字段一致）
│       │       ├── net/           # APIClient、ApiCache
│       │       ├── cache/         # LruCache、ThumbnailCache
│       │       ├── config/        # AppConfig、NetworkMonitor
│       │       ├── player/        # PlayerController、ProgressTracker、SpeedLockStateMachine、PlayerMath
│       │       ├── viewmodel/     # 各页面 ViewModel
│       │       ├── pages/         # 页面与组件（含 pages/components/）
│       │       └── common/        # Theme、Haptics、Formats、Glass
│       └── test/                  # hypium 本地单元测试（纯逻辑）
├── TASKS/                         # 任务书、共享文档、REPORT-N.md（不参与构建）
├── README.md                      # TASK-8 编写
└── .gitignore
```

## 3. 架构与状态管理

- **MVVM**：页面（@Entry/@ComponentV2）尽量薄，业务放 ViewModel 类
- **状态管理统一用 ArkUI 状态管理 V2**：`@ObservedV2 + @Trace`（ViewModel、AppConfig）、`@Local`（页面私有）、`@Param/@Event`（组件入参/回调）、`@Monitor`（观测）。**禁止混用 V1 装饰器**（@Observed/@Prop/@Link/@ObjectLink）
- **AppConfig 是全局单例**（`AppConfig.getInstance()`），持有网络配置、API Key、activeURL、网络监听；通过 `@Provider/@Consumer` 或单例直取注入页面
- **页面导航**：根容器 `Tabs`（4 个页签，对应 iOS TabView）+ 每页签独立 `Navigation`（NavPathStack）；二级页 push NavDestination；**播放器用 `bindContentCover` 全屏模态**（对应 iOS fullScreenCover）；底部弹层用 `bindSheet`（对应 iOS sheet）
- **轮询刷新统一模式**：页面 `onPageShow` 启动 10 秒间隔定时器、`onPageHide` 停止；同时 onPageShow 立即拉一次（对应 iOS「10 秒轮询 + 回前台刷新」）

## 4. 命名与代码风格

- 文件名大驼峰与类型同名（`APIClient.ets` 例外，保持与 iOS 同名）；目录小写
- 类/接口大驼峰；方法/变量小驼峰；常量全大写下划线；私有成员 `_` 前缀或 private 修饰
- 所有用户可见文案使用中文，集中在页面内定义或 `$r('app.string.*')`（页面内直接中文字符串即可，不必强行资源化）
- 注释只写「代码本身表达不了的约束」，密度对齐 iOS 源码（低密度）
- 错误处理：网络/解析错误统一抛 `ApiError`（见 model/Common.ets），页面 catch 后映射为中文文案展示

## 5. 网络层约定

- 只允许通过 `net/APIClient.ets` 发请求；页面/VM 不得自行 `http.createHttp`（备份源站上传也走 APIClient 的独立 base URL 参数）
- 鉴权：默认 `Authorization: Bearer {apiKey}`；媒体/缩略图 URL 用 `?_key=` query（由 APIClient 的 URL 构造方法统一处理，见 API-CONTRACT.md）
- 明文 HTTP（局域网地址）默认可用；如遇系统限制，在模块配置补充 cleartext 放行并在报告说明
- 超时：普通请求 15s；LAN 探测 2s（见 NetworkMonitor 规格）

## 6. 持久化约定

| 数据 | 手段 |
|---|---|
| serverURL/lanURL/publicURL/autoSwitchNetwork/backupServerURL | `@ohos.data.preferences`（文件 `config`） |
| API Key | Asset Store Kit（关键资产，alias `api_key`）；API 不可用或失败时回退 preferences 存储，读写路径集中封装在 AppConfig，其他模块无感知 |
| API JSON 缓存 | `cacheDir/api-cache/`，30 分钟 TTL |
| 缩略图磁盘缓存 | `cacheDir/thumbnails/`，文件名 = URL 的 SHA-256 十六进制 |

## 7. 视觉约定

- 品牌主色（accent）：`#1FDBC7`（青绿，来自 iOS RGB(0.12,0.86,0.78)），用于进度条、选中态、强调按钮；资源名 `brand_color`（含 dark 变体）
- 整体 UI 用鸿蒙原生风格（系统 List/Grid/Dialog/Menu/Refresh、系统圆角与间距规范），不强仿 iOS 视觉；播放器页强制暗色
- 毛玻璃效果用 `backgroundBlurStyle`（对应 iOS Liquid Glass 回退 ultraThinMaterial 的位置：警告横幅、BoundKeyCard、HUD 底衬）
- 图标优先 `SymbolGlyph($r('sys.symbol.xxx'))`，无合适符号时用简单自绘或文本占位；**所用资源必须真实存在可编译**
- 适配：用 `GridRow/GridCol` 或按宽度计算列数；列表/网格在 ≥840vp（平板横屏）与窄屏下均合理展示；禁止写死 2456×1600 像素值

## 8. 行为对齐总原则（最高优先级）

1. **凡任务书给出精确数值/规则的行为（轮询间隔、5 秒规则、手势几何、轮询次数等），必须逐字实现**，这些是从 iOS 源码提取的契约
2. iOS 未实现的特性鸿蒙也不实现（例：iOS 用 10 秒轮询而非 SSE，鸿蒙同样用轮询）
3. 鸿蒙无法等价实现的 iOS 能力（如系统级音量 hack），按任务书给出的降级方案执行

## 9. Git 约定

- TASK-0 执行 `git init`；`.gitignore` 忽略 `build/`、`.hvigor/`、`.idea/`、`local.properties`、`oh_modules/`、`*.hap`、`.DS_Store`
- **每个任务一次提交**，提交信息：`TASK-N: 简述`（修复则 `TASK-N-fix: 简述`），便于主控 diff 审查
- 禁止 push 到远端；禁止 rebase/修改历史提交

## 10. 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false      # 编译必须通过（产物无需签名）
hvigorw.bat test --daemon=false             # 单元测试必须全绿（若命令不可用，报告说明并保证 IDE 可跑）
```

若 `hvigorw.bat` 找不到 SDK/Node：设置 `DEVECO_SDK_HOME`、`NODE_HOME`（指向 DevEco Studio 安装目录下对应子目录），详见 TASK-README.md「环境备忘」。

## 11. 通用禁止事项（每个任务都适用）

1. 只允许修改 `bililive-harmony\` 目录内文件；**严禁改动** `bililive-go-UI\`、`bililive-ios\`、`bililive-server-update\`
2. 不引入任何运行时三方 ohpm 依赖（系统 Kit 足够）；确有必要时在报告中说明并等待主控确认后再动手
3. 不删除/重命名 CONVENTIONS 与任务书已定义的公共接口（APIClient 方法、AppConfig 接口、模型字段）；必须变更时在报告「实现说明」中显著标注
4. 不修改 `TASKS\docs\` 下的共享文档；发现文档错误时在报告中指出
5. **只做当前任务书（TASK-N）范围内的事**：严禁提前实施后续任务（TASK-N+1 及以后）的任何功能、页面、文件——后续任务有独立验收与前置依赖，提前实现一律视为本任务验收失败
6. 每个任务完成必须：自验命令通过 + 写 REPORT-N.md + git 提交，三者缺一视为未完成

## 12. REPORT-N.md 模板（每个任务完成后必须写，N = 任务号）

文件位置：`TASKS\REPORT-N.md`（修复后更新原文件）。结构固定：

```markdown
# REPORT-N：<任务标题>

## 完成项
（对照任务书验收标准逐条列出，✅/❌ + 一句话证据，如「✅ 编译通过：hvigorw assembleHap 输出 BUILD SUCCESSFUL」）

## 实现说明
- 关键设计决策与理由（任务书留白处的选择）
- 与任务书的偏差及原因（没有则写「无」）
- 对 TASK-1 公共接口的任何变更（没有则写「无」）

## 新增/修改文件清单
（路径列表，标注 新增/修改）

## 自验结果
（执行的命令 + 关键输出摘要：编译结果、测试通过数）

## 遗留问题
（未完成项、已知风险、需要真机验证的项；没有则写「无」）
```
