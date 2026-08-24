# 🧭 Live OS for HarmonyOS

Live OS 是 bililive 生态的**鸿蒙原生客户端**（ArkUI / Stage 模型），配套
[⚙️ bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI) 录播主服务使用，与
[📱 bililive-ios](https://github.com/xuyuanzhang1122/bililive-ios) 功能 1:1 对齐。

当前应用版本：`2.0.0`；Bundle Name：`com.xumy.liveos`。

> ⚠️ **服务端要求 v2.0.2 及以上**：v2.0.1 及之前为 iOS 优先的 HLS 形态，鸿蒙端部分格式不可播；[v2.0.2](https://github.com/xuyuanzhang1122/bililive-go-UI/releases/tag/v2.0.2) 起双端兼容。

## ✨ 能做什么

- 📺 **视频库**：录播房间自适应网格、缩略图缓存、直播状态、视频列表、单项及批量删除
- 🎙️ **直播间**：增删直播间、监听启停（乐观更新）、状态轮询、多行链接解析、备份导出
- 🕘 **观看历史**：多用户 API Key 隔离、跨设备进度同步、续播、历史删除
- ⚙️ **设置**：手动/智能网络、API Key 验证与安全存储、备份源站、缓存管理
- 🎮 **播放器**：MP4/HLS 双路径、时间线拖动、倍速、亮度/音量、横滑 seek、2 倍速锁定、画中画、续播与进度上报
- ☁️ **备份**：本地 JSON、远端短 ID、恢复重启轮询，备份包与 iOS 完全互通
- 🔔 **系统级体验**：品牌启动动画、触觉反馈、深色模式、手机/平板/2in1 自适应大屏布局

完整功能对齐状态见 [TASKS/docs/parity-checklist.md](TASKS/docs/parity-checklist.md)（约 70 项逐条核对）。

## 📥 下载与安装

> [Releases](https://github.com/xuyuanzhang1122/Live-os-Harmony/releases) 页提供构建好的 `.hap`。

- 附带的 `.hap` 为**调试签名**（绑定作者设备 UDID），其他设备直接安装会签名校验失败
- 其他设备请自行构建：DevEco Studio 6.0.1+ 打开工程 → Signing Configs 启用**自动签名**（需华为开发者账号，调试证书有效期一年）→ 连接设备运行 `entry` 模块
- 调试签名一年到期后重新生成签名再装机即可，覆盖安装数据不丢

## 📸 截图

> 截图占位：视频库（MatePad 横屏）

> 截图占位：播放器控制层

> 截图占位：设置与备份恢复

## 🛠️ 构建

### 环境

- 推荐使用 DevEco Studio 6.0.1 打开工程并配置自动签名；实际验收环境为 DevEco Studio 6.1.1、内置 API 24 SDK 与 Hvigor 6.24.4
- 工程不显式写 `compileSdkVersion`，跟随 IDE；`targetSdkVersion = 6.0.1(21)`，`compatibleSdkVersion = 5.0.0(12)`（最低兼容 HarmonyOS 5.0 / API 12）
- 目标设备为 Huawei MatePad 11.5（2456×1600），同时支持 phone、tablet 与 2in1

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

## 🧩 项目生态

这套东西是三个仓库配合的，各管一摊：

| 仓库 | 状态 | 管什么 |
|------|------|--------|
| **[bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI)** | ✅ 开源 | 录播主服务、Web UI、全部核心 API（需 v2.0.2+） |
| **Live-os-Harmony**（本仓库） | ✅ 开源 | 鸿蒙原生 App |
| **[bililive-ios](https://github.com/xuyuanzhang1122/bililive-ios)** | ✅ 开源 | iOS 原生 App（本项目的行为参考实现） |

## 🧬 与 iOS 版的关系

鸿蒙版以 iOS Live OS 为行为参考：轮询间隔、续播边界、播放器手势几何、备份结构等契约保持一致；界面使用鸿蒙原生组件与系统主题 token，不机械复制 iOS 外观。无法直接等价的系统能力采用任务书规定的降级路径。

## 🙏 致谢

- [bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI)：录播管理与媒体服务
- Live OS iOS 版：功能和交互参考实现，启动/图标资产同源
- [pillarbox-apple](https://github.com/SRGSSR/pillarbox-apple) 的 pillarbox / contain 布局思路：播放器在不同视频与窗口比例下保持等比显示
