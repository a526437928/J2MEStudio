# Windows → iPhone 安装与更新

当前 **0.4.2 (6)**：[成功构建 #11](https://github.com/a526437928/J2MEStudio/actions/runs/42025151337)、[下载 IPA Artifact](https://github.com/a526437928/J2MEStudio/actions/runs/42025151337/artifacts/13414442134)。本地交付为 `cloud-build-11/device/J2MEStudio-unsigned.ipa`。Artifact 内另一份 `StudioDiagnostics-standalone-unsigned.ipa` 是点图标直接启动的独立诊断 App，使用不同 Bundle ID；通常先安装通用模拟器即可。

已开始测试旧版的用户先备份完整 Documents，再用相同 Apple ID 和最终 Bundle ID 覆盖更新，不卸载旧 App。旧包保留在 `cloud-build-5/device` 和 `cloud-build-9/device`；不同云构建目录不可混淆。

本次 0.4.2 修复方向盘斜向触发 1/3/7/9 技能。保持原签名账号、最终 Bundle ID 和安装选项，将新版 IPA 拖入 Sideloadly，点击 Start 覆盖更新；不先卸载。更新后直接打开已有《诛仙伏魔录》，无需删除或重新导入 JAR。进入“设置 → 显示与按键 → 方向盘模式”，选择默认的“数字方向”。依次测试四个斜向，应能移动且不误放数字技能；右侧数字 1/3/7/9 仍应主动触发技能。如果游戏不能识别两数字方向组合，再试“独立方向”并分别记录移动结果。“旧八向”保留原斜向数字键，会继续触发这款游戏的技能。详见[方向盘修复报告](方向盘斜向修复.md)。

如需诊断回归，再点“测试 MIDlet”，选择 **J2ME Studio 诊断 0.4.2**。旧诊断条目及旧存档保留，不能拿旧程序验证新增诊断；新诊断的计数从其自身首次值开始比较。仅测试已有游戏的斜向修复不需要此步骤。

## 下载与辨别产物

1. 打开自己仓库的 Actions，选择 `iOS unsigned device build`，核对提交和该次运行结论。
2. 在 Artifacts 下载 `J2MEStudio-device-运行号`，解压最外层 GitHub Artifact ZIP。
3. 使用里面的 `J2MEStudio-unsigned.ipa`。不要把 Artifact ZIP、源码 ZIP 或 `device-app.zip` 直接拖给安装工具。
4. IPA 本身是 ZIP；应包含 `Payload/J2MEStudio.app/Info.plist`、arm64 可执行文件和两个运行库 JAR。CI 的封装检查会拒绝模拟器包和缺失运行库的包。通过检查代表结构和目标平台符合预期，不能保证签名或运行成功。
5. 若仅有 `device-app.zip`，说明 `.app` 已保存但 IPA 可能封装失败；查看同一次运行 diagnostics 的原因，不要自行把失败标为通过。

## Sideloadly 签名与安装

1. 从 [Sideloadly 官方网站](https://sideloadly.io/) 安装 Windows 版，按官网当时要求配置 Apple 驱动/iTunes/iCloud。官网目前要求 Windows 使用网页发行版本的 iTunes 和 iCloud。
2. 用 USB 连接、解锁 iPhone，选择“信任此电脑”。打开 Sideloadly，确认正确设备。
3. 将未签名 IPA 拖入 Sideloadly，使用自己的免费 Apple ID 完成本机签名，按程序提示处理双重认证。密码只在本人本机的官方程序流程中输入，绝不放进仓库、Actions Secrets、脚本、聊天或日志。
4. 点击 Start，等待签名和安装结束。保存错误码和不含敏感内容的日志以便排查；IPA 已生成不代表此步骤已成功。
5. 在 iPhone 的“设置 → 隐私与安全性 → 开发者模式”开启，按提示重启并确认。若开关未出现，先完成开发签名 App 的安装尝试，再检查。参照 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
6. 若系统提示不受信任的开发者，在“设置 → 通用 → VPN 与设备管理”中信任本人用于签名的开发者，然后运行 App。

原工程最低支持 iOS 18.0；不要通过安装工具强改最低版本来冒充旧系统兼容性。iOS 路径使用解释器，无需打开 JIT 功能。

## 免费账号限制

[Apple Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account)当前列出：每台设备最多安装 3 个此类 App、最多登记 3 台设备、最多登记 10 个 App ID；相关登记和描述文件存在 7 天期限。Sideloadly 官网也说明免费账号签名通常有效 7 天，需要重新签名/刷新。这些属于 Apple 账号与签名限制，与模拟器内导入多少个 JAR 无关。Apple 规则可能改变，以实际签名提示为准。

## JAR 导入与验证

打开 App 后用“+”按钮从文件 App 选择 `.jar`；也可通过 iTunes 文件共享或文件 App 将合法 JAR 放入应用 Documents，再刷新/重新进入列表。点击左上角“测试 MIDlet”可直接安装本项目自编的中文诊断程序，不需要寻找商业 JAR。Artifact 附带 `studio_diagnostics.jar`，可以保存到手机文件 App 后用“+”导入；同内容重复导入应复用已有游戏记录。原仓库 `test_midlet.jar` 也保留。不能因为能导入就认为已能运行。

启动诊断游戏，依次检查中文、长按右方向、右方向加数字 5 的双指组合、松开后的停止重复、后台返回、退出重开和完整关闭 App 后的 RMS 次数增加。此诊断程序没有音频测试资源，不把它的通过计为音效验收。

0.4.0 可在游戏“设置 → 显示与按键”测试自动旋转/锁定方向、三种缩放、按键大小/透明度、拖动组与逐键拖动/缩放。完成编辑后退出重开，确认专属配置仍保留。原始像素模式会有较小画面，这是 1:1 物理像素显示；可切回保持比例适应。

## 更新与备份

更新前先备份应用整个 Documents，包括 `library.json`、`games`、`Saves`、`Configurations`、`Backups`，以及存在时的 `Games Data` 和 `Import Backups`；缺少 library.json 会丢失 UUID 与存档的对应关系。可用 iTunes 文件共享将应用文档保存到电脑；若文件 App 能看到应用文件夹，也可将完整内容复制到别处，并确认文件数量和关键索引存在。尽量使用相同 Apple ID、相同最终签名 Bundle ID、相同安装选项覆盖更新，保持数据容器。不要先删除旧 App；卸载通常会删除本地存档。重新签名工具改变 Bundle ID、换 Apple ID 或操作系统策略变化都可能影响覆盖安装和数据保留，必须先备份。

游戏列表的 RMS 快照位于同一应用沙盒，不能替代卸载前的电脑备份。长按游戏可导出当前及历史运行日志。若 App 无法打开，在 iPhone“设置 → 隐私与安全性 → 分析与改进 → 分析数据”寻找对应时间的 J2MEStudio/JetsamEvent 报告；分享前检查并遮去个人信息。完整系统报告需设备提供，App 内日志不保证包含原生堆栈。

本阶段改用了项目自己的 Bundle ID `org.j2mestudio.emulator`，若之前安装过上游 JarBox，它可能作为另一 App 安装；先手动备份，不承诺自动迁移。第二阶段已采用 UUID 隔离；旧版中文名称碰撞会提示并保留原件，不自动猜测存档归属。
