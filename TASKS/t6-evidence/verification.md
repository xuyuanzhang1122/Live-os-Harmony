# T6 验证摘要（2026-10-04）

## 自动验证

- 源码测试：87 / 87；包括真实 ETS 模块转译后的 HTTP、会话、控制器逻辑与 native C++ 查询 stub 回归。
- Hypium：107 / 107，Failure 0，Error 0；直接读取 test_result.txt。
- 正常入口签名构建：CompileArkTS、Native、PackageHap、SignHap 均成功。正常包中无 T6ProbePage，main/test/native/resources 文件与工作区逐字一致。
- 编译日志和结果原件仅保留本机；哈希记录下方。签名包 SHA256 与业务源指纹见 artifact-manifest.json。
- TODO/FIXME 扫描 main/test 无命中；HTTP 创建只在 APIClient；diff --check 通过。

## 独立审查及修复

1. 临近过期 refresh=0 不应被视为坏响应：允许 0 并换新会话取消旧会话。随后核对真实 Go omitempty 行为，仅在 hard-expiry/<=60s 边界补 0，其他缺失保持失败。
2. 缺录播身份的旧缓存在 v2 清单失败时不能走 legacy 删除：仅显式确认 legacy 后允许，混合/缺身份 v2 选择失败并提示刷新。
3. 暂停刷新先播放再 seek 会短暂发声：prepare → seekDone → rate → 原 autoplay，测试涵盖暂停及位置恢复。

## MatePad 签名诊断样片

设备 API 21；独立本地服务 127.0.0.1:18686，通过 HDC 反向端口。样片 H.264 Main level 3.1、640x360/25fps、AAC-LC 48k stereo，长样片480.064s。

- 能力：NDK 确认 H.264 baseline/main/high 1080p60/level4.2；AAC profile 成功但空数组，实际 LC Configure 成功后确认 AAC-LC，未猜测通配支持。
- 冷启动：17:30:02.773 清单2项；17:30:02.914 prepared；17:30:02.925 原生 startRenderFrame；17:30:02.929 playing。
- 退出：17:30:37.775 关闭，17:30:37.974 native released，17:30:37.978 关闭覆盖层。服务端同会话状态 cancelled。
- 暖重开：17:30:38.537 清单；17:30:38.718 prepared；17:30:38.722 原生首帧。
- 50% seek：17:30:43.723 发起，随后实际 timeUpdate=240.032s，继续至244.088s。
- 近尾 seek：17:30:48.723 发起，随后 timeUpdate=472.064s，继续至479.006s；17:30:58.889 重播回0s。
- 暂停刷新：17:34:28.804 paused；17:34:38.700 收到刷新并重新 setup；17:34:53.723 验证仍为 prepared、209.502s；恢复后17:34:53.732 原生首帧，17:34:53.756 playing。刷新期间未启动播放。
- 跨原授权有效期：初始会话17:30:38建立、token原有效期约17:35:38；17:35:58.725 native=playing、274.164s，继续收到timeUpdate至289.057s。
- 最终常规入口包已覆盖安装并启动成功；诊断入口不在该包内。测试服务器停止、仅本轮18686反向端口撤销，其他设备连接未清理。

诊断额外入口/内存测试 APIClient/定时驱动只在临时副本；业务逻辑为当前源码。seek 是真实 native 调用验证，尚不能代表完整手势 UI 验收。指定5,634,539,067字节录播未取得，样片结论不覆盖它或全媒体矩阵。原始真机日志不入库。

## 本机配置偏差

首次测试启动意外覆盖本机默认 config.yml，缺事前备份，待用户提供恢复来源；已说明并改用独立 BILILIVE_CONFIG_FILE 防止再次镜像。未改远端生产。

## 本机验证原件 SHA256

- source-final.log: `d30d0e92c19bba89e58429e3700feaff32245903ae813c39bafb463ec8c209bb`
- hypium-final.log: `b0e6fb5c17342a056a516516dc59ad5a371abfcd38e9e333054800df91181957`
- normal-assemble-final.log: `19d0dfd47969f08da0917485809f00a89454597f2c6593c6b75911e417160c1b`
