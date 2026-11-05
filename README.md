# J2ME Studio — iPhone Java 游戏模拟器

基于 [ccbkv/J2MEEmulator-iOS](https://github.com/ccbkv/J2MEEmulator-iOS)，保留原有 Swift/UIKit、Objective-C/C 桥接、miniJVM 解释器、M3G、MascotCapsule、音频和 Java API。当前版本 0.4.1：中文游戏库与文件导入、独立存档及 RMS 回退、长按组合输入、横竖屏与像素缩放、可编辑按键、运行日志，以及共享核心的独立游戏模式。本版修复方向盘数字 6 的组合诊断误判；用户已在 iPhone 17 Pro / iOS 27.0 签名安装，并反馈组合操作及正常退出重开的 RMS 计数通过。外部 JAR 真机导入、音频、3D 及商业游戏兼容性待验证。

## 当前验证状态

**0.4.1：**[成功构建 #10](https://github.com/a526437928/J2MEStudio/actions/runs/41999492045)、[两个 App 的 IPA/.app/截图](https://github.com/a526437928/J2MEStudio/actions/runs/41999492045/artifacts/13402527134)、[真机问题与修复记录](docs/真机问题记录.md)。7 项 Python 测试、26 项游戏库/ZIP 检查、145 项显示/配置/RMS 检查及新增实际诊断 Canvas 输入回归通过；通用 App 的 8 个和独立 App 的 2 个真实 miniJVM 场景通过。合成输入现在走真实方向盘分区计算和数字键按钮处理，断言实际键码为 54。两个真机目标均编译并封装 IPA，CI 产物均未签名，新版真机操作未复验。

第三、四阶段历史：[0.4.0 构建 #9](https://github.com/a526437928/J2MEStudio/actions/runs/41989259650)、[验收记录](docs/第三四阶段验收.md)。

第二阶段历史：[0.2.0 成功构建 #5](https://github.com/a526437928/J2MEStudio/actions/runs/41980458006)、[验收记录](docs/第二阶段验收.md)。

Windows 与 GitHub macOS Runner 均已实际编译 439 个 Java API 源文件及原仓库测试 MIDlet，源码检查、RMS 宿主测试和打包回归测试通过。[真实云构建 #1](https://github.com/a526437928/J2MEStudio/actions/runs/41974554625) 已成功编译 C/Objective-C/Swift，并上传真机 `.app` 及未签名 IPA。IPA 仍需要在 Windows 本地重新签名。**不能把 Java 编译、iOS 编译、IPA 封装、签名和 iPhone 运行视为同一结果。** 最新证据见 [第一阶段审查](docs/第一阶段审查.md)。

## 使用

点击“+”导入合法 JAR；同名不同内容分别保存，同内容复用记录。长按游戏可配置分辨率、帧率和 3D 增强，查看运行记录或管理存档。左上角“测试 MIDlet”安装本项目自编、Apache-2.0 的中文诊断程序。旧 JAR 与存档迁移保留备份，歧义归属会提示。

0.4.1 更新后请重新点“测试 MIDlet”，选择 **J2ME Studio 诊断 0.4.1**；旧条目及其存档保留，但仍是旧程序，不能用于验证组合诊断修复。RMS 为自动保存，画面第三、四行显示次数和状态；同一个诊断退出重开后次数应加一。

游戏内“设置 → 显示与按键”选择方向与缩放，调整大小、透明度及位置；横竖屏分别保存。游戏菜单可备份/恢复 RMS 或导出日志。详细验证结果与独立 App 构建命令见 [第三、四阶段验收](docs/第三四阶段验收.md)。所有自动化游戏资源均为自编诊断 MIDlet；《诛仙伏魔录》尚无合法且验证过的 JAR，未打包。

## 仓库结构和构建

```text
J2MEEmulator.xcodeproj/     根目录的 Xcode 工程，shared scheme: J2MEEmulator
J2MEEmulator/UI/            UIKit 游戏管理、游戏画面、虚拟按键
J2MEEmulator/NativeBridge/  JNI 风格原生桥接、2D/3D/音频
J2MEEmulator/minijvm/       已随仓库提交的 C JVM 及 TLS/压缩/线程依赖
J2MEEmulator/Resources/     原版运行库 JAR、API JAR、SoundFont
j2me_api/src/              Java ME API 源码
test_midlet/               原仓库的测试 MIDlet，无商业游戏
fixtures/studio_diagnostics/ 本项目自编的中文诊断 MIDlet
standalone.example.json    独立 App 显示和专用按键配置示例
scripts/                   跨平台 Java 编译、检查、真机构建及 IPA 封装
.github/workflows/         macOS 自动构建
```

不需要创建 `miniJVM-2.0.0` 假目录，也不需要 CocoaPods、SwiftPM 或 Maven。原 README 引用的外部路径不在仓库中。miniJVM **C 核心由 Xcode 直接编译**；Java 启动类库 `minijvm_rt.jar` 暂时采用原仓库版本并锁定 SHA-256。其完整源码对应关系仍待验证，绝不以最新上游运行库替换冒充修复。

Windows 安装 JDK 17 或更新版本并设置 `JAVA_HOME`，在本仓库运行：

```powershell
python scripts/check_project.py
python scripts/build_java.py all
python scripts/check_project.py --built-java
python scripts/test_rms_host.py
python -m unittest discover -s tests -v
```

macOS / GitHub Actions：

```bash
bash scripts/build_ios.sh
```

工作流固定 `macos-26`、Xcode 26.3 和 Temurin 17。按 [Runner 官方清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)选择版本；镜像会更新，若移除该 Xcode，选择步骤会明确失败。最低系统统一为 iOS 18.0。未启用 JIT 特权。

工作流监听 `main`、`codex/**` 分支和 PR，并支持手动执行。没有证书、密码或 Apple 登录步骤。构建成功后先保存实际 `.app`，再封装 `J2MEStudio-unsigned.ipa`；即使 IPA 封装失败也保留 `.app`。构建和检查错误会使任务失败，日志与 `.xcresult` 在失败时仍尝试上传。

## 推送并开始云构建

本地工程和 `J2MEStudio.bundle` 包含完整 Git 历史，基线提交与上游 `8afc8d808ca22160139333d1d58138c7dca91169` 相同。最新开发代码在 `codex/studio-complete` 分支；后续修改后可在含 `.git` 的工程目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish.ps1 -Branch codex/studio-complete
```

若 Git Credential Manager 打开登录窗口，请本人在浏览器完成 GitHub 登录。脚本仅推送新分支，不强制覆盖远端 `main`。仓库 Actions 页面应出现 `iOS unsigned device build`；Fork 首次使用可能需要手动启用 Actions，然后选择该分支 Run workflow。公共仓库使用 GitHub 标准托管 Runner 通常免费，须以账号当时的额度和规则为准。[GitHub 计费说明](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions)

第一阶段历史产物：[未签名 IPA 与 .app Artifact](https://github.com/a526437928/J2MEStudio/actions/runs/41974554625/artifacts/13391216595)、[日志与 xcresult](https://github.com/a526437928/J2MEStudio/actions/runs/41974554625/artifacts/13391236607)。GitHub 产物保留 14 天，本地交付也保存了真实下载副本。

下载、签名、安装与存档备份见 [Windows 侧载指南](docs/Windows侧载指南.md)。许可证和后续工作见 [第三方声明](THIRD_PARTY_NOTICES.md)及[架构与后续阶段](docs/架构与后续阶段.md)。
