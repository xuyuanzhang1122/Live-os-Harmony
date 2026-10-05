# REPORT-SUN：鸿蒙正式大版本

## 完成项

- ✅ 应用显示 sun，包内 versionName 3.0.0 / versionCode 3；版本递增，保留 bundleName。
- ✅ 设置和关于页共用 ReleaseInfo，新增本次迭代详情并保留旧记录；修正项目链接。
- ✅ README 与 RELEASE_NOTES 同步正式版、包版本、自行签名和命令行构建说明。
- ✅ 源码回归 87/87；Hypium 107/107，Failure 0、Error 0；Release assembleHap BUILD SUCCESSFUL。
- ✅ 实际 HAP ZIP、module.json 数字版本及两架构 NDK libavcap.so 核对通过。

## 实现说明

SDK schema 实际拒绝纯字母 versionName，采用数字 3.0.0，展示和标签仍 sun。公开构建配置删除旧 Windows 签名路径与材料，使用未签名发布包；原配置保存在本机私有临时目录，不上传私钥或证书。播放和网络契约未修改。

## 新增与修改

AppScope 版本、包元数据、ReleaseInfo、设置/关于页、公开构建配置、README / RELEASE_NOTES 和计划报告。

## 自验

node --test TASKS/tests/*.cjs 87 pass；Hvigor test 实际 test_result.txt 107 pass / Failure 0 / Error 0；release assembleHap 成功。新增/修改 main 文件 TODO/FIXME 扫描无命中，git diff --check 通过。

## 发布与限制

用户授权正式三端 Release，含必要推送。公开 LiveOS-sun-unsigned.hap 不带签名，需要自己的合法签名或 DevEco 构建运行。包兼容 API 12、目标 API 21；已有 API13 倍速枚举兼容警告未在此版本同步中扩展范围。指定大文件 MatePad 及多设备/编码矩阵仍保持先前真实限制，不能以源码测试替代。

待资产发布后追加实际下载摘要及 URL。
