# REPORT-0：工程骨架

## 完成项

- ✅ 工程文件齐全：Stage 模型、单 entry 模块、AppScope、Hvigor 配置及双平台包装脚本均已创建。
- ✅ 编译通过：`hvigorw.bat assembleHap --daemon=false` 输出 `BUILD SUCCESSFUL`，生成 `entry-default-unsigned.hap`。
- ✅ 工程结构有效：Hvigor 已完成资源编译、ArkTS 编译和 HAP 打包，`module.json5` 与 `pages/Index` 均可解析。
- ✅ 四页签框架完成：视频库、直播间、历史、设置顺序与 iOS 一致，每个页签使用独立 `NavPathStack` 和 `Navigation`。
- ✅ Navigation 骨架完成：四个页签标题分别为视频库、直播间、观看历史、设置，并统一注册空 `NavDestination` 路由表。
- ✅ 权限与后台模式完成：声明 INTERNET、VIBRATE，以及 EntryAbility 的 `audioPlayback`。
- ✅ 触觉封装完成：`Haptics.light()`、`medium()`、`selection()` 均使用系统 vibrator，页签切换调用 `selection()`，失败静默忽略。
- ✅ 主题资源完成：浅色和深色资源中的 `brand_color` 均为 `#1FDBC7`，页签选中文案使用该资源。
- ✅ 自适应基础完成：窗口不设置固定尺寸，Ability 使用 `auto_rotation`，支持 tablet、phone、2in1。
- ✅ 图标完成：AppScope 与 entry 均使用确定性生成的 216×216 PNG，占位图为青绿底白色播放三角。
- ✅ 基础单测通过：`hvigorw.bat test --daemon=false` 输出 `BUILD SUCCESSFUL`，验证 AppConfig 单例和初始空 `activeURL`。
- ✅ Git 仓库已初始化：构建、测试与任务报告完成后按要求创建首次提交。

## 实现说明

- 关键设计决策：页签图标采用任务书允许的纯文字页签，避免引用不同 SDK 版本中可能不存在的 `sys.symbol` 资源；选中态通过品牌色和中等字重区分。
- 关键设计决策：四个页签各自持有独立 `NavPathStack`，共用一个空的 `NavDestination` builder，后续任务可在不改变根 Tabs 结构的情况下增加二级页面。
- 关键设计决策：触觉使用 8/10/20ms 的短时 `touch` 振动分别表达 selection/light/medium，不依赖设备厂商预设 effectId。
- 关键设计决策：资源限定目录使用 HarmonyOS 实际识别的 `zh_CN`，对应任务书中的中文环境 `zh-CN`；使用字面 `zh-CN` 会被资源编译器视为非法限定目录。
- 关键设计决策：本机实际安装路径为 `D:\DevEco Studio`，版本为 DevEco Studio 6.1.1、内置 Hvigor 6.24.4；包装脚本优先读取 `DEVECO_HOME`/`DEVECO_SDK_HOME`，并保留本机安装路径和标准 Program Files 路径回退，同时自动设置 Node、JBR 和 SDK 环境。
- 与任务书的偏差：本机并非任务书记录的 DevEco Studio 6.0.1，而是 6.1.1，且仅安装 API 24 SDK。Hvigor 6.24.4 会拒绝显式 `compileSdkVersion: 6.0.1(21)`，错误为 `compileSdkVersion is incompatible ... configured version: 21, DevEco Studio version: 24`。因此按 Hvigor 官方报错建议省略 `compileSdkVersion`，实际使用 IDE 内置 API 24 编译；`targetSdkVersion` 仍严格为 `6.0.1(21)`，`compatibleSdkVersion` 为 `5.0.0(12)`。这是同时满足当前环境可编译和目标系统行为的最小偏差。
- 与任务书的偏差：工程级 `oh-package.json5` 的 Hvigor devDependencies 保持为空，使用 DevEco 内置 Hvigor；6.24.4 的 `@ohos/hvigor` 包不发布在 ohpm 公共仓库，声明后会导致 `ohpm install` 404。entry 仅增加测试期 `@ohos/hypium` 1.0.18，不属于运行时依赖。
- 对 TASK-1 公共接口的任何变更：无。`AppConfig.getInstance()` 与 `activeURL` 按任务书只提供空壳，未实现 TASK-1 持久化或网络功能。

## 新增/修改文件清单

- 新增：`.gitignore`
- 新增：`AppScope/app.json5`
- 新增：`AppScope/resources/base/element/string.json`
- 新增：`AppScope/resources/base/media/app_icon.png`
- 新增：`AppScope/resources/zh_CN/element/string.json`
- 新增：`build-profile.json5`
- 新增：`oh-package.json5`
- 新增：`hvigorfile.ts`
- 新增：`hvigor/hvigor-config.json5`
- 新增：`hvigorw`
- 新增：`hvigorw.bat`
- 新增：`entry/build-profile.json5`
- 新增：`entry/hvigorfile.ts`
- 新增：`entry/oh-package.json5`
- 新增：`entry/oh-package-lock.json5`
- 新增：`entry/src/main/module.json5`
- 新增：`entry/src/main/ets/entryability/EntryAbility.ets`
- 新增：`entry/src/main/ets/pages/Index.ets`
- 新增：`entry/src/main/ets/config/AppConfig.ets`
- 新增：`entry/src/main/ets/common/Theme.ets`
- 新增：`entry/src/main/ets/common/Haptics.ets`
- 新增：`entry/src/main/ets/common/Formats.ets`
- 新增：`entry/src/main/resources/base/element/color.json`
- 新增：`entry/src/main/resources/base/element/string.json`
- 新增：`entry/src/main/resources/base/media/app_icon.png`
- 新增：`entry/src/main/resources/base/profile/main_pages.json`
- 新增：`entry/src/main/resources/dark/element/color.json`
- 新增：`entry/src/main/resources/zh_CN/element/string.json`
- 新增：`entry/src/test/List.test.ets`
- 新增：`TASKS/REPORT-0.md`

## 自验结果

- `hvigorw.bat assembleHap --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`、`BUILD SUCCESSFUL in 7 s 237 ms`，产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`。唯一警告为任务预期的未配置签名。
- `hvigorw.bat test --daemon=false`：通过；`BUILD SUCCESSFUL in 7 s 344 ms`，TASK-0 冒烟测试完成编译和本地执行流程。
- 静态契约脚本：21 项通过；核对 bundle/version、SDK target/compatible、设备类型、权限、后台模式、自动旋转、4 个 TabContent、4 个 Navigation、页签文案、触觉调用、品牌色、HAP 存在且非空、Git 初始化。
- 图标检查：AppScope 与 entry 的 `app_icon.png` 均为合法 PNG，尺寸均为 216×216。

## 遗留问题

- 需要用户在 DevEco Studio 中配置自动签名并进行 MatePad/手机真机布局与振动体验验证。
- 如主控要求工程文件显式保留 `compileSdkVersion = 21`，需另行安装 DevEco Studio 6.0.1/API 21 工具链后再恢复该字段；当前 DevEco Studio 6.1.1/API 24 明确拒绝该配置。
