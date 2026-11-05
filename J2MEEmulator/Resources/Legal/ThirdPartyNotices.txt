# Third-party notices / 第三方声明

本工程基于 ccbkv/J2MEEmulator-iOS，原始 commit `8afc8d808ca22160139333d1d58138c7dca91169`。其根目录 LICENSE 为 Apache License 2.0。本次新增构建脚本、测试及文档亦采用 Apache-2.0；上游各文件自己的声明优先，不重新许可第三方文件。

| 组件 | 已核对证据 | 许可证/状态 |
|---|---|---|
| iOS 外壳及移植代码 | 原仓库根 LICENSE | Apache-2.0，保留原文件头 |
| J2ME API | 原 README、Java 文件头及 [J2ME-Loader LICENSE](https://github.com/nikita36078/J2ME-Loader/blob/master/LICENSE) | Apache-2.0；部分 MicroEmulator 文件提供 LGPL-2.1-or-later / Apache-2.0 双许可，依文件声明 |
| miniJVM C 核心 | [官方 2.0.0 LICENSE](https://github.com/digitalgust/miniJVM/blob/47c00ad743e01417b05e09d1a7b0294c5dfb31f3/LICENSE) | 上游项目代码 MIT；嵌入组件各自声明优先。本仓库 C 代码含 iOS 修改，未覆盖替换 |
| miniJVM Java 启动类库 | 原版 JAR；[2.0.0 Java 源码候选](https://github.com/digitalgust/miniJVM/tree/47c00ad743e01417b05e09d1a7b0294c5dfb31f3/minijvm/java) | 上游 Java 目录包含 GPL-2.0 及明确标记 Classpath Exception 的 OpenJDK 文件。原 JAR 内仅有 manifest，源码对应版本尚未确认，不宣称整个 JAR 属于 MIT/Apache |
| Nokia M3G | `NativeBridge/m3g/src` 文件头 | Eclipse Public License 1.0，保留 Nokia 声明；独立于根 Apache 许可 |
| mbedTLS 2.4.2 | `minijvm/utils/https/mbedtls/include/mbedtls/version.h` 与源码头 | Apache-2.0，版本较旧，后续独立评估更新，不在构建修复中替换 |
| tinycthread | `minijvm/utils/tinycthread.[ch]` 文件头 | zlib 风格许可，保留声明 |
| miniz | `minijvm/utils/miniz.[ch]` 文件头 | MIT 风格许可，保留声明 |
| c-algorithms 容器 | arraylist/hashtable 等文件头 | ISC 风格许可，保留 Simon Howard 声明 |
| GeneralUser GS 1.471 | 原版 `gs_instruments.sf2` INFO/ICMT 元数据 | GeneralUser GS License v2.0；完整原文提取至 LICENSES/GeneralUser-GS.txt。元数据作者为 S. Christian Collins；许可说明也披露部分样本来源的不确定性，不改写为无条件版权保证 |

原运行库字节校验已固定，未在仓库伪造缺失的 Java 源码。`LICENSES/miniJVM-2.0.0-upstream.txt` 是候选上游当年的原始声明；其中对二进制许可的表述不替代文件自身条款。本工程尚未完成运行库源码逐项对应与发布合规整理，不能凭根 LICENSE 就宣称所有第三方组件均可任意闭源分发。

没有包含、下载或打包《诛仙伏魔录》或其他未经许可的商业游戏。`test_midlet` 来自已指明的 Apache-2.0 上游仓库；新增 HostRmsSmoke 测试为本项目编写。

本阶段变更：修复 Java 构建路径和跨平台编译；添加未签名真机工作流、源码检查及打包测试；修改应用身份与统一部署版本。未替换 C miniJVM、Java 运行类库、M3G 或 MascotCapsule 实现。
