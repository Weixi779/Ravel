# Ravel artwork

- `ravel-icon-dark.png`: the approved original icon; the current macOS app icon
  sizes are derived from this image.
- `ravel-icon-light.png`: a companion with a white tile and the same teal ribbon
  knot. It uses an opaque white outer canvas for documentation and previews.

Both variants were produced with Codex's built-in image generation tool. The light
variant was edited from the approved original on 2026-09-09. It is an alternative
asset; it does not switch the app's default icon or add a theme preference.

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
