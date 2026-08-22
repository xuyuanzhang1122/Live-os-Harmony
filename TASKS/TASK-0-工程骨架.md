# TASK-0：工程骨架

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、`TASKS/docs/API-CONTRACT.md`（本任务主要用 CONVENTIONS）。

## 前置条件

无（这是第一个任务）。`bililive-harmony\` 下当前只有 `TASKS\` 目录。

## 目标

在 `D:\Users\Xumy\Downloads\bili-honmey\bililive-harmony\` 创建可编译的 DevEco Studio Stage 模型工程：4 页签主框架 + Navigation 骨架 + 主题资源 + 权限声明 + git 仓库。

## 详细规格

### 1. 工程文件

手写完整 Stage 工程文件（用户已装 DevEco Studio 6.0.1，可直接打开构建）：

- `AppScope/app.json5`：bundleName `com.xumy.liveos`，versionCode 1，versionName `2.0.0`（与 iOS 版本号对齐）
- `AppScope/resources/base/element/string.json`：app_name = `Live OS`
- `build-profile.json5`（工程级）：compileSdkVersion 21、compatibleSdkVersion 12、targetSdkVersion 21；签名配置留空（用户在 IDE 自动签名）
- `oh-package.json5`（工程级）：仅 hvigor 相关 devDependencies
- `hvigor/`（hvigor-config.json5 等）+ `hvigorw`/`hvigorw.bat` 包装脚本
- `entry/` 模块：`build-profile.json5`、`oh-package.json5`、`src/main/module.json5`、资源、ets 源码
- `.gitignore`（按 CONVENTIONS §9）

**获取 hvigor 脚本与版本号的建议做法**：DevEco Studio 安装目录（常见 `C:\Program Files\Huawei\DevEco Studio`）内有工程模板与 hvigor 发行版，找到模板（如 `templates\` 或 `plugins\` 下的 Empty Ability 模板）复制其 hvigorw、hvigor 配置与 oh-package 依赖版本；找不到就按官方 Stage 工程结构手写，版本取 DevEco 6.0.1 对应的 hvigor 5.x。以 `hvigorw.bat assembleHap` 实际跑通为准。

### 2. module.json5 要点

- entry 顶层配置：mainAbility 指向 EntryAbility，`deviceTypes: ["tablet", "phone", "2in1"]`
- **requestPermissions**：`ohos.permission.INTERNET`、`ohos.permission.VIBRATE`（均 system_grant）
- EntryAbility 的 `backgroundModes: ["audioPlayback"]`（后续播放器后台/PiP 用）
- pages 注册 `pages/Index`
- orientation：不锁定方向（autoRotate），平板横竖屏均支持

### 3. 主框架（pages/Index.ets）

复刻 iOS `ContentView.swift` 的结构（4 页签 TabView）：

- `Tabs` 组件，barPosition 底部，4 个页签：**视频库、直播间、历史、设置**（文案与顺序与 iOS 完全一致）
- 每个页签内容 = 独立 `Navigation`，标题分别为「视频库」「直播间」「观看历史」「设置」，`NavDestination` 路由表留好（后续任务往里加页面）
- 每个页签当前显示居中占位文本（如「视频库 - 待实现（TASK-2）」），说明各页签由后续任务填充
- 页签切换时调用 `common/Haptics.ets` 的轻触觉（本任务先建好 Haptics 封装，内部用 `@ohos.vibrator`，调用失败静默忽略）
- 应用品牌色 `#1FDBC7` 设为 Tabs 选中色等强调位置

参考 iOS：`D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\ContentView.swift`（注意路径含空格）。

### 4. EntryAbility 与窗口

- `EntryAbility.ets`：onWindowStageCreate 加载 `pages/Index`；在 `onCreate` 里初始化全局 `AppConfig` 单例（本任务可先建空壳类 `config/AppConfig.ets`，只含单例骨架与「activeURL 为空」状态，TASK-1 填充实现）
- 窗口不写死尺寸，跟随系统；平板上 Tabs 布局自适应

### 5. 资源

- `resources/base/element/color.json`：`brand_color` = `#1FDBC7`，dark 变体同色
- `resources/base/element/string.json` + `resources/zh-CN/element/string.json`：app_name 等
- 应用图标：`resources/base/media/` 放占位图标（自绘简单 PNG，如青绿底 + 白色播放三角；可用脚本生成任意合法 PNG，尺寸 216×216 与 app.json5 引用一致即可，TASK-8 再换正式图标）
- 页签图标：优先 `SymbolGlyph($r('sys.symbol.xxx'))`（如视频库/信号/时钟/齿轮方向），**必须选用真实存在的 sys.symbol 资源名**；找不到合适的就用文字页签（鸿蒙 Tabs 支持），不要用不存在的资源导致编译失败

### 6. common 目录骨架

- `common/Theme.ets`：品牌色常量、常用圆角/间距常量
- `common/Haptics.ets`：`light()/medium()/selection()` 三个方法封装 vibrator，带 API 可用性 try-catch
- `common/Formats.ets`：空实现占位（TASK-1 填充）

### 7. git

- `git init` + 首次提交 `TASK-0: 工程骨架`（.gitignore 生效，TASKS 目录一并纳入版本管理）

## 验收标准

- [ ] 工程文件齐全，`hvigorw.bat assembleHap --daemon=false` 在工程根目录执行成功（无签名要求，产物可为 unsigned）
- [ ] DevEco Studio 打开工程无结构错误（module.json5 可解析、pages 注册齐全、资源引用真实存在）
- [ ] 4 页签 Tab 框架 + 每页签 Navigation 骨架编译通过；页签文案为 视频库/直播间/历史/设置
- [ ] module.json5 含 INTERNET、VIBRATE 权限与 audioPlayback 后台模式
- [ ] Haptics 封装存在且页签切换调用（无振动设备上静默失败）
- [ ] 品牌色 #1FDBC7 生效于页签选中态
- [ ] git 仓库初始化且首次提交完成，`git status` 干净

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false
git log --oneline
```

## 禁止事项

通用禁止事项见 CONVENTIONS §11。另：本任务不实现任何网络请求与真实页面逻辑；不创建 TASK-1 及以后才建的目录文件。
