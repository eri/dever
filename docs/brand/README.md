# Dever brand

The mark is a D with a calm eye: a 64-unit panel whose right side is fully round
(radii 10 / 28 / 28 / 10) with an 8-unit hole at (43, 23). One flat colour, no stroke.

| File | Use |
|---|---|
| `dever-mark.svg` | Master, lime `#DAFA9C` on soot |
| `dever-mark-lime.svg` | Lime on dark grounds |
| `dever-mark-green.svg` | Green `#3F6212` on light grounds (the light-mode action colour) |
| `dever-mark-mono-dark.svg` / `dever-mark-mono-light.svg` | Ink versions when lime is not wanted |
| `dever-mark-on-lime.svg` | Soot mark on the lime tile |
| `app-icon.svg` | The app icon, 1024, on Apple's icon grid |

In the app the mark is `DeverMark` (SwiftUI, `Views/ContentView.swift`), drawn from the same
geometry and coloured `Soot.lime` so it follows light and dark. The app icon is built by
`scripts/make-icon.sh` into `assets/AppIcon.icns`, which `scripts/build-app.sh` copies into the bundle.

Explorations and the UI library live in Figma: https://www.figma.com/design/In5Oqed5fw4Wq4F6EjPBjU
