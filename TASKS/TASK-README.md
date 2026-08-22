# bililive-harmony 任务书总览与工作流

本目录包含鸿蒙版 Live OS 的全部实施任务书。工作模式：**主控 AI（ZCode）拆任务与验收，Codex 实施，用户传递**。

## 项目背景

为 bililive 生态（直播录播）开发鸿蒙客户端，功能与 iOS 版 [Live OS] 1:1 对齐，UI 采用鸿蒙原生风格，页面操作一致。

- **目标设备**：Huawei MatePad 11.5（2456×1600，横屏平板），同时自适应手机布局
- **系统版本**：HarmonyOS 6.0.1（API 21）；最低兼容 API 12（HarmonyOS 5.0）
- **开发语言**：ArkTS（Stage 模型，ArkUI 声明式）
- **IDE**：DevEco Studio 6.0.1（已安装在用户本机 Windows）
- **参考实现**：iOS App 源码位于 `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\`（实施者可直接阅读对照）
- **后端服务**：bililive-go-UI（主服务）+ bililive-server-update（备份源站），API 契约见 `docs/API-CONTRACT.md`

## 任务依赖图

```
TASK-0 工程骨架
   └─ TASK-1 基础设施（模型/网络/缓存/配置）
        ├─ TASK-2 视频库 + 视频列表
        │    └─ TASK-3 播放器核心（AVPlayer/控制层/单击双击）
        │         └─ TASK-4 播放器完整手势（seek/音量亮度/2x锁/续播/上报/PiP）
        ├─ TASK-5 直播间管理 + 观看历史
        └─ TASK-6 设置全套
             └─ TASK-7 备份导出与恢复
                  └─ TASK-8 打磨与总验收
```

严格按编号顺序执行；TASK-2/5/6 在 TASK-1 完成后可并行，但建议单线顺序执行以便审查。

## 每份任务书的固定结构

实施者（Codex）拿到的每份任务书都自包含：前置条件、必读参考、任务范围、详细规格、验收标准、自验命令、禁止事项。共享约定集中在 `docs/CONVENTIONS.md`，API 细节集中在 `docs/API-CONTRACT.md`，任务书只引用不重复。

## 用户操作流程

1. 把下面的提示词模板发给 Codex（替换任务编号与文件名）
2. Codex 完成后会：通过自验命令 → 写 `TASKS/REPORT-N.md` → git 提交
3. 回到主控（ZCode）说「TASK-N 已完成，请检查」
4. 主控 check 通过后，再领取下一个任务；不通过则主控给出修正清单，用户转交 Codex 修复

### 给 Codex 的提示词模板

```
你是实施工程师。请完整执行以下任务书：
D:\Users\Xumy\Downloads\bili-honmey\bililive-harmony\TASKS\TASK-N-XXXX.md

开工前必读（按顺序）：
1. D:\Users\Xumy\Downloads\bili-honmey\bililive-harmony\TASKS\docs\CONVENTIONS.md
2. D:\Users\Xumy\Downloads\bili-honmey\bililive-harmony\TASKS\docs\API-CONTRACT.md
3. 任务书「必读参考」一节列出的文件（含 iOS 源码，可直接阅读）

要求：
- **只执行本任务书（TASK-N）范围内的内容。严禁实施任何后续任务（TASK-N+1 及以后）的功能、页面或文件**，即使你看到它们的任务书也不要碰——后续任务有独立验收，提前实现会导致验收失败
- 严格遵循任务书的规格与验收标准，逐条自验
- 完成后写 TASKS\REPORT-N.md（固定结构见 CONVENTIONS.md 第 12 节）
- 全部自验通过后 git 提交（提交信息格式见 CONVENTIONS.md）
- 遇到任务书未覆盖的决策点：选择最贴近 iOS 行为的方案，并在报告中说明
```

### 给 Codex 的修复提示词模板

```
TASK-N 验收未通过。以下是主控审查结论，请逐条修复：
<粘贴主控给出的修正清单>
修复后更新 TASKS\REPORT-N.md 的「自验结果」与「遗留问题」，并 git 提交。
```

## 环境备忘（实施者需要知道）

- **DevEco Studio 6.0.1** 已安装（常见路径 `C:\Program Files\Huawei\DevEco Studio`，以实际为准）。SDK 在其 `sdk` 子目录；hvigor 与 Node 由 DevEco 携带
- **命令行编译**：项目根目录执行 `hvigorw.bat assembleHap`。若报找不到 SDK/Node，设置环境变量 `DEVECO_SDK_HOME`（指向 DevEco 的 sdk 目录）与 `NODE_HOME`（指向 DevEco 携带的 node），或参考 DevEco 模板工程的 `local.properties`
- **单元测试**：`hvigorw.bat test`（本地 hypium 测试；若命令不可用，报告说明即可，保证 IDE 内可跑）
- **真机运行与签名**：由用户在 DevEco Studio 里完成（自动签名需华为开发者账号），实施者不需要处理签名
- **设备屏幕**：2456×1600（约 3.0 密度，约 819×533vp），设计按自适应断点布局，勿写死像素

## 验收循环（主控职责，实施者无需执行）

主控对每个任务执行：对照验收清单读代码 → 跑编译与单元测试 → 与 iOS 参考行为逐条核对 → 输出「通过 / 修正清单」。全部任务完成后由 TASK-8 做总验收。

## 目录现状

```
bililive-harmony/
├── TASKS/            ← 本目录（任务书、共享文档、REPORT-N.md）
└── （TASK-0 将在此创建 DevEco 工程文件：AppScope/ entry/ build-profile.json5 等）
```
