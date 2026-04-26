# Vink Flasher APK History

这个目录记录 Vink Flasher 每个 APK 版本的更新内容和归档位置。

APK 二进制文件不直接放在源码树里，避免 Git 仓库被大文件快速撑大。历史 APK 统一存放在 GitHub Release：

- 最新版下载页：<https://github.com/Vivitoto/Vink-Flasher/releases/tag/latest>
- 历史 APK 归档页：<https://github.com/Vivitoto/Vink-Flasher/releases/tag/apk-history>

## 版本记录

### v0.3.0+21 / `vink-flasher-v0_3_0.apk`

发布时间：2026-04-26

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_0.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_0.apk>

更新内容：

- 烧录底层从 Dart 手写 ESP32 ROM bootloader 协议重构为 Android Chaquopy/Python + 官方 `esptool.py`。
- 新增 Android USB 串口到 Python `serial.Serial` 的桥接层。
- 新增 Kotlin MethodChannel 调用 Python esptool 的桥接实现。
- 内置 vendored `esptool` 4.8.1，避免 Chaquopy 直接安装 esptool sdist 的构建兼容问题。
- 修复 Chaquopy / Android Gradle Plugin / Flutter CI 的插件加载与 Python 3.11 构建配置。
- APK 签名验证与 GitHub Actions 发布流程已通过。

### v0.2.13+20 / `vink-flasher-v0_2_13.apk`

发布时间：2026-04-26

归档状态：旧 Release 资产已从 `latest` 清理；当前没有保留二进制副本。若需要恢复，可从对应源码提交重新构建后补到 `apk-history` Release。

更新内容：

- 使用 Dart 手写 ESP32 烧录协议的最后一个发布版本。
- 修复 Android 上 full flash 烧录前额外整片擦除导致的问题。
- 增加烧录诊断日志、USB 权限提示、bootloader 超时与同步波特率相关修复。
- 已被 v0.3.0 的官方 esptool 后端替代，不建议新用户下载。

## 维护规则

- `latest` Release 只保留最新 APK，避免用户下载错版本。
- `apk-history` Release 用于长期保留历史 APK，每个版本一个资产文件。
- 每次发布新版 APK 后，同步更新本文件的版本记录。
