# Localization

All copy lives in [Localizable.xcstrings](Sources/Localization/Resources/Localizable.xcstrings).

## Add

1. In Xcode, add a key such as `repositoryOpen`, its English text, translations,
   and a short comment explaining its use. Configure variables or plurals in the catalog when needed.
2. From the repository root, run `Tools/updateLocalization`.
3. Use the generated `I18n` member. Include both the catalog and `I18n.generated.swift` in your change.

To edit existing wording, keep the key, update the catalog, and run the same command.
Do not edit `I18n.generated.swift` by hand.

## Remove

1. Remove the key's `I18n` usages from the app.
2. Delete the key from the catalog and run `Tools/updateLocalization`.
3. Build the app to catch any remaining references.

## Use

```swift
import Localization

// SwiftUI
Text(I18n.repositoryOpen)
Text(I18n.historyChangeCount(count))

// AppKit or other String-taking APIs
let title = String(localized: I18n.repositoryOpen)
```

Type `I18n.` to browse available copy with code completion.
