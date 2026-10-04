# T8：鸿蒙历史身份补强

## 完成项
在 T6 已提交基线 a1321bb 上，history POST 保留 recording_id/source_version；播放器使用原会话捕获的身份和 APIClient，避免来源替换和切换账号后的错误上报。

## 实现说明
新增字段可选，旧服务端可以忽略；v2 播放通过已核验清单捕获身份，服务端对缺身份或版本变化的写入拒绝。

## 改动文件
HistoryEntry、APIClient、PlayerPage 与 v2-regression 源码执行测试。

## 自验结果
历史 POST 新回归先失败，再通过；源码回归 88/88，Hypium 107/107、Failure=0、Error=0。主工作区 ArkTS/PackageHap 通过但仍引用旧 Windows 签名路径；沿用 T6 合法本机签名独立副本同步本轮三文件后 assembleHap 与 SignHap 成功。副本仅修改构建签名路径，不含测试入口。

## 遗留问题
当前 HDC 无连接设备，本次身份补强未重新覆盖鸿蒙真机。T6 指定大录播与本机旧配置恢复仍待材料，详见 REPORT-T6-20261004.md。未 push。
