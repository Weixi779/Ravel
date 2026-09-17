# UserDefaultsKit

Swift 6 的同步 UserDefaults 工具包。提供强类型 Key、原生值 / Codable 编码、
可注入的 Store，以及两个可分别选择的入口：

- `UserDefaultsKit`：`@UserDefault` 只简化读写；运行时只依赖系统框架。
- `UserDefaultsKitMacros`：`@ObservedDefault` 生成可观察属性；编译插件依赖 SwiftSyntax 602。

```text
使用处的 @UserDefault(.业务Key) → UserDefaultsKit → Foundation.UserDefaults
使用处的 @ObservedDefault(.业务Key) → 同一 Store + 官方 ObservationRegistrar
```

使用处直接导入工具包。业务 Key 和默认值集中声明；工具包不包含业务 Key，也不要求
Preferences 实例、业务转发层或 FactoryKit。Ravel 目前把 Key 放在 `Sources/Ravel/UserDefaultsKeys.swift`，
将来的业务模块归属另行决定。

## 定义与配置

```swift
import UserDefaultsKit

// 业务侧集中声明；不创建全局可变的业务状态对象。
extension UserDefaultsKey {
    static var lastWorkspacePath: UserDefaultsKey<String?> {
        .init("lastRepositoryPath", default: nil)
    }

    static var recentWorkspacePaths: UserDefaultsKey<[String]> {
        .init("recentRepositoryPaths", default: [])
    }
}

// 任何需要这个属性的类型都可以直接使用，无需另一个 Preferences 实例。
final class WorkspaceModel {
    @UserDefault(.lastWorkspacePath)
    var lastWorkspacePath: String?
}
```

Key 定义名字、类型、默认值和编码方式，不绑定环境、不注册默认域、不写入初始值。
Key 按业务组织，不按返回类型拆分 extension；每个属性明确声明自己的 `UserDefaultsKey<Value>` 类型。
同一配置复用同一处 Key 定义；wrapper 不提供第二个默认值来源。
省略 `store:` 时使用不可替换的 `UserDefaultsStore.standard`，所有默认 wrapper 共用该 Store。
需要其他环境时传入 `store:`；构造 wrapper 不读写值，因此初始化时替换 backing storage
不会先读取或写入正式偏好。
库不建立全局 Key 注册表，调用方仍需避免为同一名字重新定义不同的 Key。

普通 Key 支持 String、Bool、Int、Double、Float、Data、Date，以及这些值构成的 Optional、
数组和 String-keyed 字典。原生解码严格区分字符串、布尔、整数、浮点等存储类别，
不做跨类别兼容转换：`"01"` 不会读成数字，`true` 不会读成 `1`，`1.0` 不会读成整数。
类别不匹配遵循下面的读取失败规则，原始值保留。Optional、数组和字典递归使用相同规则。
NSNumber 仍是 Foundation 必需的数值容器；Float / Double 同属浮点类别，按目标精度解包，
不记录原始 Swift 数值类型标签。自定义模型使用显式 Codable Key，存储格式为 JSON Data：

```swift
struct DiffOptions: Codable, Sendable {
    var contextLines: Int
}

let key = UserDefaultsKey<DiffOptions>.codable("diffOptions", default: .init(contextLines: 3))
```

编码器按调用创建。原生集合中的 nil 无法表示为 property list，会抛错；需要保留 null 元素时使用 Codable。
多层 Optional 不提供独立的三态持久化语义。

## 读写语义

- 未保存时返回 Key 默认值，不顺手持久化默认值。
- Optional 赋 nil 删除显式值；之后遵循 UserDefaults 的域查找，再回退到 Key 默认值。
- 赋值恰好等于默认值仍会保存；需要删除时显式 `reset`。
- `read`、`set`、`update` 可以抛错。读取坏数据保留原始值，编码失败保留旧值。
- 普通 wrapper getter 在读取失败时回退，setter 在写入失败时保留旧值；失败通过 Store 的
  `onFailure` 报告，默认写入系统日志。回调在锁外、调用线程上执行。
  原生通知同步重入时，失败先入队，等当前线程最外层 Store 操作释放锁后交付；
  重入的 getter 仍立即返回默认值。
- setter 同步完成当前存储调用，不承诺已经写入磁盘或提供多键事务。

```swift
let paths = UserDefaultsKey<[String]>("recentWorkspacePaths", default: [])
let store = UserDefaultsStore(defaults: defaults)
try store.set(["/workspace-A"], for: paths)
let restored = try store.read(paths)
try store.update(paths) { $0.append("/workspace-B") }
store.reset(paths)
```

wrapper 也提供 `set`、`reset`、`update`，宿主可通过 `_property` 使用它们。
初版不提供 `$property` 投影或自动 UI Binding。

## 观察宏

在业务模型里使用官方 `@Observable`，持久属性由我们的宏接管：

```swift
import Observation
import UserDefaultsKit
import UserDefaultsKitMacros

@MainActor @Observable
final class WorkspaceModel {
    private let store: UserDefaultsStore

    @ObservedDefault(.lastWorkspacePath, store: \Self.store)
    @ObservationIgnored
    var lastWorkspacePath: String?

    init(store: UserDefaultsStore = .standard) {
        self.store = store
    }
}
```

省略 `store:` 时使用 `.standard`。实例 Store 用强类型 KeyPath 传入；直接写 `store: store`
无法通过 Swift 的宏参数类型检查。Store 应在模型生命周期内保持稳定。
当前 Swift 编译器要求把 `@ObservedDefault` 写在 `@ObservationIgnored` **前面**。
`Ignored` 只阻止外层宏再次生成访问器，观察依赖仍由本宏生成的 getter 建立。
属性需要显式类型，默认值只写在 Key 中。

宏生成普通计算属性，不在模型里复制偏好值或保存订阅。Store 为每个被观察的 Key
持有一个共享的观察对象，由官方 `ObservationRegistrar` 记录读取和通知变化。
SwiftUI body 等 Observation 跟踪范围内读取属性即可建立依赖；普通 wrapper 的读取不建立依赖。

- 同一 Store 中，宏、普通 wrapper、`set`、`reset` 和 `update` 的写入都会更新观察者。
- 同一个 UserDefaults 实例发出的 `didChangeNotification` 也会被处理，因此直接写原生 UD
  能更新观察者；其他实例、其他进程的通知交付不属于本包的保证。
- 只通知持久表示发生变化的 Key；其他 Key、相同值以及未提交的失败写入不会通知。
- 为过滤通知，Store 保存被观察 Key 的原始表示快照；实际 getter 每次仍读取 UD。
  比较也区分数值类别，包括集合内部，避免 `true → 1` 等变化被 Foundation 相等判断吞掉。
- 第一次观察时才安装通知监听；观察身份与监听随 Store 释放，不保留模型。
- 当前每次访问结束（包括普通读取）都会扫描该 Store 曾经观察过的所有 Key。
  成本随 Key 数量和被比较值的大小增长，并非固定开销；本版保留这一策略。
- 通知表示需要重新读取最新状态，不是逐笔写入的事件流。重叠写入可合并失效通知。
  合并保留期间已经检测到变化的 Key：即使 `0 → 1 → 0` 回到原值，中途读取 `1`
  建立的依赖仍会被通知，不会被初末值相等抵消。
- 本包不提供 Publisher、AsyncStream 或专有 Binding；SwiftUI 可以对 Observable 模型使用 `@Bindable`。

Ravel 的 `LogSession` 中，最近工作区列表、上次工作区路径和 jj 路径统一使用宏，
通过 `\Self.store` 共用注入的 Store；初始化只保存 Store，无需逐个初始化 wrapper。
最近工作区列表直接从 Store 读取，不再额外保存一份列表副本。

## 并发边界

Store 的所有读写共用实例级递归锁；`update` 持锁完成读取、修改、编码和写回。
普通 `+=` / `append` 仍是独立的 getter、setter，不具备整个操作的原子性。
复合更新闭包应短小，只修改传入值，不访问 Store、不做 IO。
这些保证只覆盖同一 Store；其他 Store、原生 UD 调用、其他进程不参与协调。

Key 和 wrapper 是不可变的 Sendable 值，wrapper setter 为 `nonmutating`。
Store 内只有一个内部 Foundation 引用持有器使用 `@unchecked Sendable`，依据是
[Apple 对 UserDefaults 的线程安全保证](https://developer.apple.com/documentation/foundation/userdefaults)。
这个桥接不表示 wrapper 的宿主或复合业务操作自动线程安全。

Store 的读写都进入同一操作边界；同步重入只累计变化和失败，不提前交付本包的
Observation 和 `onFailure` 回调。
最外层操作释放递归锁后，才交付它累计的失败。Observation 在参与协调的访问全部退出后
交付累计变化。变化和失败都先从待交付状态中取出，再调用观察者或 `onFailure`，
因此回调再次访问 Store 不会重复交付上一批。
变更通知在释放存储锁和内部状态锁后交付，观察者可重新访问 Store。
通知可在写入线程上执行；Registrar 的线程安全不等于业务模型可以跨 actor 修改。
宏通过 Store 的共享观察对象跟踪变化，不在后台回调中修改 MainActor 模型。
原生 UD 调用不参与 Store 的原子更新协调。

AppKit 也能消费 Observable 模型。在支持跟踪的 `layout`、`draw`、`viewWillLayout` 等方法中
读取模型即可建立依赖；macOS 15 需要在 Info.plist 启用 `NSObservationTrackingEnabled`。
当前 Ravel 的 AppKit 组件由 SwiftUI 的 `NSViewRepresentable.updateNSView` 推送数据，
本次无需改用直接观察。[Apple AppKit 文档](https://developer.apple.com/documentation/appkit/updating-views-automatically-with-observation-tracking-in-appkit)

## 测试与 Preview

创建独立 suite 和 Store，可直接传给属性声明：

```swift
@UserDefault(.lastWorkspacePath, store: testStore)
var lastWorkspacePath: String?
```

如果 Store 由宿主初始化参数传入，使用 Swift 标准 backing storage 初始化：

```swift
final class WorkspaceModel {
    @UserDefault(.lastWorkspacePath) var lastWorkspacePath: String?

    init(store: UserDefaultsStore = .standard) {
        _lastWorkspacePath = UserDefault(.lastWorkspacePath, store: store)
    }
}
```

同一环境里需要协调更新的访问者共用这个 Store。初始值作为 fixture 写入，suite 的创建者负责清理。
suite 仍使用系统持久存储，不是内存后端；不通过可变全局 default Store 切换测试环境。

```swift
let suite = "WorkspaceTests.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let model = WorkspaceModel(store: UserDefaultsStore(defaults: defaults))
model.lastWorkspacePath = "/fixture"
```

验证：`swift test --package-path Packages/UserDefaultsKit -Xswiftc -warnings-as-errors`。
测试使用独立 suite，覆盖错误保留、隔离、显式并发更新、宏的编译诊断、
多个模型同步、后台 / 原生写入、重复通知过滤，以及 Store 释放后的清理。
重入回归还覆盖中途读者、写回原值、原生 / Store 重入写入，以及原生通知内读写失败的锁外交付。
