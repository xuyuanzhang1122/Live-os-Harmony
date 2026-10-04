# REPORT-CONTRACT：播放与逐项删除契约续作

日期：2026-10-03。

## 完成项

- ✅ 鸿蒙批量删除解包并校验服务端逐项结果；只移除成功项，保留失败选择和原因，同步缓存并报告真实成功数量。
- ✅ iOS 播放解析与鸿蒙四状态、URL/签名/Key、有限轮询和旧端点回退规则对齐。
- ✅ iOS 逐项批删、失败反馈及列表缓存键对齐。
- ✅ 两端使用服务端 15 个共享播放解析样例；API-CONTRACT.md 补充实际协议。
- ✅ 本地回归、工程编译与服务端相关验证有完整记录；签名及真机验收仍待完成。

## 实现说明

本轮按用户跨仓续作授权实施，保留原播放器生命周期修复，不重复重写。公共方法 batchDeleteFiles 返回类型从 Promise<void> 改为 Promise<BatchDeleteResult[]>，同步更新基础设施测试替身。ViewModel 只根据本次请求明确成功的路径修改列表；非法/重复结果与请求失败不修改列表。缺失结果视为失败并保留原因。

iOS 的 API/模型及 UI 也处理逐项结果。共享契约改动和跨仓范围来自当前用户续作要求；没有执行旧任务规范中的自动提交。

## 新增/修改文件清单

- 修改 entry/src/main/ets/model/Common.ets、net/APIClient.ets、viewmodel/VideoLibraryViewModel.ets、pages/VideoListPage.ets。
- 修改 entry/src/test/Task1Infrastructure.test.ets，适配返回类型。
- 新增 TASKS/tests/batch-delete-regression.cjs；给 playback-regression.cjs 补共享样例。
- 修改 TASKS/docs/API-CONTRACT.md。
- iOS 与服务端本轮范围见工作区根目录 bililive-续作与验收记录-2026-10-03.md。

## 自验结果

- 源码回归 41 项通过；批删新增 8 项在修复前 7 失败，修复后全部通过。
- Hvigor test 退出码 0；实际 Hypium 95 通过、0 失败/错误。
- assembleHap 编译打包通过，SignHap 因本机无有效配置失败，退出码 255。
- iOS 契约回归及完整模拟器构建通过。
- 服务端全量测试、lint 0 issues、race、真实 FFmpeg 集成、前后端联合构建、Windows 交叉编译通过；收尾遇到的 HLS 测试清理失败已定位、补回归并修复。
- 三仓 diff 空白检查通过；本轮源码 TODO/FIXME 无新增匹配。
- 独立只读审查没有新增阻断发现。

## 遗留问题

修复版 HAP 尚未签名/安装，未对指定 5.2GB 视频完成冷/暖启动、拖动与持续播放验收；设备报告版本号 2.0.1 不能作为源码匹配证据。长期资产/能力分流、签名过期续播、Windows 目录同步及真实设备性能仍需继续。

当前代码 SHA-256、Git 状态和完整日志保存在工作区根目录 bililive-验收证据-2026-10-03；完整命令及结果见 bililive-续作与验收记录-2026-10-03.md。
