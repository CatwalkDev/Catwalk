import Cocoa

// Click-through overlay shown while locked. Dims every monitor with a dark scrim and the
// "Input ignored!" cat message. The monitor with the menu-bar cat also gets a spotlight cut
// around the icon plus the arrow and "Click here to disable". Fades out 5s after the last
// ignored input.
final class OverlayController {
    static let shared = OverlayController()

    private var overlays: [(window: NSWindow, view: OverlayView)] = []
    private var builtSignature = ""
    private var dismiss: Timer?

    /// Supplied by the app: which screen the cat icon is on, and the icon's frame in
    /// screen coordinates (used for the spotlight cutout and the arrow).
    var iconScreen: (() -> NSScreen?)?
    var iconScreenRect: (() -> NSRect?)?

    func show() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        rebuildIfNeeded(for: screens)

        let iconFrame = iconScreen?()?.frame
        let iconRect = iconScreenRect?()

        for (i, screen) in screens.enumerated() where i < overlays.count {
            let (window, view) = overlays[i]
            window.setFrame(screen.frame, display: false)
            view.frame = NSRect(origin: .zero, size: screen.frame.size)

            // Only the cat-icon monitor gets the spotlight + arrow; the rest just dim.
            if let f = iconFrame, f == screen.frame, let r = iconRect {
                let local = NSRect(x: r.minX - screen.frame.minX, y: r.minY - screen.frame.minY,
                                   width: r.width, height: r.height)
                view.iconRectLocal = local
                view.arrowTarget = NSPoint(x: local.midX, y: local.minY)   // bottom-center of the icon
            } else {
                view.iconRectLocal = nil
                view.arrowTarget = nil
            }
            view.updateScale(window.backingScaleFactor)
            view.layoutContents()

            if !window.isVisible {
                window.alphaValue = 0
                window.orderFrontRegardless()
            }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            for (window, _) in overlays { window.animator().alphaValue = 1 }   // cancels any fade-out
        }

        dismiss?.invalidate()
        dismiss = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    func hideNow() {
        dismiss?.invalidate(); dismiss = nil
        for (window, _) in overlays { window.orderOut(nil) }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            for (window, _) in overlays { window.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            for (window, _) in self.overlays where window.alphaValue < 0.02 { window.orderOut(nil) }
        })
    }

    /// One window per screen; only rebuilt when the display layout actually changes.
    private func rebuildIfNeeded(for screens: [NSScreen]) {
        let sig = screens.map { NSStringFromRect($0.frame) }.joined(separator: "|")
        if sig == builtSignature && overlays.count == screens.count { return }
        for (window, _) in overlays { window.orderOut(nil) }
        overlays = screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.ignoresMouseEvents = true          // never eats clicks; the cat icon stays reachable
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let v = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.contentView = v
            return (w, v)
        }
        builtSignature = sig
    }
}

private final class OverlayView: NSView {
    var arrowTarget: NSPoint? { didSet { layoutArrow() } }
    var iconRectLocal: NSRect?                 // icon frame in window coords; cut out of the scrim

    private let scrim = CAShapeLayer()         // dark everywhere except the spotlight hole
    private let spot  = CAShapeLayer()         // soft glow ring around the hole
    private let face  = CATextLayer()
    private let title = CATextLayer()
    private let sub   = CATextLayer()
    private let arrow = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(scrim)
        layer?.addSublayer(spot)
        layer?.addSublayer(face)
        layer?.addSublayer(title)
        layer?.addSublayer(sub)
        layer?.addSublayer(arrow)
        styleContents()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: d, size: size) ?? base
        }
        return base
    }

    private func attr(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        return NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: p
        ])
    }

    private func styleContents() {
        scrim.fillColor = NSColor(white: 0, alpha: 0.62).cgColor   // dim the whole screen
        scrim.fillRule = .evenOdd                                  // except the cut-out hole

        spot.fillColor = NSColor.clear.cgColor
        spot.strokeColor = NSColor(white: 1, alpha: 0.30).cgColor
        spot.lineWidth = 1.5
        spot.shadowColor = NSColor.white.cgColor
        spot.shadowOpacity = 0.5
        spot.shadowRadius = 7
        spot.shadowOffset = .zero

        for t in [face, title, sub] {
            t.alignmentMode = .center
            t.truncationMode = .none
            t.isWrapped = true
            t.shadowColor = .black
            t.shadowOpacity = 0.5
            t.shadowRadius = 8
            t.shadowOffset = CGSize(width: 0, height: -2)
        }
        face.string  = attr("🐱", NSFont.systemFont(ofSize: 128), .white)
        title.string = attr("Input ignored!", rounded(54, .bold), .white)
        sub.string   = attr("Click here to disable", rounded(20, .semibold),
                            NSColor(white: 1, alpha: 0.92))

        arrow.strokeColor = NSColor.white.cgColor
        arrow.fillColor = NSColor.white.cgColor
        arrow.lineWidth = 5
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.shadowColor = .black
        arrow.shadowOpacity = 0.5
        arrow.shadowRadius = 6
        arrow.shadowOffset = CGSize(width: 0, height: -2)
    }

    func updateScale(_ s: CGFloat) {
        for t in [face, title, sub] { t.contentsScale = s }
        arrow.contentsScale = s
    }

    func layoutContents() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let b = bounds
        scrim.frame = b
        spot.frame = b

        // Scrim = full screen, minus a circular spotlight around the icon.
        let path = CGMutablePath()
        path.addRect(b)
        if let r = iconRectLocal {
            let radius = (hypot(r.width, r.height) / 2 + 8) * 0.75   // ~25% smaller spotlight
            let c = CGPoint(x: r.midX, y: r.midY)
            let circle = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
            let holePath = CGPath(ellipseIn: circle, transform: nil)
            path.addPath(holePath)
            spot.path = holePath
            spot.isHidden = false
        } else {
            spot.path = nil
            spot.isHidden = true
        }
        scrim.path = path

        let midY = b.height * 0.5                         // centered
        face.frame  = CGRect(x: 0, y: midY + 4,   width: b.width, height: 160)
        title.frame = CGRect(x: 0, y: midY - 62,  width: b.width, height: 72)
        CATransaction.commit()
        layoutArrow()                                     // also places "Click here" under the arrow
    }

    private func layoutArrow() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        guard let tip = arrowTarget else {
            arrow.isHidden = true; sub.isHidden = true
            CATransaction.commit(); return
        }
        arrow.isHidden = false
        sub.isHidden = false
        arrow.frame = bounds

        // Shaft rises toward the icon; chevron head points up at it.
        let topY = tip.y - 26                 // a bit lower, clear of the spotlight circle
        let botY = tip.y - 80
        let x = tip.x
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: botY))
        path.addLine(to: CGPoint(x: x, y: topY))
        path.move(to: CGPoint(x: x - 9, y: topY - 11))
        path.addLine(to: CGPoint(x: x, y: topY))
        path.addLine(to: CGPoint(x: x + 9, y: topY - 11))
        arrow.path = path

        // "Click here to disable" sits directly under the arrow.
        let lw: CGFloat = 240, lh: CGFloat = 28
        let lx = max(12, min(bounds.width - lw - 12, x - lw / 2))
        sub.frame = CGRect(x: lx, y: botY - lh - 8, width: lw, height: lh)

        CATransaction.commit()

        // Gentle bob so the eye is drawn to the icon.
        if arrow.animation(forKey: "bob") == nil {
            let bob = CABasicAnimation(keyPath: "transform.translation.y")
            bob.fromValue = 0; bob.toValue = 5
            bob.duration = 0.55
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            arrow.add(bob, forKey: "bob")
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let s = window?.backingScaleFactor { updateScale(s) }
    }
}
