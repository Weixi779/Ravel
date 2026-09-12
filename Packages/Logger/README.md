# Logger

本地 Package 的统一日志入口，无第三方依赖。`Logger.make` 返回原生 `os.Logger`，
调用方可以直接使用系统的日志等级、插值格式和逐字段隐私控制，无需 App 初始化。

```swift
import Logger

private let logger = Logger.make(category: "JJClient")

logger.debug("Command started")
logger.info("Command completed count=\(count)")
logger.error("Command failed operation=\(operation, privacy: .public)")
```

其他本地 Package 在 `Package.swift` 中添加 `.package(path: "../Logger")`，
并在使用它的 target dependencies 中添加 `.product(name: "Logger", package: "Logger")`。
只需 `import Logger` 即可打日志；同时导入 `os` 且需要声明类型时，使用 `os.Logger` 区分。

subsystem 统一使用宿主的 bundle identifier；无 bundle identifier 时使用 `Logger`。
category 由调用方声明，无需集中注册所有业务模块。建议按模块或职责命名，
把请求 ID、数量、耗时等变化值放在消息中。

日志直接进入 Apple unified logging。在 Xcode 控制台或 macOS Console 中按
subsystem/category 筛选，或实时查看 Ravel 的日志：

```sh
log stream --level debug --predicate 'subsystem == "com.weixi.Ravel"'
```

采集、显示和保存等级沿用系统策略，本 Package 不设置全局日志级别。
字符串插值保留原生隐私规则；确认可公开的诊断值显式使用 `privacy: .public`。
Ravel 的接入点记录命令类型、数量、耗时及错误类型，不记录仓库路径、内容或原始 stderr。

第一版只统一创建入口和 subsystem/category 约定。原生返回值绑定 OSLog，
不提供 backend 替换、双输出、结构化 metadata、远程发送或日志查询导出；
接入第二种输出时再确定调用 API 和路由边界。

验证：`swift build --package-path Packages/Logger`。Ravel 的 macOS 测试覆盖实际调用流程。
