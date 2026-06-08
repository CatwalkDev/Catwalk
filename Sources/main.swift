//  Catwalk: a menu-bar app that blocks the keyboard and trackpad while a cat is on it.
//  This file: app entry point, the status-item menu, and the event tap that swallows input.

import Cocoa
import CoreGraphics
import ApplicationServices

// ⌃⌘L is the fail-safe unlock combo. 37 == kVK_ANSI_L.
private let unlockKeycode: Int64 = 37

// Clicks and scroll in the top menu-bar strip pass through so the cat icon stays clickable
// while everything else is locked. Height is set when locking.
private var passThroughY: CGFloat = 40

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var locked = false
    private(set) var menuOpen = false        // true while the right-click menu is open
    private var heldKeys = Set<Int64>()      // keycodes currently down; drives the Hiss loop
    private var recenterTimer: Timer?

    // Use the cat glyph if this SF Symbols version has it, otherwise a pawprint.
    private lazy var idleImage   = AppDelegate.symbol(["cat", "pawprint"])
    private lazy var lockedImage = AppDelegate.symbol(["cat.fill", "pawprint.fill"])

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = idleImage
            button.image?.isTemplate = true
            button.toolTip = "Click to lock the keyboard and trackpad"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Tell the overlay where the cat icon is so its arrow can point at it.
        OverlayController.shared.iconScreen = { [weak self] in
            self?.statusItem.button?.window?.screen
        }
        OverlayController.shared.iconScreenRect = { [weak self] in
            guard let b = self?.statusItem.button, let win = b.window else { return nil }
            return win.convertToScreen(b.convert(b.bounds, to: nil))
        }
    }

    static func symbol(_ names: [String]) -> NSImage? {
        for n in names {
            if let img = NSImage(systemSymbolName: n, accessibilityDescription: "Catwalk") {
                return img
            }
        }
        return nil
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let lockItem = NSMenuItem(title: locked ? "Unlock" : "Lock now",
                                  action: #selector(toggle), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)

        menu.addItem(.separator())

        let soundsItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let soundsMenu = NSMenu()
        for s in CatSound.allCases {
            let it = NSMenuItem(title: s.title, action: #selector(pickSound(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s.rawValue
            it.state = (SoundManager.shared.current == s) ? .on : .off
            soundsMenu.addItem(it)
        }
        menu.addItem(soundsItem)
        menu.setSubmenu(soundsMenu, for: soundsItem)

        menu.addItem(.separator())
        menu.addItem(makeVolumeItem())

        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Fail-safe unlock:  ⌃⌘L", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Catwalk",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc func toggle() { locked ? unlock() : lock() }

    // An ignored mouse click or scroll while locked: flash the overlay and play the sound.
    func ignoredInput() {
        OverlayController.shared.show()
        SoundManager.shared.input()
    }

    // A key press while locked. `suppressed` (menu open) skips the overlay and discrete
    // sound; `isRepeat` flags auto-repeat so the one-shot sounds fire once per press.
    // Key-held tracking always runs so the Hiss loop stays accurate.
    func keyDown(_ code: Int64, suppressed: Bool, isRepeat: Bool) {
        heldKeys.insert(code)
        if !suppressed {
            OverlayController.shared.show()
            SoundManager.shared.input(isRepeat: isRepeat)
        }
        SoundManager.shared.setHissActive(true)
    }

    func keyUp(_ code: Int64) {
        heldKeys.remove(code)
        SoundManager.shared.setHissActive(!heldKeys.isEmpty)   // stops when the last key lifts
    }

    @objc private func pickSound(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let s = CatSound(rawValue: raw) else { return }
        SoundManager.shared.set(s)
    }

    // MARK: - NSMenuDelegate
    // While the menu is open the tap passes every click through (its items sit below the
    // menu bar and would otherwise be swallowed), and the overlay steps aside.
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        OverlayController.shared.hideNow()
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    // Volume row (custom slider view) for the right-click menu.
    private func makeVolumeItem() -> NSMenuItem {
        let item = NSMenuItem()
        let w: CGFloat = 232, h: CGFloat = 30
        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let icon = NSImageView(frame: NSRect(x: 14, y: 5, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")
        icon.contentTintColor = .secondaryLabelColor
        container.addSubview(icon)

        let slider = NSSlider(frame: NSRect(x: 42, y: 4, width: w - 42 - 16, height: 22))
        slider.cell = AccentSliderCell()
        slider.minValue = 0; slider.maxValue = 1
        slider.doubleValue = Double(SoundManager.shared.masterVolume)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(volumeChanged(_:))
        container.addSubview(slider)

        item.view = container
        return item
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        SoundManager.shared.setMasterVolume(Float(sender.doubleValue))
    }

    func lock() {
        guard !locked else { return }
        guard ensureAccessibility() else { return }

        passThroughY = NSStatusBar.system.thickness + 10

        func bit(_ t: CGEventType) -> CGEventMask { CGEventMask(1) << CGEventMask(t.rawValue) }
        // Raw event types CGEventType doesn't name: 14 = NX_SYSDEFINED (media, volume,
        // brightness, play/pause keys), and 18-20 / 29-32 = trackpad gesture events
        // (pinch, rotate, swipe, smart-zoom). Without these they slip through the lock.
        let systemAndGestures: CGEventMask = [14, 18, 19, 20, 29, 30, 31, 32]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        let mask: CGEventMask =
            bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged) |
            bit(.leftMouseDown) | bit(.leftMouseUp) |
            bit(.rightMouseDown) | bit(.rightMouseUp) |
            bit(.otherMouseDown) | bit(.otherMouseUp) |
            bit(.scrollWheel) | systemAndGestures

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: eventCallback,
                                          userInfo: ctx) else {
            warn("Couldn't create the input tap.\n\nMake sure Catwalk is enabled in System Settings → Privacy & Security → Accessibility, then try again.")
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        locked = true
        setImage(lockedImage, tip: "Locked. Click the cat or press ⌃⌘L to unlock")
        recenterTimer?.invalidate()
        recenterTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.recenterIfNearIcon()
        }
    }

    func unlock() {
        guard locked else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        locked = false
        recenterTimer?.invalidate(); recenterTimer = nil
        setImage(idleImage, tip: "Click to lock the keyboard and trackpad")
        heldKeys.removeAll()
        OverlayController.shared.hideNow()
        SoundManager.shared.stopAll()
    }

    func reEnableTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // Three seconds into a lock, if the cursor is still on or near the cat icon (where it
    // was when you clicked to lock), move it to the middle of the screen, clear of the
    // unlock target. If it has already been moved away, leave it.
    private func recenterIfNearIcon() {
        guard locked, let button = statusItem.button, let win = button.window else { return }
        let iconRect = win.convertToScreen(button.convert(button.bounds, to: nil))
        let iconCenter = NSPoint(x: iconRect.midX, y: iconRect.midY)
        let mouse = NSEvent.mouseLocation                     // screen coords, bottom-left origin
        let dx = mouse.x - iconCenter.x, dy = mouse.y - iconCenter.y
        let nearRadius: CGFloat = 80
        guard dx * dx + dy * dy <= nearRadius * nearRadius else { return }

        guard let screen = win.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // CGWarp uses a top-left-origin global space, so flip Y about the primary display.
        CGWarpMouseCursorPosition(CGPoint(x: screen.frame.midX, y: primaryH - screen.frame.midY))
    }

    private func setImage(_ img: NSImage?, tip: String) {
        statusItem.button?.image = img
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = tip
    }

    private func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        warn("Catwalk needs Accessibility permission to block input.\n\nOpen System Settings → Privacy & Security → Accessibility, turn Catwalk on, then quit and reopen it.")
        return false
    }

    private func warn(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Catwalk"
        a.informativeText = msg
        a.alertStyle = .warning
        a.runModal()
    }
}

// Runs for every keystroke, click, and scroll while locked. Returning nil swallows it.
private func eventCallback(proxy: CGEventTapProxy,
                           type: CGEventType,
                           event: CGEvent,
                           userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

    // The OS can disable a slow or contested tap; re-enable it and pass the event.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { app.reEnableTap() }
        return Unmanaged.passUnretained(event)
    }

    let menuOpen = app.menuOpen
    let raw = type.rawValue

    // Media, volume, brightness, and play/pause keys (NX_SYSDEFINED = type 14).
    if raw == 14 {
        if menuOpen { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { app.ignoredInput() }
        return nil
    }
    // Trackpad gestures (pinch, rotate, swipe, smart-zoom = types 18-20, 29-32). Block
    // silently, since they stream begin/changed/end events that would spam the overlay.
    if (raw >= 18 && raw <= 20) || (raw >= 29 && raw <= 32) {
        return menuOpen ? Unmanaged.passUnretained(event) : nil
    }

    // Keyboard: only ⌃⌘L gets through (the unlock trigger); everything else is swallowed.
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        if type == .keyDown {
            let flags = event.flags
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if flags.contains(.maskCommand), flags.contains(.maskControl), code == unlockKeycode {
                DispatchQueue.main.async { app.unlock() }
                return nil
            }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            DispatchQueue.main.async { app.keyDown(code, suppressed: menuOpen, isRepeat: isRepeat) }
        } else if type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            DispatchQueue.main.async { app.keyUp(code) }
        }
        return nil
    }

    // While the menu is open, let every click reach it.
    if menuOpen {
        return Unmanaged.passUnretained(event)
    }

    // Otherwise pass only the menu-bar strip (so the cat icon stays clickable).
    if event.location.y <= passThroughY {
        return Unmanaged.passUnretained(event)
    }
    let isPress = (type == .leftMouseDown || type == .rightMouseDown
                   || type == .otherMouseDown || type == .scrollWheel)
    if isPress { DispatchQueue.main.async { app.ignoredInput() } }
    return nil
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
