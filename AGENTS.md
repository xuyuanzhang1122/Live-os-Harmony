# AGENTS.md

本文件供后续 AI 助手和工程维护者使用。修改代码前先阅读：

1. `TASKS/docs/CONVENTIONS.md`：工程、架构、兼容性、Git 与报告约定。
2. `TASKS/docs/API-CONTRACT.md`：服务端端点、字段、鉴权、媒体 URL 与备份契约。
3. 当前任务书及相关 `TASKS/REPORT-*.md`：实际实现、偏差和真机结论。

## 目录结构

```text
AppScope/                         应用级配置与分层图标资源
entry/src/main/ets/
  entryability/                  Stage Ability 入口
  model/                         与服务端/iOS 对齐的数据模型
  net/                           APIClient 与 API 缓存
  cache/                         LRU、缩略图缓存
  config/                        AppConfig、Key 存储、网络监听
  player/                        播放控制器和纯逻辑状态机
  viewmodel/                     页面 ViewModel
  pages/                         四页签、设置子页和播放器
  pages/components/              可复用 UI、启动页、备份 Sheet
  common/                        主题、格式化、触觉、哈希
entry/src/main/resources/        模块资源与深色资源
entry/src/test/                  Hypium 本地单元测试
TASKS/docs/                      共享规范、API 契约、功能对齐表
TASKS/REPORT-*.md                各阶段真实验收记录
```

## 构建与测试

在工程根目录执行：

```powershell
.\hvigorw.bat assembleHap --daemon=false
.\hvigorw.bat test --daemon=false
```

新增测试文件必须在 `entry/src/test/List.test.ets` 注册。完成任务前还要执行 TODO/FIXME 扫描、`git diff --check` 和任务书列出的静态契约检查。

## 开发原则

- 行为对齐 iOS：任务书给出的轮询、续播、手势、重试和超时数值是契约，不得顺手调整。
- UI 鸿蒙化：优先 ArkUI 原生组件、系统颜色 token 和响应式布局；播放器恒暗，其余页面必须支持深浅色。
- 兼容 API 12，目标 API 21。使用 API 12 之后能力时必须做特性检测或 try/catch 降级，不得依赖 API 21 之后接口。
- 状态管理只用 V2：`@ObservedV2`、`@Trace`、`@Local`、`@Param`、`@Event`、`@Monitor`。
- 网络只能经 `entry/src/main/ets/net/APIClient.ets`；不要在页面直接创建 HTTP 请求。
- 服务端字段常有 `omitempty`，缺失值是 `undefined`；读取可选字段统一使用 `??` 兜底。
- ArkUI `ForEach` 键值不变时可能不重绘行。键值必须包含该行全部展示字段，参照 `roomRowKey` 和 `historyRowKey`。
- 长按上下文菜单使用 `bindContextMenu(builder, ResponseType.LongPress)`；`bindMenu` 是点击菜单，不能替代。
- 宽屏内容使用 840～1000vp 限宽居中；视频库使用响应列数，避免固定像素布局。
- 只修改当前任务范围，不改 iOS、服务端工程或 `TASKS/docs/CONVENTIONS.md` / `API-CONTRACT.md` 公共契约。
- `TASKS/tools/` 含真机探测材料，保持未跟踪，禁止加入提交。

## Git 与交付

每个任务一次提交，只 commit 不 push，不重写历史。提交前显式检查暂存文件，避免把构建产物、签名材料、真机日志或 `TASKS/tools/` 纳入版本库。报告结构遵循 `CONVENTIONS.md` 第 12 节。
