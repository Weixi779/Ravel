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
- Jujutsu (`jj`) 0.41 or later; the first implementation is verified with 0.41.0

Open `Ravel.xcodeproj`, select the **Ravel** scheme, and run. Swift Package Manager
resolves Swift Subprocess 1.0.0. The app uses local ad-hoc signing and does not
require a development team for local use.

Choose **File → Open Repository…** (`⌘O`) and select an existing jj workspace.
Refresh with `⌘R`, or return to the app after working in the terminal. `⌘0` selects
the working-copy revision. The Ravel menu includes **Choose jj Executable…** for
installations outside the usual Homebrew/PATH locations.

An explicit workspace can also be provided when launching the built app:

```sh
open /path/to/Ravel.app --args --repository /path/to/workspace
```

## Current implementation

- SwiftUI owns the window, sidebar, toolbar, and details.
- AppKit owns the table, selection, and graph rendering.
- The Changes inspector lists added, modified, removed, copied, and renamed files.
  File contents load on selection, with separate old/new line-number gutters,
  addition/deletion colors, and native text selection and copying. Gutters are
  excluded from copied text. Details remains available beside Changes.
- Pure Swift assigns graph lanes from jj's topological output.
- Swift Subprocess executes jj directly with argument arrays; no login shell.
- A custom JSONL template provides explicit fields, decoded into `Sendable` values.
- Window state is `@MainActor` and observable. `@concurrent` keeps process work,
  decoding, and graph layout off the main actor. Replaced requests are cancelled
  and cannot publish stale results.

Swift 6 language mode, complete concurrency checking, MainActor default isolation,
and approachable concurrency are enabled in `Config/Concurrency.xcconfig`.
`nonisolated` value types explicitly cross the UI boundary. UI and session models
retain checked actor isolation. UserDefaultsKit contains one internal, immutable
`@unchecked Sendable` bridge for Foundation's documented thread-safe UserDefaults;
its Store and accessors otherwise use checked Sendable conformances.

The log follows the workspace's `revsets.log` selection and keeps jj's ordering.
It displays up to 300 revisions and marks parents outside the loaded set with
dotted, capped edges. It does not imply that a hidden parent is a direct edge to
another visible revision. Commit IDs identify rows; Change IDs are retained
separately, including divergent changes.

Reads use `--ignore-working-copy --at-op=@`: opening or refreshing does not
snapshot files, update the working copy, or merge concurrent operations. Changes
made only in an editor become visible after jj records them. Concurrent operation
heads are reported as an error for the user to handle in jj.

Diffs use the selected full commit ID and jj's `diff --revisions` semantics,
including comparison against the automatic merge of all parents for a merge
revision. The file list is decoded from explicit JSON fields; file previews use
an escaped exact path fileset and the built-in Git diff format. Both revision and
file requests are cancelled on replacement, with generation checks preventing
obsolete results from appearing. Binary files and empty revisions have explicit
states; mode-only changes remain visible. Each file preview is limited to 2 MB
or 20,000 lines, with an error instead of a partial patch.

Refreshing an unchanged commit keeps the loaded file and reading position.

The first version requires a locally installed jj and uses a non-sandboxed macOS
target to access repositories and the executable. There is no Rust backend or FFI
layer in the current implementation.

### Code map

| Entry | Responsibility |
| --- | --- |
| `Sources/Ravel/RavelApp.swift` | Window lifetime, commands, repository and executable panels |
| `Sources/Ravel/Log/LogSession.swift` | Repository loading, selected revision, recents and refresh state |
| `Sources/Ravel/UserDefaultsKeys.swift` | Shared declarations of typed business keys and defaults |
| `Sources/Ravel/Log/JJClient.swift` | Process execution, executable discovery and structured log decoding |
| `Sources/Ravel/Log/LogGraph.swift` | Lane assignment and edges for the loaded revision set |
| `Sources/Ravel/Diff/` | Changed-file queries, patch parsing and cancellable diff state |
| `Sources/Ravel/UI/` | SwiftUI composition, AppKit history table, graph and text diff rendering |
| `Packages/Logger/` | Native system loggers with a shared subsystem convention |
| `Packages/UserDefaultsKit/` | Typed storage, plain property wrapper and optional Observation macro |
| `Tests/RavelTests/` | Swift Testing unit and temporary-repository integration tests |

These are the current ownership boundaries, not a final architecture proposal.

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

- Revisit state ownership, the CLI boundary, and rendering responsibilities using
  the existing history and diff flows as concrete consumers.
- Load more than the first 300 revisions; add search and filtering.
- Detect repository changes while the window stays active.
- Improve diff navigation, large-file handling and side-by-side presentation.
- Design repository mutations and conflict workflows before adding write actions.
- Decide on jj distribution, app sandboxing, signing, notarization and updates.

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

```sh
xcodebuild -project Ravel.xcodeproj -scheme Ravel \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData test
```

Swift Testing covers graph continuity, merges, hidden ancestry, divergent changes,
JSON escaping, version checks, stale requests, failed refreshes, diff hunk line
numbers, CRLF, missing final newlines, and preview limits. CLI integration tests
use isolated temporary repositories and run when `/opt/homebrew/bin/jj` is
available. They cover rename and mode changes, binary files, special filenames,
and merge semantics, and verify that reading leaves both the working directory
and operation history unchanged.

The Dock icon regression test changes only the test host's appearance. It checks
light/dark updates, resizing while detached from a window, nontransparent rendered
pixels, and observer cleanup. These checks run on macOS 27; desktop Dock rendering
still needs visual verification after changes to this integration.

The initial history-and-diff milestone passed 29 test executions and Debug/Release
builds on macOS 26.5.1, Xcode 26.6 and Swift 6.3.3 with jj 0.41.0. The code targets
Swift 6.2 concurrency semantics; a Swift 6.2 compiler has not been tested separately.
