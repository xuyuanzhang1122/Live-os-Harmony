# TASK-8：打磨与总验收（启动动画 / 触觉 / 平板适配 / 文档）

> 角色：实施工程师（Codex）。开工前必读 `TASKS/docs/CONVENTIONS.md`、全部 `REPORT-*.md`。

## 前置条件

TASK-0 ~ TASK-7 全部完成且验收通过。

## 目标

收尾打磨：品牌启动动画、触觉补全、MatePad 大屏适配走查、应用图标、README/AGENTS.md/功能对齐核对表，以及全工程编译+测试总验收。

## 必读参考（iOS 源码）

- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\LaunchScreenView.swift`（启动动画）
- `D:\Users\Xumy\Downloads\bili-honmey\bililive-ios\Live OS\Live OS\Views\GlassEffects.swift`（毛玻璃策略）

## 详细规格

### 1. 品牌启动动画（pages/components/LaunchView.ets）

对齐 iOS 动画节奏（总时长约 2.3 秒，EntryAbility 首帧叠加，结束淡出移除，仅冷启动显示）：
- 浏览器图标自左滑入 + 手机/平板图标自右滑入（居中相会）
- 闪电图标自上而下劈落（scaleY 动画）+ 白色闪光一瞬
- 标题「哔哩录播 · 鸿蒙版」+ 副标题「录播工具 / bililive」淡入
- 整体 2.3s 后淡出；动画期间不阻塞页面预加载（cover 方式叠加）
- 图标可用 SymbolGlyph/简单自绘，视觉鸿蒙化但节奏一致

### 2. 触觉补全（对照 iOS 四处）

- Tab 切换 selection 触觉（TASK-0 已有，确认）
- 播放状态变化 light（TASK-4 已有，确认）
- 2x 锁定：长按开始 light / 锁定解锁 medium（TASK-4 已有，确认）
- 缺漏处补齐；确认无振动能力设备全部静默失败不崩溃

### 3. MatePad 11.5（2456×1600）大屏适配走查

逐页检查并修正（可折叠大宽度下不变形、不过宽拉伸）：
- 视频库网格：大屏 4~5 列、卡片列宽仍在 160~300vp
- 视频列表/直播间/历史：宽屏下限制内容最大宽度（如 maxContentWidth 840~1000vp 居中）或合理多列
- 设置：平板上分组卡片最大宽度居中（鸿蒙平板设置惯例）
- 播放器：横竖屏、分屏（可选）下控制层布局不错位；时间线/按钮命中区域 ≥44vp
- 深浅色：全部页面在系统深色模式下无不可读文案（播放器恒暗）

### 4. 应用图标

替换 TASK-0 占位图标：青绿底（#1FDBC7 渐变可）+ 白色播放三角/闪电，前后景分层资源（前景自适应图标），提供 216×216 等标准尺寸；暗色模式下视觉可接受。自绘生成即可，不求精美。

### 5. 文档

**README.md**（工程根）：项目简介（鸿蒙版 Live OS，配套 bililive-go-UI）、功能清单（四页签+播放器+备份）、截图占位、构建方法（DevEco Studio 6.0.1 打开 + 自动签名 + hvigorw 命令）、与 iOS 版功能对照说明、致谢（bililive-go-UI、iOS 版、pillarbox 思路）。

**AGENTS.md**（工程根）：给后续 AI 助手的开发指南——指向 TASKS/docs/CONVENTIONS.md 与 API-CONTRACT.md，说明目录结构、构建命令、行为对齐原则。

**TASKS/docs/parity-checklist.md**：功能对齐核对表（约 60 项），分四页签+播放器+备份+全局，每项一行：功能点 | iOS 行为 | 鸿蒙实现位置（文件） | 状态（本任务全部标 ✅ 或注明遗留）。

### 6. 总验收

- 全量编译 + 全部单元测试通过
- 对照 parity-checklist 逐项自检，发现实现缺口当场修复（小缺口）或列入报告遗留（大缺口）
- `git status` 干净；提交 `TASK-8: 打磨与总验收`

## 验收标准

- [ ] 启动动画节奏/元素与规格一致，仅冷启动出现，不卡首帧
- [ ] 四处触觉齐全，异常静默
- [ ] 平板走查：视频库 ≥4 列、各列表页宽屏布局合理、设置卡片限宽居中、播放器两方向正常、深色模式无不可读
- [ ] 正式应用图标就位（含暗色可接受）
- [ ] README/AGENTS.md/parity-checklist.md 三份文档完成且内容真实
- [ ] `hvigorw.bat assembleHap` 与 `hvigorw.bat test` 全绿；无 TODO/FIXME 遗留（或全部列入报告）
- [ ] git 提交完成

## 自验命令

```bash
cd /d/Users/Xumy/Downloads/bili-honmey/bililive-harmony
hvigorw.bat assembleHap --daemon=false && hvigorw.bat test --daemon=false
grep -rn "TODO\|FIXME" entry/src/main/ets --include="*.ets" | grep -v "@todo-style" || echo "无遗留"
```

## 禁止事项

通用见 CONVENTIONS §11。另：本任务不改任何业务行为参数（轮询间隔、手势数值等契约值）；发现行为 bug 修 bug 本身并在报告列出。
