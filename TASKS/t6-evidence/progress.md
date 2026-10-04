# T6 执行记录 — plan: TASKS/plans/2026-10-03-recording-playback-mainline.md

- 授权：用户要求完成 T6；保留旧修复、完成验证后本地提交，不 push/部署。
- 基线：e4be1f2，已有播放器、resolver、逐项删除及统计改动未提交，baseline-status 单独记录。
- T5 → T6 接口核对：v2 仅录播/会话/媒体/批删；房间、历史、缩略图保持旧管理 API。Envelope 必须显式解包。
- Ruling: 原计划已明确范围并经用户要求执行；复用当前工作树创建分支，保留已有累积修复，不重复设计或重写。
- Ruling: v2 清单不含缩略图/时间；使用其稳定身份与服务端 size_text，按路径关联旧列表的展示元数据。任何 v2 鉴权/契约/目录故障都不降级掩盖，仅端点确实缺失可回退。
- 真机前置检查：hdc list targets 返回 [Empty]；已请求连接设备与本机合法签名路径，不存密码/私钥。
- [x] v2 DTO/API/列表/批删 + 共享样例
- [x] 播放能力探测与会话轮询/刷新/取消/重建/旧回调隔离
- [x] 缩略图统一请求/续签，LAN 真状态
- [x] Hypium/源码/编译与独立审查
- [ ] 真机验收；报告/证据/本地 commit

- v2 首轮 RED→GREEN：14 例；会话生命周期 9 例；能力白名单 3 例，均通过。
- 新共享契约快照保存 TASKS/contracts/v2 与 Hypium fixture 常量；源码验证一致。
- 独立审查 2 Important + 1 Minor（按实际效果将暂停短暂发声升为 Important），已全部 RED→GREEN：合法refresh=0主动续会话、未确认legacy的缺身份缓存拒删、prepare→seekDone→倍速→按原意播放。
- HLS duration增长、native首帧事件及晚到隔离补回归；当前源码84/84。
- Hypium编译曾发现缺回调声明和reject参数类型，已修复后复测；最终结果后续记录。
- 合法签名源来自用户配置的 Documents/github 同名工程；隔离临时副本构建成功并覆盖安装（不卸载、不改数据）。签名材料不入库。
- 设备shell拒绝执行未签名native诊断程序（Permission denied）；尊重限制，改为合法签名应用诊断，不变更设备安全保护。
- 诊断副本仅增加内存APIClient和测试入口，复用实际PlayerPage/Controller/NDK能力查询；不改用户保存的服务器配置。
- 隔离服务仅127.0.0.1:18686，hdc反向端口；fixture目录独立，未触及远端生产。
- 偏差：首次服务启动意外写本机系统配置镜像，缺少事前备份，已向用户说明并请求恢复来源。后续设置BILILIVE_CONFIG_FILE到隔离目录；远端生产未改。不能擅自猜旧内容。

- 最终源码回归87/87；Hypium107/107（直接检查结果文件，失败/错误均0）。
- 实机首次AAC能力查询profile成功但空数组；用真实AAC-LC/48k/双声道Configure确认，拒绝配置仍不上报。补native stub回归2项。
- 实机签名诊断样片冷启动、退出重进均触发原生startRenderFrame；普通prepared/HTTP成功未被当作首帧。
- 追加T5真实wire边界兼容：Go omitempty省略0值refresh时，仅token硬过期且剩余<=60秒归一为0，其他缺失仍拒绝；RED→GREEN。
- 本轮matrix诊断驱动首次编译失败（测试驱动方法名错误），核查后修复重构建成功，再安装；不使用失败构建后的旧包作为matrix证据。

- 真机480.064秒长样片已验证50%/近尾native seek、关闭released与服务器cancelled、重开首帧、暂停刷新保持209.502秒且未播放、恢复后越过原5分钟token期限。
- 常规入口最终签名包覆盖安装并成功启动；移除本轮反向18686端口并停止独立测试服务。测试样本和临时证据保留。
- 指定大录播未取得、默认本机旧配置恢复来源未收到，整体T6保留未完成。以下提交为已验证代码及旧成果检查点，不声称完成指定视频验收。
