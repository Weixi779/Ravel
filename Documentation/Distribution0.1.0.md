# Ravel 0.1.0 分发记录

0.1.0 整合线已采用 AppKit 原生 `NSTextView`。后续 A4 使用[下文指定的普通 arm64 Release 包](#a4-下载验收)。Fetch/Push 顺延。

最早的本地 Release 测试包基于共同基线 `ssw/release-0.1.0-base`，commit `c6382ffde5b79566e9ec0c1c98bfde265b79bb59`。它是供开发机验证的 arm64 构建。远端探针使用另外一个 bundle identifier 和测试入口。正式签名、公证、tag 和上传由发布负责人执行。

## 早期构建中 STTextView 2.4.1 的链接与授权评估

Xcode 项目为 App 和测试目标都声明了 `exactVersion = 2.4.1`。`Package.resolved` 和构建所用 checkout 的 HEAD 均为 `bbdcfd9d413ad3055dafd23a223be9bd39742f89`。上游 manifest 的 `.library` 没有指定静态或动态类型。Release 的 `Ravel-LinkMap-normal-arm64.txt` 把 `STTextView.o`、`STTextViewAppKit.o`、`STTextKitPlus.o`、`CoreTextSwift.o` 列为主程序输入。`nm` 在主 Mach-O 中找到已定义的 `STTextViewAppKit` / `addPlugin` 符号。`otool -L` 中没有 STTextView 动态库，包内也没有对应 framework。此产物把库静态链接进 Ravel。[锁定版本的 Package.swift](https://github.com/krzyzanowskim/STTextView/blob/bbdcfd9d413ad3055dafd23a223be9bd39742f89/Package.swift) · [锁定版本的许可](https://github.com/krzyzanowskim/STTextView/blob/bbdcfd9d413ad3055dafd23a223be9bd39742f89/LICENSE.md)

| 可选路线 | 公开源码与可下载二进制 | 成本与对 3 号 Diff 的影响 |
| --- | --- | --- |
| 保留 STTextView，组合分发遵循 GPLv3 | 可维持独立 Ravel 自有代码的 Apache-2.0 授权，写清各部分的权利和组合程序的 GPLv3 条件。若统一调整项目许可证，另由负责人决定。源码仓如复制或修改上游代码，须保留相应版权、许可及修改说明。发 App 时随附 GPLv3、版权和免责信息，同时按下述方式交付精确对应的完整源码。 | 无商业许可费。每个公开二进制都需要配套源码、构建输入、清晰的下载指引和维护责任。3 号可保留现有渲染、行号、选择、搜索与滚动实现。 |
| 保留 STTextView，购买商业授权 | 作者草案允许将组件集成进应用再分发，限制单独再分发组件。确认最终合同覆盖 Ravel、实际开发人数、公开源码仓、外部贡献者自行构建及其再分发权利。公开 Ravel 自有源码时写清边界，购买者的权利不会自动转授给每位 fork 作者。 | 核对时官网公开档位为个人 €25、最多 8 名开发者 €65、组织 €500，最终税费、适用档位和授予条款以购买时合同为准。草案个人及团队档各限 1 个应用，组织档 10 个。3 号无渲染迁移，发布前须确认和保存授权。 |
| 移除 STTextView，保留 Apache-2.0 自有代码 | 用 AppKit `NSTextView` / TextKit 重建展示，移除 App 与测试目标的产品引用、imports 和无主依赖。复查新 Release 的 link map、符号、包内容和剩余依赖声明。 | 无 STTextView 采购费用。成本集中在双列和统一视图、视口装饰与行号对齐、查找、文本选择和大文件滚动回归。3 号可继续做 hunk 身份、勾选状态、补丁生成和写前校验；新交互应通过 hunk / 文件身份沟通，直接依赖 `STPlugin`、布局片段及鼠标命中的部分需随渲染器联调。 |

源码仓当前以 Apache-2.0 授权 Ravel 自己的代码，锁文件仅引用上游。公开自有源码、随包复制第三方源码、分发已经链接的应用是三种交付物。Apache-2.0 可纳入 GPLv3 组合物；改成动态链接也不能据此将组合程序作为纯 Apache-2.0 发布。GPL 下载路线可采用 §6(d)，在二进制下载位置明确提供对应源码的等价免费获取方式。准备与该产物一致的 Ravel 源码、实际使用的非系统依赖源码及本地补丁、接口定义、工程和控制编译安装的脚本，保留两套锁文件与原始许可和 NOTICE。仅给 `main` 或一个锁文件不足以交付这些源码。可复现步骤不要求公开开发者签名私钥。开源组合程序的分发条件也适用于接收者后续再分发。[GPLv3 §1、§4–6](https://www.gnu.org/licenses/gpl-3.0.html) · [Apache Software Foundation 的兼容性说明](https://www.apache.org/licenses/GPL-compatibility) · [作者报价](https://krzyzanowskim.gumroad.com/l/sttextview) · [作者的商业授权草案](https://github.com/krzyzanowskim/STTextView/files/13804713/STTextView.Commercial.Licence.-.draft.pdf)

`STTextKitPlus 0.3.1` 为 BSD-3-Clause，源码保留原文，二进制随附版权、条件和免责声明；`CoreTextSwift 0.2.0` 为 MIT，随分发保留版权与许可。三条路线均须按最终链接清单复核其余依赖。Rust 的 `libravel_backend.a` 同样并入主程序，`cargo tree --locked --target aarch64-apple-darwin -e normal` 可见 `uniffi` / `uniffi_core` 等 MPL-2.0 组件和 Unicode 数据。MPL 涵盖文件应告知接收者如何获取相应源码。发布时应对照 link map、锁文件和各包原文整理通知和源码位置，另行识别仅用于宏或构建的依赖。目前测试包尚未完成公开分发用的第三方声明。[STTextKitPlus 许可](https://github.com/krzyzanowskim/STTextKitPlus/blob/8117f3b6a20633e4ce92df102dd260b808ffc9bd/LICENSE.md) · [CoreTextSwift 许可](https://github.com/krzyzanowskim/CoreTextSwift/blob/833177201d6421e6322296f39fce6ff6ae52618a/LICENSE.md) · [MPL 2.0 §3](https://www.mozilla.org/en-US/MPL/2.0/)

## 本地打包

在分发 workspace 根目录运行下列命令，参数可以是已提交的完整 commit ID 或仅指向一个 commit 的本地 bookmark。工具先解析完整 ID，导出该版本的源码，在独立目录运行普通 `Ravel` scheme 的 Release 构建。Xcode 使用锁定的 SwiftPM 版本，工程自带的 `Tools/buildBackend` 使用 Rust 1.96.0 和 `cargo build --locked --release`。本机用 Xcode 27.2、Apple Swift 6.4.2 及 `aarch64-apple-darwin` target。首次构建需要能获取锁定的依赖。

```sh
Tools/packageLocalRelease 32b9dedb05c04a0d5b4dbdc7b7c56b62e4da5e3d
```

快照解包时使用当前修改时间，使 Cargo 在跨 revision 复用缓存时重新检查并编译本地 Rust 源码。归档中的 commit 时间可能比上次生成的静态库更早。

工具复用当前 workspace 的 `.build/SourcePackages`、`.build/rust-target` 和 `.build/ReleaseDerived`。每次运行生成独立的 `.build/Distribution/<commit>-<运行编号>/`，包含普通产品 ZIP、`unpacked/Ravel.app`、`report.md`、完整构建日志、link map 以及依赖清单。报告记录 ZIP 的实际 SHA-256、源码 commit、签名详情和 Gatekeeper / 票据检查的原始退出码。相同源码可重跑整个流程，每次 ZIP 的散列受文件时间戳等因素影响。

普通产品使用 `com.weixi.Ravel`。打包工具逐文件比对解包结果、验证签名，并检查包内是否混入诊断资源。两轮远端传输实测中，服务端静默时取消操作均未能及时结束 Git 子进程，因此 0.1.0 的验收范围限于本地仓库操作。公开发布前的依赖工作见[第三方声明草案](ThirdPartyNotices0.1.0.md)。

### 共同基线的首次 Finder 验证

本次 ZIP 为 `Ravel-0.1.0-arm64-local.zip`，26,547,892 字节，SHA-256 `18c735de7e5630ca7f39c6e8360f23b81aa0652abd75ad22d679c45e827d3c6d`。Swift 使用 `-O`，本次构建日志中没有 `-profile-generate` / `-fprofile-instr-generate`。ZIP 解包后文件逐一比较相同，`codesign --verify --deep --strict` 通过。Finder 打开解包副本后，Launch Services 登记的实际可执行路径为 `verify/Ravel.app/Contents/MacOS/Ravel`，PID 30826。版本 `0.1.0 (1)`，bundle ID `com.weixi.Ravel`。`codesign` 显示 `adhoc,runtime`、无 TeamIdentifier；`spctl -a -t exec -vv` 返回 `rejected`，`stapler validate` 返回无票据。未向 Apple 提交此包。

## 整合版本的开发机验收

先以探针资料所在的 `10aa39d8` 重跑普通构建，通过 ZIP 解包逐文件比对和严格签名验证。整合线随后确认 `014b8312c86c9b48ac63b4aef5ac616ec9fdbc56` 已通过 macOS 与 Rust 测试。基于该完整 ID 制作的普通 ZIP 为 27,696,129 字节，SHA-256 为 `c7e48d6d4e56c096cd6de92758fbe3471f4b1458c5d4d96a50f80b135d1d8e09`。本次运行目录为 `.build/Distribution/014b8312c86c-u4wtvfna/`，内含原始报告和依赖证据。

从 Finder 打开解包后的产品（PID 57862），在一次性仓库中选中 A、右键旧 B，在“编辑描述”里保存新标题和两行正文。图刷新后选中 B。独立 jj 回读确认 B 的 Change ID `xxmxkomq…` 保留，commit 从 `aa25051e…` 变为 `f4792aad…`，工作副本仍是 A。普通包无 R0 helper；Gatekeeper 评估为 rejected，无装订票据。

## A4 下载验收

A4 的源码固定为 `32b9dedb05c04a0d5b4dbdc7b7c56b62e4da5e3d`。沿用已完成 Finder 验证的普通 Release 0.1.0 (1)，ZIP 的 SHA-256 为 `4153fcccfedf2513a04a97d2d3c3b1543ede9f1336bd1f16629e39a073c7f723`。按[本地打包](#本地打包)重建时，工具会打印包含 ZIP 和 `report.md` 的本次输出目录。

发布前仍需定稿与实际能力相符的 README、第三方声明和源码入口。此包仅覆盖 arm64，`LSMinimumSystemVersion=15.0`；如承诺 Intel，还需单独构建并验证相应 Rust target、所有内嵌代码和最终 Mach-O 的 x86_64 切片。

最终应用需使用 Developer ID Application、安全时间戳和 hardened runtime 签名，提交公证、取得 Accepted 结果，将票据装订到 App 后重新打包 ZIP，核对最终散列。使用从实际下载渠道取得且保留 quarantine 的包，在无开发工具链、全新用户或干净 Mac 上正常解压、移入 Applications 并从 Finder 打开。核验 Gatekeeper 放行及离线票据、签名标识、资源完整、首次打开本地 jj 仓库与第 2 节完整场景。分别验证声明的最低系统和架构。Fetch/Push 已顺延；本版下载验收以本地仓库流程为范围。[Apple 公证流程](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Apple 分发测试说明](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) · [首版验收场景](Release0.1.0.md)

## 整合前后的开发机实测

此前交给第 2 节独立验收的普通整合版本为 `edff7a20d64f94911a8de69d536cb327e66bf5fc`。本地 ZIP 位于 `.build/Distribution/edff7a20d64f-23jwi18j/`，解包的应用在其 `unpacked/Ravel.app`。SHA-256 为 `43307d88c2565cccdc2a441f02a1d28f82afa32c9f80ac2bd9c2690535cb9ad6`。该包仍链接 STTextView。

已并入 0.1.0 的 `ssw/native-diff-reader` 包含上述整合版本。其只读视图使用 AppKit 的 NSTextView 和 TextKit 1，沿用原有文档、行号栏和 hunk 选择。两份 ZIP 可从各自 commit 通过 `Tools/packageLocalRelease` 单独重建。两者都使用普通产品标识，R0 诊断包仍使用单独的构建入口。

候选在 macOS 27.2.1 上通过了 96 项应用测试和 4 项本地化测试。6 项 Diff 回归各重复 30 次，覆盖深浅外观下的底边像素、读写保护、复制和查找栏、独立横滚及双向纵滚。修复的两个渲染问题分别是行首被覆盖，以及跳滚时背景露出一条空白。后者按 AppKit 实际请求重画的区域取行。

同机 Debug 宿主中，预先准备文档，分别测 3 次更新及布局。双栏每侧 1,000 行，STTextView 和原生方案的中位数约为 14 与 7 毫秒。每侧 9,990 行时约为 36 与 27 毫秒。若打开后立即跳到尚未完成布局的远端行，原生方案会补齐两栏布局，此项在 9,990 行样本的中位数为 269 毫秒。计时不含补丁读取、文档投影或最终上屏的时间。

普通原生 ZIP 位于 `.build/Distribution/32b9dedb05c0-397dy30h/`，精确源码 `32b9dedb05c04a0d5b4dbdc7b7c56b62e4da5e3d`，SHA-256 为 `4153fcccfedf2513a04a97d2d3c3b1543ede9f1336bd1f16629e39a073c7f723`。从 Finder 打开该目录的解包 App 后，在一次性仓库查看 Settings.swift 的双栏 +2/−1，在右栏查找 jitter 命中 1 处。工作副本被选中时右键父提交执行 Describe，写入新标题和两行正文。保存后窗口选中改写的父提交，jj 回读确认其 commit 从 `0550bb35` 变为 `e5963efb`，Change ID 保持 `uqoslnutxnxrwutopnvyyzzplolpzstw`，工作副本仍在原来的子 change。两份包均为本机 ad-hoc 签名，无装订票据，Gatekeeper 评估拒绝。干净 Mac 的隔离下载、最低系统验证与正式签名公证仍待 A4。
