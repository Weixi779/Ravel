# Ravel 0.1.0 第三方声明草案

## 0.1.0 整合包的声明范围

旧版 `edff7a20` 的主程序静态链接 STTextView、STTextKitPlus 和 CoreTextSwift。0.1.0 已采用原生 `NSTextView`，整合 commit `32b9dedb05c04a0d5b4dbdc7b7c56b62e4da5e3d` 的 App 与测试目标都已移除它们，源码依赖锁仅剩供编译宏使用的 swift-syntax 602.0.0。其 Release 链接对象、解包主程序的符号、动态库列表与 bundle 文件清单中，这三个包各为零命中。原生文本视图来自系统 AppKit。

0.1.0 保留 Ravel 自有代码的 Apache-2.0 许可。随包声明覆盖下表中的 Rust 库、数据及工具链条目。两个普通包的 212 组 Rust 包名、版本与许可一致。保留第三方版权、许可、适用 NOTICE 与 MPL 源码入口的工作仍需定稿。STTextView 的采购或 GPLv3 组合分发路线仍适用于选择含它的旧版产物。两包的源码版本与二进制核对结果见[分发记录](Distribution0.1.0.md#整合前后的开发机实测)。

## 旧版链接清单与沿用的 Rust 组件

以普通 arm64 Release `014b8312c86c9b48ac63b4aef5ac616ec9fdbc56` 核对。该包的 Rust 清单包含 202 条已与 registry 名称和版本匹配的归属记录，以及 10 条需按工具链核对的记录。下表供发布负责人定稿。每次打包的 `report.md` 标识精确源码和 ZIP，`link-map.txt.gz` 保存链接器证据，`linked-rust.tsv` 列出可从有效符号归属到 Rust archive member 的具体包名、版本和许可。

| 实际组件 | 锁定版本与许可 | 公开发布时随附或说明 |
| --- | --- | --- |
| STTextView，含 AppKit、Common、SwiftUI 模块 | 2.4.1 · Marcin Krzyżanowski · GPLv3 / 商业授权（仅涉及含该组件的旧包） | 保留作者声明；GPLv3 路线需要组合程序对应源码与许可，商业路线按采购合同核定席位、公开仓及下游分发。见[该版本的许可](https://github.com/krzyzanowskim/STTextView/blob/bbdcfd9d413ad3055dafd23a223be9bd39742f89/LICENSE.md)。 |
| STTextKitPlus | 0.3.1 · Marcin Krzyżanowski · BSD-3-Clause | 随二进制附版权、完整条件和免责声明。[原文](https://github.com/krzyzanowskim/STTextKitPlus/blob/8117f3b6a20633e4ce92df102dd260b808ffc9bd/LICENSE.md) |
| CoreTextSwift | 0.2.0 · Marcin Krzyzanowski，2020–2023 · MIT | 附版权和许可原文。[原文](https://github.com/krzyzanowskim/CoreTextSwift/blob/833177201d6421e6322296f39fce6ff6ae52618a/LICENSE.md) |
| `jj-lib`、`jj-cli`、`gix` | 0.41.0、0.41.0（Apache-2.0）；gix 0.83.0（MIT OR Apache-2.0） | 三者的代码通过 `libravel_backend.a` 进入主程序。整理锁定源码的版权、许可及适用 NOTICE；随包保留所选条款。[Jujutsu 许可](https://github.com/jj-vcs/jj/blob/v0.41.0/LICENSE) |
| `uniffi_core` | 0.32.0 · MPL-2.0 | 提供 MPL 文本及接收者可取得该版本 MPL 涵盖源码的位置，连同实际补丁。[锁定源码包](https://crates.io/crates/uniffi_core/0.32.0) · [MPL §3](https://www.mozilla.org/en-US/MPL/2.0/) |
| Unicode、编解码和其他 Rust 库 | 如 ICU4X `icu_segmenter` 2.3.0 等（Unicode-3.0），`wezterm-bidi` 0.2.3（MIT AND Unicode-DFS-2016），`encoding_rs` 0.8.41（含 BSD-3-Clause），`zlib-rs` 0.6.8（Zlib） | 按每个锁定包及其数据文件收集实际版权和许可全文，保留复合许可各组成部分。其余逐项见当次 `linked-rust.tsv`。[Unicode 许可](https://www.unicode.org/license.txt) |
| Rust 标准库与随工具链链接的代码 | Rust 1.96.0；可见 `std`、`core`、`alloc`、`compiler_builtins` 等 | 以该工具链的 `share/doc/rust/COPYRIGHT-library.html` 复核各组成部分的原文及例外。[Rust 许可说明](https://rust-lang.org/policies/licenses/) |

核对方法：以最终 Mach-O 的 link map 有效符号和包内清单为准，Cargo depfile 对回 crates.io 包版本。`cargo-dependencies.txt` 还包括宏及可能被内联的依赖，须结合锁文件、源码中的数据许可及 NOTICE 补核；单看 archive member 无法穷尽内联代码。SwiftSyntax 用于宏构建，普通包中没有 SwiftSyntax 框架或宏插件可执行文件。Apple 的 AppKit、SwiftUI 和系统动态库记于 `dynamic-libraries.txt`。本草案及生成的清单可用来整理随包原文，正式发布前仍需装入选定授权路线要求的材料。
