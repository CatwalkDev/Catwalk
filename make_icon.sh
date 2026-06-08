#!/bin/zsh
# Generates Catwalk.icns — a white cat on a warm rounded square. Renders a 1024px
# master with AppKit, then builds the .iconset and runs iconutil. The committed
# Catwalk.icns is the output; re-run this only to change the artwork.
# (Needs a macOS whose SF Symbols set includes "cat.fill".)
set -e
ROOT="${0:A:h}"
TMP=$(mktemp -d)

cat > "$TMP/icon.swift" <<'SWIFTEOF'
import AppKit

func bitmap(_ w: Int, _ h: Int) -> (NSBitmapImageRep, NSGraphicsContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return (rep, NSGraphicsContext(bitmapImageRep: rep)!)
}

// A white "cat.fill" glyph on its own transparent layer.
func whiteCat(_ side: CGFloat) -> NSImage? {
    let conf = NSImage.SymbolConfiguration(pointSize: 600, weight: .regular)
    guard let sym = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(conf) else { return nil }
    sym.isTemplate = true
    let h = Int(side * sym.size.height / max(1, sym.size.width))
    let (rep, g) = bitmap(Int(side), h)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
    let rect = NSRect(x: 0, y: 0, width: Int(side), height: h)
    sym.draw(in: rect)
    NSColor.white.set(); rect.fill(using: .sourceAtop)   // recolor the glyph white
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: rect.size); img.addRepresentation(rep); return img
}

let px = 1024
let (rep, g) = bitmap(px, px)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
let S = CGFloat(px), margin: CGFloat = 96
let r = NSRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
let path = NSBezierPath(roundedRect: r, xRadius: r.width * 0.2237, yRadius: r.width * 0.2237)
NSGradient(starting: NSColor(srgbRed: 1.00, green: 0.78, blue: 0.34, alpha: 1),
           ending:   NSColor(srgbRed: 1.00, green: 0.49, blue: 0.13, alpha: 1))!
    .draw(in: path, angle: -90)                          // light top → warm bottom
if let cat = whiteCat(560) {
    let s = cat.size
    cat.draw(in: NSRect(x: (S - s.width) / 2, y: (S - s.height) / 2 + 6, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("rendered", out)
SWIFTEOF

swift "$TMP/icon.swift" "$TMP/icon_1024.png"

ICONSET="$TMP/Catwalk.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s          "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Catwalk.icns"
rm -rf "$TMP"
echo "✅ wrote $ROOT/Catwalk.icns"
