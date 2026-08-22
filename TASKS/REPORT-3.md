# REPORT-3：播放器核心（AVPlayer / 控制层 / 基础手势 / 错误态）

## 完成项

- ✅ 播放入口完成：`VideoListPage.openPlayer(file)` 的 content cover 已替换为真实 `PlayerPage`，播放地址统一通过当前 `AppConfig.getClient()` 的 base URL/API Key 调用 `APIClient.buildPlaybackUrl()`，既有测试覆盖 MP4 直链与 HLS 决策分支。
- ✅ AVPlayer 核心完成：`PlayerController` 按 create→url→surfaceId→prepare→play 初始化，映射 idle/initialized/prepared/playing/paused/completed/stopped/released/error 全状态，提供播放、暂停、秒级 seek、七档倍速、音量及查询接口。
- ✅ 生命周期与资源释放完成：关闭时 pause→空 `onBeforeClose` 扩展钩子→stop/reset/release→关闭 cover；release 幂等，七类 AVPlayer 事件均使用成对回调解绑；生命周期令牌阻止退出后迟到的异步播放器继续播放。
- ✅ ProgressTracker 完成：250ms 采样当前进度；交互开始暂停并冻结显示时间，拖动中仅更新预览，结束 seek，seekDone 后仅在进入交互前正在播放时恢复，并等待异步 pause 完成；交互令牌与目标校验会忽略旧 seekDone，停止或取消拖动也不会误恢复播放。
- ✅ 全屏分层完成：黑底、40vp 模糊且 0.4 透明度的封面背景、SURFACE XComponent、顶部 120vp/底部 160vp 暗角、手势层、空 HUD 层、Toast 层、结束重播层与控制层按任务书顺序实现，视频显式使用 aspect-fit。
- ✅ 控制层完成：顶部退出、文件名/大小和禁用 PiP 占位；底部等宽时间、自定义缓冲/主进度/14vp 拖点时间线、播放暂停/重播按钮及七档倍速 Menu，当前倍速依据系统 `speedDone` 回写并显示勾选。
- ✅ 时间线完成：34vp 命中高度包住 4vp 轨道，上下各外扩 15vp；`PanGesture(distance: 0)` 支持点按即跳与连续拖动，时长未就绪时不会误入交互冻结态。
- ✅ 手势完成：双击优先的 Exclusive GestureGroup 实现双击播放/暂停（结束时重播）与单击切换控制栏；控制层位于手势层上方，隐藏时透明且 `HitTestMode.None`，不会吞掉底层手势。
- ✅ 错误与结束态完成：recording/processing/其他分别显示「正在录制，请稍后」「正在处理，请稍后」「视频暂时无法播放」，错误层仅有「退出」按钮；播放完成显示毛玻璃圆形重播按钮。
- ✅ Toast/HUD 扩展点完成：单条毛玻璃 Toast 位于底部上方 132vp，2.2 秒自动消失；HUD 与 `onBeforeClose` 均只留 TASK-4 扩展点，没有提前实现后续行为。
- ✅ 编译与测试通过：`assembleHap` 输出 `TYPE CHECK SUCCESSFUL`、`BUILD SUCCESSFUL` 并完成签名；Hypium 40 个用例全部通过，Failure 0、Error 0。
- ✅ 范围约束满足：未实现 TASK-4 的横滑 seek、音量/亮度手势、2x 锁定、续播、上报或 PiP，仅保留禁用按钮与空扩展钩子。

## 实现说明

- `PlayerController` 使用可注入 `PlayerAdapter` 隔离系统媒体对象，使本地单测可以验证初始化顺序、毫秒/秒换算、七类事件解绑和 release 幂等；生产适配器仍直接封装 `media.AVPlayer`，没有引入第三方运行时依赖。
- 系统媒体调用抛出的 `BusinessError` 会转换为保留原始 code/message 的 `PlayerOperationError`；API 12 将 3x 降级为 2x 时，界面也按系统最终 `speedDone` 结果显示 2x，而非乐观显示请求值。
- iOS 参考行为中的时间线冻结语义由独立 `ProgressTracker` 承担，页面只负责把拖动目标传入 tracker；这为 TASK-4 复用同一交互状态机保留了稳定接口。
- 单击/双击采用双击在前的 `GestureGroup(GestureMode.Exclusive, ...)`，由框架等待高优先级双击识别失败后再确认单击，避免手写计时器带来的重复触发。
- 控制图标选择可编译的 Unicode 文本符号，避免依赖当前 SDK 中不确定的系统 Symbol 资源；毛玻璃、品牌色和其他视觉仍使用工程原生能力与 `app.color.brand_color`。
- `PlaybackSpeed.SPEED_FORWARD_3_00_X` 自 API 13 起提供，目标 API 21 真机直接使用；兼容 API 12 设备以 try-catch 降级到 2x，并根据系统回调同步菜单状态，符合 CONVENTIONS 的高版本 API 运行时降级纪律。
- 任务书所称 `PanGesture(minimumDistance: 0)` 在当前 ArkUI 声明中的等价参数名为 `distance: 0`，行为仍为触点按下即可进入拖动识别。
- 与任务书的偏差：无。
- 对 TASK-1 公共接口的任何变更：无。

## 新增/修改文件清单

- 新增：`entry/src/main/ets/pages/PlayerPage.ets`
- 新增：`entry/src/main/ets/player/PlayerController.ets`
- 新增：`entry/src/main/ets/player/ProgressTracker.ets`
- 新增：`entry/src/main/ets/player/PlayerRules.ets`
- 新增：`entry/src/test/Task3Player.test.ets`
- 新增：`TASKS/REPORT-3.md`
- 修改：`entry/src/main/ets/pages/VideoListPage.ets`
- 修改：`entry/src/test/List.test.ets`

## 自验结果

- `.\hvigorw.bat assembleHap --daemon=false`：通过；`TYPE CHECK SUCCESSFUL`、`BUILD SUCCESSFUL`，ArkTS 编译、HAP 打包与签名全部成功。
- `.\hvigorw.bat test --daemon=false`：通过；结果文件为 Tests run 40、Pass 40、Failure 0、Error 0、Ignore 0。
- 新增测试覆盖：时间线位置钳制、七档倍速清单、三类错误文案、ProgressTracker 冻结/条件恢复/异步 pause 竞态、旧 seekDone/停止/取消拖动竞态、PlayerController setup 顺序、秒/毫秒换算、音量钳制、有效倍速回写、错误码保真、七类事件解绑、release 幂等及创建未完成时退出的迟到实例清理。
- 静态生命周期检查：`stateChange`、`error`、`seekDone`、`durationUpdate`、`speedDone`、`volumeChange`、`bufferingUpdate` 七类事件均成对 on/off；关闭路径和 `aboutToDisappear` 均停止 tracker 并释放播放器。
- 静态范围检查：仅出现 TASK-4 所需的空 HUD、禁用 PiP 按钮和空 `onBeforeClose` 钩子；未调用历史 API、亮度/PiP API，未实现横滑 seek、音量/亮度手势、2x 锁定、续播或上报。`git diff --check` 无空白错误。

## 遗留问题

- 需要连接真实 bililive 服务并在真机分别播放 MP4 与 HLS，验收视频画面、网络缓冲百分比、倍速实际生效、横竖屏布局、单/双击判定、时间线点按/拖动及毛玻璃视觉。
- API 12 系统本身不支持 3x PlaybackSpeed，已按兼容纪律降级并回显为 2x；目标 API 21 设备支持完整七档。
