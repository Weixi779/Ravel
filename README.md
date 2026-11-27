# Ravel

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Artwork/ravel-icon-dark.png">
  <img src="Artwork/ravel-icon-light.png" alt="Ravel ribbon knot icon" width="144">
</picture>

A native Jujutsu client for Mac.

Ravel is an early, read-only prototype with a Fork-inspired history layout.
The current milestone is browsing a workspace's graph and understanding each
revision's changes. The architecture is still evolving; there is no tagged release
or packaged installer yet.

Ravel opens an existing jj workspace and shows its revision graph, descriptions,
bookmarks, authors, and timestamps in a native table. Select a revision to see its
changed files and a unified diff, or switch to Details for its full description
and identity. The last successfully opened workspace is restored at launch.

## Build and run

- macOS 15 or later
- Xcode 26 or later with Swift 6.2 or later
- Rust 1.96.0 through rustup (pinned in `Backend/rust-toolchain.toml`)
- Jujutsu (`jj`) 0.41 or later only for creating integration-test fixtures

Open `Ravel.xcodeproj`, select the **Ravel** scheme, and run.
The build phase runs `Tools/buildBackend` and
statically links jj-lib 0.41.0 through UniFFI. The first build downloads Cargo
dependencies. For a universal Release build, install both Rust targets:
`rustup target add --toolchain 1.96.0 aarch64-apple-darwin x86_64-apple-darwin`.
The app uses local ad-hoc signing and does not require a development team.

Choose **File → Open Repository…** (`⌘O`) and select an existing jj workspace.
Refresh with `⌘R`, or return to the app after working in the terminal. `⌘0` selects
the working-copy revision. Browsing history and diffs does not require an
installed jj executable.

An explicit workspace can also be provided when launching the built app:

```sh
open /path/to/Ravel.app --args --repository /path/to/workspace
```

## Current implementation

- SwiftUI owns the window, sidebar, toolbar, and details.
- AppKit owns the table, selection, and graph rendering.
- The Changes inspector offers a folder tree, folder groups, and a filename-first
  list with a secondary path, filtering, and status icon badges. Native file
  type icons also work for historical paths. Added/deleted/modified/moved use
  green/red/blue/purple; conflicts have an independent warning indicator.
  Per-file and total line statistics load independently of file previews. File
  information shows before/after types, executable modes and conflict sides.
  Read-only STTextView readers offer unified or aligned side-by-side text,
  synchronized vertical scrolling, line-number gutters, change backgrounds,
  basic intraline emphasis, conservative comment coloring, and native find.
  Header copy buttons copy the repository-relative path or filename; the context
  menu also provides the absolute path.
  Optional +/− markers stay outside copied code and do not move the code column.
  This preference is independent of appearance and initially follows macOS
  Differentiate Without Color. Details remains available beside Changes.
- Rust owns a fixed-operation history view and demand-driven revset traversal.
  `CodeRepositoryReader` and `HistoryQuery` expose application values to Swift.
- Pure Swift incrementally assigns graph lanes, retaining parents across pages.
- The Rust reader enumerates changed files and renders Git patches in process,
  using the selected history operation and full commit ID.
- Window state is `@MainActor` and observable. Swift awaits async UniFFI calls;
  native workers own blocking jj operations at user-initiated QoS. Cancellation
  tokens and generation checks prevent replaced requests from publishing stale
  pages, and explicit close awaits native resource cleanup.

Swift 6 language mode, complete concurrency checking, MainActor default isolation,
and approachable concurrency are enabled in `Config/Concurrency.xcconfig`.
`nonisolated` value types explicitly cross the UI boundary. UI and session models
retain checked actor isolation. UserDefaultsKit contains one internal, immutable
`@unchecked Sendable` bridge for Foundation's documented thread-safe UserDefaults;
its Store and accessors otherwise use checked Sendable conformances.

History loads all visible commits and their ancestors, down to the root commit,
in jj's topological order. It ignores `revsets.log` and excludes abandoned or
superseded hidden versions. Settings offers batches of 100, 200, 500, 1,000 or
5,000 revisions, with 1,000 as the default; changes apply on the next refresh or
repository open. Scrolling near the loaded end requests the next page.
Loading more preserves selection and existing graph
rows. Page failures keep the cursor for explicit Retry. Refresh replaces the view
only after successfully reading the previously loaded depth.

The history graph and description share one column. Each title follows the lanes
occupied in its own row, so a distant fork does not indent the whole list.
When a path ends or joins another, continuing paths close the vacant lanes below
that row. Their relative order and colors stay intact, and loading another page
does not redraw earlier rows.
Selecting a revision emphasizes its visual path and the titles on that path;
other paths retain subdued versions of their colors. Focus uses allocated path
identities, not a full branch or ancestor traversal, and does not reorder history.
Settings offers rounded connections (the default) and smooth curves. History
colors have separate light, dark and increased-contrast values; a user theme
editor is not implemented yet.

Read access does not snapshot files, import Git refs, update the working copy, or
merge concurrent operations. Editor changes appear after jj records them.
Concurrent operation heads are reported for the user to handle in jj. Every
history query pins one operation, so external repository changes cannot mix pages
from different views.

Diffs use the selected full commit ID and jj's `diff --revisions` semantics,
including comparison against the automatic merge of all parents for a merge
revision. The file list crosses the native bridge as typed records; file previews
use an exact repository-path matcher and the built-in Git diff format. Both revision and
file requests are cancelled on replacement, with generation checks preventing
obsolete results from appearing. Binary files and empty revisions have explicit
states; mode-only changes remain visible. Each file preview is limited to 2 MB
or 20,000 lines, with an error instead of a partial patch.

Refreshing an unchanged commit keeps the loaded file and reading position.
Revision and file switching retain the displayed snapshot until a replacement is
ready, keeping its title and contents together. Progress indicators appear only
after 250 ms. Window-scoped preview caches use immutable commit/operation/path
identities, a 24-revision metadata limit and a 64 MiB estimated display-cost
budget. One adjacent file may be prefetched after visible work settles; changing
the selection cancels that work. Repository changes clear these caches.

The text reader does not soft-wrap. Split views align replacement blocks with
blank rows and retain native horizontal scrolling independently on each side.
Multi-hunk selections retain visible gap headings, so copied fragments are not
presented as a contiguous complete source file. Expanding omitted source context
and full language-aware syntax highlighting are not implemented yet. Conflicts
inherited unchanged from merged parents remain listed, with an explicit message
when there is no additional text delta.
STTextView is pinned to 2.4.1 and is available under
[GPLv3 or a commercial license](https://github.com/krzyzanowskim/STTextView#license).

History and Diff use the bundled Rust backend. Diff requests carry the history
operation ID as well as the full commit ID. The macOS target remains non-sandboxed
to access repositories.

The accepted reader/writer ownership, write preprocessing and cancellation
contract and integration details are documented in
[Repository architecture](Documentation/RepositoryArchitecture.md). No write
commands or write UI are implemented in this slice.

### Code map

| Entry | Responsibility |
| --- | --- |
| `Sources/Ravel/App/` | Application lifetime, Dock appearance, feature composition and commands |
| `Sources/Ravel/Domains/History/Presentation/` | Repository browser, native history table, history session and derived graph state |
| `Sources/Ravel/Domains/History/Infrastructure/` | Persisted history and recent-workspace preference keys |
| `Sources/Ravel/Domains/Revision/Presentation/` | Revision inspector, details, file navigation, native diff reader and diff view models |
| `Sources/Ravel/Domains/Revision/Infrastructure/` | Persisted diff-reading preference keys |
| `Sources/Ravel/Domains/Settings/Presentation/` | Settings interface bound to the existing state owners |
| `Sources/Ravel/Domains/Repository/Domain/` | Shared revision, changed-file and file-diff values |
| `Sources/Ravel/Domains/Repository/Application/` | Workspace lifetime and diff requests |
| `Sources/Ravel/Domains/Repository/Infrastructure/` | Native repository reader and query adapter |
| `Sources/Ravel/Shared/Presentation/` | Revision summary presentation used by multiple domains |
| `Backend/` | Pinned jj-lib, read-only operation views and streaming history queries |
| `Packages/RavelBackend/` | Generated UniFFI Swift declarations and C module |
| `Packages/Logger/` | Native system loggers with a shared subsystem convention |
| `Packages/UserDefaultsKit/` | Typed storage, plain property wrapper and optional Observation macro |
| `Tests/RavelTests/` | App and domain tests grouped by tested responsibility, with common fixtures in `Support/` |

Business domains are the outer grouping. Within each domain, folders use
`Domain`, `Application`, `Presentation` and `Infrastructure` according to the
responsibilities that exist today. `Presentation` keeps `View` and `ViewModel`
together; the latter includes existing session owners and derived display values.
Localized presentation extensions sit directly in `Presentation`. A `Component`
folder is added only when local interface components need separate organization.
Settings has no separate state owner, so it has no empty ViewModel or other layers.

This change organizes files without renaming existing types or changing state
ownership. The app remains one target, and folders do not enforce dependency
inversion: the workspace still uses the concrete native reader, whose current
file also declares its read/query contracts. Extracting modules or splitting these
files is a separate change that will require explicit interfaces.

Diagnostics use the local [Logger package](Packages/Logger/). Repository refreshes
and jj invocations record events and diagnostic fields under the `com.weixi.Ravel`
subsystem. Each package can create its own logger without application setup.

## Localization

Product copy is maintained in a single catalog in the local [Localization package](Packages/Localization/).
It supports nine languages and exposes `I18n` accessors generated by Apple’s string
catalog tool. After editing the catalog, run `Tools/updateLocalization`; new copy
does not require hand-written accessors or changes to the generator.

## Development workflow

This checkout uses jj colocated with Git. After cloning elsewhere, initialize the
local metadata once:

```sh
jj git init --colocate
jj bookmark track main --remote origin
```

Configure your own jj author identity if needed. For a small, coherent change, use
`jj describe -m "type(scope): describe the change"` to name it, then `jj new` to
start the next change. Use `jj split` to separate mixed work before publishing.
Fetch and inspect the graph before moving or pushing the intended bookmark.

CI uses SwiftFormat 0.61.0 and SwiftLint 0.65.1. Use the repository scripts to
apply the same rules locally.

```sh
brew install swiftformat swiftlint
Tools/format --lint # Check formatting without changing files
Tools/format        # Apply formatting
Tools/lint          # Run the configured SwiftLint rules in strict mode
```

Both scripts cover the handwritten Swift files in `Sources`, `Tests`, `Packages`,
and `Tools`. Multiline parameter and argument lists put one parameter or argument
on each line, with a trailing comma and the closing parenthesis on its own line.

CodeGraph is optional development tooling, not an app dependency. With its CLI
installed, create a local index from the repository root:

```sh
codegraph init -i
```

CodeGraph-enabled tools can then query this repository by its local project path.
The index is disposable and may lag edits; the compiler and tests verify behavior.
`.jj/`, `.codegraph/`, build outputs, test result bundles, and Xcode user state are
ignored. The Xcode project, shared scheme, and `Package.resolved` are tracked.

## What remains

The next milestones are open for discussion, rather than a fixed delivery plan:

- Add history search and filtering without confusing filtered edges with unloaded parents.
- Detect repository changes while the window stays active.
- Improve diff navigation, large-file handling and side-by-side presentation.
- Implement the first writer against the documented preparation, serialization and outcome contract.
- Decide on app sandboxing, signing, notarization and updates.

## Artwork

The approved dark icon and its white-background companion live in [Artwork](Artwork/).
While Ravel is running, its Dock icon follows **System Settings → Appearance**
directly: light appearance uses the white tile, dark appearance uses the dark tile.
No separate icon-style setting is needed for the running app's Dock icon.

[AppIcon.icon](Sources/Ravel/Resources/AppIcon.icon) supplies the system-managed
icon in Finder and when Ravel is not running. On macOS 26 and later, those surfaces
follow **Icon & widget style**, which is separate from window appearance. Earlier
macOS versions use the static compatibility icon generated by Xcode.
The README follows the reader's color scheme.
The light variant keeps the teal ribbon knot and changes the tile to white;
generation and integration details are recorded in [Artwork/README.md](Artwork/README.md).

## Verify

[GitHub Actions](.github/workflows/ci.yml) runs the style checks, package tests,
Rust backend tests and the Ravel macOS test plan for pull requests and pushes to
`main`. The plan includes Localization. The generator tests also check translation
coverage and compare the generated Swift accessors with the checked-in file.

```sh
swift test --package-path Packages/DesignSystem
swift test --package-path Packages/UserDefaultsKit --force-resolved-versions
swift test --package-path Tools/LocalizationGenerator
Tools/testBackend
xcodebuild -project Ravel.xcodeproj -scheme Ravel \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData test
```

Swift Testing covers graph continuity, merges, pending ancestry, divergent changes,
stale pages, retry cursors, failed refreshes, diff hunk line
numbers, CRLF, missing final newlines, and preview limits. Native integration tests
use isolated temporary repositories and run when `/opt/homebrew/bin/jj` is
available. They cover rename and mode changes, binary files, special filenames,
and merge semantics, and verify that reading leaves both the working directory
and operation history unchanged.

Rust integration tests traverse more than 450 commits through root, verify fixed
views across external operations, replay after cancellation, read-only state,
concurrent-operation errors and close behavior. Native unit tests also verify that
repository close cancels active reads and waits for cleanup, and that patch output
enforces preview limits and cancellation. `Tools/testBackend` isolates jj
configuration; set `RAVEL_TEST_JJ` to override the fixture executable. Swift tests
also compare the real Rust bridge output against CLI metadata.

The shared Ravel test plan enables Xcode's Thread Performance Checker. Bridge
tests cover page sizes 1/1,000/5,000, user-initiated reads, cancellation recovery
and concurrent close. Rust tests use controlled completion signals to verify that
waiting futures yield, cancelled results are discarded, and every close caller
waits for native resource release even after the read future is dropped. On Apple
platforms they also check the worker's actual QoS. These tests establish lifecycle
guarantees; exercise a representative large repository in the app as well when
checking runtime warnings or responsiveness.

After changing the native interface, run `Tools/generateBackendBindings` and
include its generated Swift/header/module-map changes. Both native and Swift
callers must be built from the same interface version.

The Dock icon regression test changes only the test host's appearance. It checks
light/dark updates, resizing while detached from a window, nontransparent rendered
pixels, and observer cleanup. These checks run on macOS 27; desktop Dock rendering
still needs visual verification after changes to this integration.

The initial history-and-diff milestone passed 29 test executions and Debug/Release
builds on macOS 26.5.1, Xcode 26.6 and Swift 6.3.3 with jj 0.41.0. The code targets
Swift 6.2 concurrency semantics; a Swift 6.2 compiler has not been tested separately.
