# Ravel artwork

- `ravel-icon-dark.png`: the approved original icon, used for the dark appearance.
- `ravel-icon-light.png`: a companion with a white tile and the same teal ribbon
  knot. It uses an opaque white outer canvas for documentation and previews.

Both variants were produced with Codex's built-in image generation tool. The light
variant was edited from the approved original on 2026-09-09.

## App integration

`Sources/Ravel/Resources/AppIcon.icon` is the app's Icon Composer document.
Its `Assets/Light.png` and `Assets/Dark.png` are unchanged copies of these source
images. Appearance-specific visibility selects the white artwork by default and
the original artwork in dark mode. Layer positioning fits the existing tiles to
the system mask; extra glass, translucency, and group shadows are disabled.

The running app uses `DockIconController` to observe `NSApplication.effectiveAppearance`
and explicitly redraw its Dock tile when system appearance changes. Its
`Resources/DockIconLight.png` and `DockIconDark.png` are 1024pt, 1× macOS Default
and Dark PNG exports from this Composer document, with transparent corners. The
image canvas supplies the surrounding padding; a single root image view is drawn
by the Dock without Auto Layout or child views. To regenerate them, use Icon Composer
**File → Export**, select macOS and the matching appearance, and replace these PNGs.

This runtime Dock behavior is independent of **Icon & widget style**. Finder and
the Dock while Ravel is not running still use the system-managed icon: on macOS 26
and later, select **System Settings → Appearance → Icon & widget style → Dark → Auto**
to follow system appearance. There is no Dock tile plug-in or app-level theme preference.

The target's existing `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` setting selects
the document. Xcode gives it precedence over the older `AppIcon.appiconset` and
generates a static default-appearance icon for macOS versions before 26. The old
asset catalog remains as the original artwork's size set. See Apple's
[Icon Composer integration documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Generation prompts

The light variant was generated with this edit prompt:

```text
Use case: precise-object-edit. Asset type: Ravel macOS app icon, white-background companion variant. Input image 1 is the edit target, the approved original Ravel icon. Change ONLY the dark ink rounded-square tile to a clean soft white / ivory-white tile with subtle neutral edge shading and the same gentle dimensional finish. Preserve the teal/mint ribbon knot EXACTLY: same silhouette, shape, loop, single crossing, horizontal flowing ends, position, proportions, satin material and teal gradients. Do not redesign or rotate the ribbon, do not turn it into a literal letter. Preserve the icon's square composition, rounded-corner geometry, padding, perspective and restrained shadow. The white tile should be unmistakably white, not grey; ensure the mint ribbon remains clearly readable. Transparent canvas outside the rounded-square tile and shadow, preserve alpha. No text, no letters, no labels, no watermark. Deliver a single high-resolution square icon.
```

The first edit produced a checkerboard instead of actual transparency. The final
correction used that candidate as its edit target:

```text
Use case: precise-object-edit. The input is a nearly finished white Ravel app icon. Make ONE correction only: erase all checkerboard pattern outside the white rounded-square tile and replace that entire outer canvas with perfectly plain solid white (#FFFFFF), leaving a subtle clean neutral shadow immediately beside the tile. Deliver an opaque square image on a white background. No transparency, no checkerboard, no grey pattern, no texture outside the tile. Preserve the white rounded-square tile and the mint/teal satin ribbon knot exactly as they are, including geometry, loop and single crossing, horizontal ends, proportions, size, placement, color, light and materials. No extra elements, no text, no watermark.
```
