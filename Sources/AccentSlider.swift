import Cocoa

/// A linear slider whose filled portion is drawn in the system accent color.
/// (NSSlider.trackFillColor is ignored inside menus on recent macOS, so we draw
/// the bar ourselves.)
final class AccentSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let radius = rect.height / 2

        // Unfilled track.
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        // Filled portion, in the accent color.
        let span = maxValue - minValue
        let frac = span > 0 ? CGFloat((doubleValue - minValue) / span) : 0
        guard frac > 0 else { return }
        var fill = rect
        fill.size.width = max(rect.height, rect.width * frac)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
