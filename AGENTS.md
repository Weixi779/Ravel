# 开发约定

## 文件头

- 手写源码、测试、脚本与构建配置使用包含文件名、项目名 `Ravel`、创建信息和版权声明的文件头。作者使用 `weixi`；移动或修改已有文件时保留原创建日期。
- 版权行统一为 `Copyright © 2026 Ravel contributors. All rights reserved.`，并附 `SPDX-License-Identifier: Apache-2.0`，沿用仓库现有许可证。新增年份或跨年维护时按实际情况更新年份。
- 保留 Swift Package 的 `swift-tools-version` 和脚本 shebang 在第一行，文件头置于其后。生成代码及第三方代码保留原有头信息，不手工覆盖。

## 目录组织

- 应用代码按业务域放在 `Sources/Ravel/Domains/<Domain>/`，域内按职责使用 `Domain/`、`Application/`、`Presentation/`、`Infrastructure/`；只建立实际需要的层。
- `Domain/` 放领域值和规则；`Application/` 放应用工作流和请求；`Presentation/View/` 放界面，`Presentation/ViewModel/` 放界面状态、会话和派生展示模型；`Infrastructure/` 放后端适配与偏好存储。不使用泛化的 `UI/` 目录集中收纳界面。
- 本地化等展示扩展直接放在对应的 `Presentation/`；有需要独立组织的局部组件时才建立 `Presentation/Component/`，不预先补齐空目录。
- `App/` 负责应用生命周期与功能组装；`Domains/Repository/` 负责共享仓库模型与访问；`Shared/` 只放确有多个业务域使用的代码，并按相同职责分层。
- 设置界面使用已有状态所有者，没有独立状态时不额外创建 ViewModel。目录分层不要求额外包装现有状态所有者或补齐空层；文件和类型命名可单独调整。
- 测试按相同业务域及被测职责整理，跨层集成测试可放在对应业务域根目录，共用测试工具放在 `Tests/RavelTests/Support/`。

## 本地化文案

- `I18n` 提供 `LocalizedStringResource`。SwiftUI API 支持该类型时直接传入，例如 `Text(I18n.historyTitle)`、`Button(I18n.commonRetry) { ... }`、`.help(I18n.diffFind)`，不要先包装为 `String(localized:)`。
- 自定义展示函数的本地化标题优先接收 `LocalizedStringResource`；需要同时接收本地化文案与动态原文的展示内容时，可接收 `Text`，在调用处明确 `Text(I18n.xxx)` 或 `Text(verbatim: value)`。
- 仅在 API 或数据确实要求 `String` 时使用 `String(localized:)`，例如 AppKit 文案属性、`LocalizedError`、字符串返回值、生成的插值参数及字符串断言；不要为省略必要转换而增加包装层。
- 仓库描述、路径、标识符和原始错误等动态内容保留原文，不作为本地化 key。文案在 `Localizable.xcstrings` 维护，通过 `Tools/updateLocalization` 生成 `I18n`，不手改生成文件。

## SwiftUI 排版

- View 构造与每个链式修饰符分别占一行，例如 `.font`、`.fontWeight`、`.foregroundStyle`；即使表达式很短，也不要合并到同一行。
- 同级相邻组件之间保留一个空行。每个组件及其连续修饰符作为一个完整块，块内不插入额外空行，便于看清组件边界和修饰符归属。
- SwiftUI 组件的 action、label 等闭包内容展开换行，不将按钮等组件的闭包压在一行。
- 格式化后仍须保留上述排版；以 `RevisionFileListView.swift` 的现有写法作为参考。

## Swift 格式化

- 每轮 Swift 代码新增、修改或重构完成后，交付或提交前，必须在项目根目录运行一次 `Tools/format`。
- 使用项目现有的 `.swiftformat` 配置和脚本覆盖范围；生成代码、依赖、构建产物及 `research` 按配置排除。
- 检查格式化产生的差异，确认没有混入与当前任务无关的手动改动。
