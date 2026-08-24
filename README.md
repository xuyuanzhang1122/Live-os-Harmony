# Live OS for HarmonyOS

Live OS 是 bililive 生态的 HarmonyOS 客户端，配套
[bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI) 使用。应用以鸿蒙原生 ArkUI 呈现视频库、直播间、观看历史和设置，并提供完整播放器与跨端备份恢复能力。

当前应用版本：`2.0.0`；Bundle Name：`com.xumy.liveos`。

## 功能

- 视频库：录播房间自适应网格、缩略图缓存、直播状态、视频列表、单项及批量删除。
- 直播间：增删直播间、监听启停、状态轮询、多行链接解析、备份导出。
- 观看历史：多用户 API Key 隔离、跨设备进度同步、续播、历史删除。
- 设置：手动/智能网络、API Key 验证与安全存储、备份源站、缓存管理、版本日志。
- 播放器：MP4/HLS、时间线、倍速、亮度/音量、横滑 seek、2 倍速锁定、续播与进度上报。
- 备份：本地 JSON、远端短 ID、主服务重启轮询、iOS 配置互通。

完整功能对齐状态见 [TASKS/docs/parity-checklist.md](TASKS/docs/parity-checklist.md)。

## 截图

> 截图占位：视频库（MatePad 横屏）

> 截图占位：播放器控制层

> 截图占位：设置与备份恢复

## 构建

### 环境

- 推荐使用 DevEco Studio 6.0.1 打开工程并配置自动签名。
- TASK-8 实际验收环境为 DevEco Studio 6.1.1、内置 API 24 SDK 与 Hvigor 6.24.4。
- 工程不显式写 `compileSdkVersion`，跟随 IDE；`targetSdkVersion = 6.0.1(21)`，`compatibleSdkVersion = 5.0.0(12)`。
- 目标设备为 Huawei MatePad 11.5，同时支持 phone、tablet 与 2in1。

### DevEco Studio

1. 用 DevEco Studio 6.0.1 或兼容的更高版本打开工程根目录。
2. 在项目签名设置中启用自动签名。
3. 连接 HarmonyOS 设备，选择 `entry` 模块运行。

### 命令行

Windows PowerShell：

```powershell
.\hvigorw.bat assembleHap --daemon=false
.\hvigorw.bat test --daemon=false
```

构建产物位于 `entry/build/default/outputs/default/`。包装脚本会探测 DevEco Studio 的 Node、JBR 与 SDK；环境差异详见 `TASKS/docs/CONVENTIONS.md`。

## 与 iOS 版的关系

鸿蒙版以 iOS Live OS 为行为参考：轮询间隔、续播边界、播放器手势几何、备份结构等契约保持一致；界面使用鸿蒙原生组件与系统主题 token，不机械复制 iOS 外观。无法直接等价的系统能力采用任务书规定的降级路径。

## 致谢

- bililive-go-UI：录播管理与媒体服务。
- Live OS iOS 版：功能和交互参考实现。
- pillarbox / contain 布局思路：播放器在不同视频与窗口比例下保持等比显示。
