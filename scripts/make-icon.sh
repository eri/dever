#!/bin/zsh
# Renders docs/brand/app-icon.svg into assets/AppIcon.icns (every size macOS asks for).
set -euo pipefail
cd "$(dirname "$0")/.."
SET=build/AppIcon.iconset
rm -rf "$SET"; mkdir -p "$SET" assets
swift - <<'SWIFT'
import AppKit
let svg = URL(fileURLWithPath: "docs/brand/app-icon.svg")
guard let image = NSImage(contentsOf: svg) else { fatalError("cannot read app-icon.svg") }
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                              ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "build/AppIcon.iconset/icon_\(name).png"))
}
SWIFT
iconutil -c icns "$SET" -o assets/AppIcon.icns
echo "→ assets/AppIcon.icns"
