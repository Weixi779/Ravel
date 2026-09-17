# 开发约定

## 目录组织

- 应用代码按业务域放在 `Sources/Ravel/Domains/<Domain>/`，域内按职责使用 `Domain/`、`Application/`、`Presentation/`、`Infrastructure/`；只建立实际需要的层。
- `Domain/` 放领域值和规则；`Application/` 放应用工作流和请求；`Presentation/View/` 放界面，`Presentation/ViewModel/` 放界面状态、会话和派生展示模型；`Infrastructure/` 放后端适配与偏好存储。不使用泛化的 `UI/` 目录集中收纳界面。
- 本地化等展示扩展直接放在对应的 `Presentation/`；有需要独立组织的局部组件时才建立 `Presentation/Component/`，不预先补齐空目录。
- `App/` 负责应用生命周期与功能组装；`Domains/Repository/` 负责共享仓库模型与访问；`Shared/` 只放确有多个业务域使用的代码，并按相同职责分层。
- 设置界面使用已有状态所有者，没有独立状态时不额外创建 ViewModel。目录分层不要求额外包装现有状态所有者或补齐空层；文件和类型命名可单独调整。
- 测试按相同业务域及被测职责整理，跨层集成测试可放在对应业务域根目录，共用测试工具放在 `Tests/RavelTests/Support/`。

## Swift 格式化

- 每轮 Swift 代码新增、修改或重构完成后，交付或提交前，必须在项目根目录运行一次 `Tools/format`。
- 使用项目现有的 `.swiftformat` 配置和脚本覆盖范围；生成代码、依赖、构建产物及 `research` 按配置排除。
- 检查格式化产生的差异，确认没有混入与当前任务无关的手动改动。
