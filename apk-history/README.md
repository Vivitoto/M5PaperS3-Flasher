# Vink Flasher APK History

这个目录记录 Vink Flasher 每个 APK 版本的更新内容和归档位置。

APK 二进制文件不直接放在源码树里，避免 Git 仓库被大文件快速撑大。历史 APK 统一存放在 GitHub Release：

- 最新版下载页：<https://github.com/Vivitoto/Vink-Flasher/releases/tag/latest>
- 历史 APK 归档页：<https://github.com/Vivitoto/Vink-Flasher/releases/tag/apk-history>

## 版本记录

### v0.3.18+39 / `vink-flasher-v0_3_18.apk`

发布时间：2026-04-30

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_18.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_18.apk>

更新内容：

- 修复“本地/烧录”页进入后仍等待远端固件清单导致一直转圈的问题。
- 本地固件扫描完成后立即显示本地可烧录版本；远端清单只在后台补全版本说明/Release 链接。
- 远端元数据刷新增加 4 秒超时，网络不可用时只显示离线提示，不阻塞烧录入口。

### v0.3.15+36 / `vink-flasher-v0_3_15.apk`

发布时间：2026-04-27

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_15.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_15.apk>

更新内容：

- 底部导航新增“本地/烧录”同级 Tab，将远端固件浏览/下载与本地固件管理/烧录入口分离。
- 固件页保留最新版与历史版本下载入口；本地/烧录页集中展示已下载或未完成下载的固件版本。
- 每个本地固件版本可继续下载、重新下载、删除本地文件，并指定该版本进入烧录。
- App 自更新 APK 改为保存到系统 Downloads，避免长期占用应用缓存/临时目录。
- 保留 PaperS3 Android 原生 0xFlash 兼容烧录后端和 921600 默认高速烧录设置。

### v0.3.8+29 / `vink-flasher-v0_3_8.apk`

发布时间：2026-04-27

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_8.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_8.apk>

更新内容：

- 新增并默认推荐“官方模式”：按 M5Stack PaperS3 官方文档，USB 连接后长按侧边电源键，直到背面红灯闪烁进入下载模式。
- 官方模式烧录时使用 `--before no_reset`，避免 Android 端 DTR/RTS 自动复位时序继续影响 PaperS3 ROM sync。
- 烧录前增加确认弹窗，等用户确认红灯闪烁后再启动官方 esptool。
- 修正兼容模式：真正使用 Ink Box / esptool 4.8.1 原版 USB-JTAG reset 序列，避免继续走自动模式的 reset patch。
- 保留自动模式和 Ink Box 兼容模式作为备用/对照测试。

### v0.3.6+27 / `vink-flasher-v0_3_6.apk`

发布时间：2026-04-27

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_6.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_6.apk>

更新内容：

- 修复 Android Serial 初始化 DTR/RTS 硬件线后，pySerial 内部 `dtr/rts` 状态仍保留默认 True 导致 esptool USB-JTAG reset 序列被错误补发 DTR 的问题。
- 参考 0xFlash v0.9.5 的 Android 烧录逻辑，将 ESP32-S3 USB-JTAG 进入下载模式的 reset 序列改为 DTR false + RTS true → DTR true + RTS false → DTR false + RTS false。
- 新增设置页烧录逻辑选择：稳定模式默认适合 PaperS3；兼容模式按 Ink Box 参数（chip auto、default_reset、no-stub、460800）用于对照验证。
- 关闭串口时同步清理内部 DTR/RTS 状态，避免下一轮烧录继承错误控制线状态。

### v0.3.5+26 / `vink-flasher-v0_3_5.apk`

发布时间：2026-04-27

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_5.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_5.apk>

更新内容：

- ESP32-S3 烧录前强制使用 esptool `usb_reset`，避免默认 reset 模式在 Android USB Serial/JTAG 下同步失败。
- Android Serial 打开/关闭时将 DTR/RTS 保持在 USB-JTAG 空闲态，并在 USB-JTAG reset 后增加短暂等待，提高 ROM bootloader sync 成功率。

### v0.3.4+25 / `vink-flasher-v0_3_4.apk`

发布时间：2026-04-27

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_4.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_4.apk>

更新内容：

- 修复 esptool 连接阶段小字节读取触发 Android usb-serial-for-android `Read buffer too small` 的问题。
- Android Serial read 改为内部大缓冲读取，再按 pySerial 语义返回 esptool 请求的字节数。

### v0.3.3+24 / `vink-flasher-v0_3_3.apk`

发布时间：2026-04-27

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_3.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_3.apk>

更新内容：

- 修复 Android 原生 / Chaquopy bridge 异常只显示 Java 线程堆栈、丢失 Python/esptool 根因的问题。
- 日志回调失败时不再让 PyException 逃逸到 MethodChannel，改为把完整错误返回到 App 烧录日志中。

### v0.3.2+23 / `vink-flasher-v0_3_2.apk`

发布时间：2026-04-26

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_2.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_2.apk>

更新内容：

- 修复 Chaquopy 接收到 Kotlin `ArrayList` 参数后 Python 侧直接迭代导致的 `TypeError: 'ArrayList' object is not iterable`。
- esptool bridge 现在会把 Java/Kotlin List、Iterator、Array 统一转换成 Python list 后再调用官方 esptool。
- 修复烧录设置里的波特率没有传给 USB 授权连接和 esptool 实际烧录流程的问题。
- 强化固件清单 / GitHub Release JSON 解析，避免数字和 Map/List 类型转换导致界面加载失败。
- 强化固件和应用更新下载校验，避免断点续传 416 或大小不一致时误把半截文件当完整文件。

### v0.3.1+22 / `vink-flasher-v0_3_1.apk`

发布时间：2026-04-26

归档位置：

- Latest: <https://github.com/Vivitoto/Vink-Flasher/releases/download/latest/vink-flasher-v0_3_1.apk>
- History: <https://github.com/Vivitoto/Vink-Flasher/releases/download/apk-history/vink-flasher-v0_3_1.apk>

更新内容：

- 修复 Android 端 Chaquopy Python 无法用 `from com... import ...` 加载 Java 包导致的 `ModuleNotFoundError: No module named 'com'`。
- 改用 Chaquopy 官方 `java.jclass(...)` 方式加载 USB Serial Java 类。
- 显式加入 `usb-serial-for-android` 依赖和 JitPack 仓库，确保运行时可找到 `com.hoho.android.usbserial.driver.*`。

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
