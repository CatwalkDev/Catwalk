import Cocoa
import AVFoundation

enum CatSound: String, CaseIterable {
    // Declaration order is the order shown in the right-click Sound menu.
    case off, bloop, click, purr, hiss

    var title: String {
        switch self {
        case .off:   return "Off"
        case .bloop: return "Bloop"
        case .click: return "Keyboard"
        case .purr:  return "Purr"
        case .hiss:  return "Hiss"
        }
    }
}

// Plays the chosen sound on each ignored input while locked.
// All public methods must be called on the main thread.
final class SoundManager {
    static let shared = SoundManager()

    private(set) var current: CatSound = .bloop       // default sound on first launch
    private(set) var masterVolume: Float = 0.7        // the menu slider; scales every sound

    // Bloop and the Click fallback both use the macOS system sound "Tink". The real Click
    // is the fetched keyboard taps in Sounds/click_*.wav; Tink is only used if those are missing.
    private let clickSystemSound = "Tink"
    private let bloopSystemSound = "Tink"

    private var purr: AVAudioPlayer?
    private var hiss: AVAudioPlayer?             // continuous loop while any key is held
    private var bloopPool: [AVAudioPlayer] = []  // copies of one source, free overlap
    private var clickPool: [AVAudioPlayer] = []  // varied key-tap pool, overlap plus pitch jitter
    private var bloopIdx = 0
    private var clickIdx = 0

    private var purrIdle: Timer?
    private var purrStop: Timer?
    private var hissIdle: Timer?
    private var hissStop: Timer?

    private let kVol = "CatwalkVolume"
    private let kSound = "CatwalkSound"

    // Per-sound design level. The slider multiplies on top of these so click/bloop stay
    // gentle relative to a purr or hiss.
    private func baseGain(_ s: CatSound) -> Float {
        switch s {
        case .off:   return 0
        case .bloop: return 0.5
        case .click: return 0.45
        case .purr:  return 0.55      // 0.85 minus 35%
        case .hiss:  return 0.455     // 0.65 minus 30%
        }
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: kVol) != nil { masterVolume = d.float(forKey: kVol) }
        if let raw = d.string(forKey: kSound), let s = CatSound(rawValue: raw) { current = s }
        load()
    }

    // MARK: - Loading

    private func soundsDir() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true)
    }

    // Every .wav whose name starts with `prefix`, sorted, so dropping in hiss_5.wav /
    // click_9.wav etc. expands the pool automatically.
    private func files(prefix: String) -> [URL] {
        guard let dir = soundsDir(),
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return items
            .filter { $0.pathExtension.lowercased() == "wav"
                   && $0.lastPathComponent.lowercased().hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func systemSound(_ name: String) -> URL? {
        let u = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func makePlayer(_ url: URL, loop: Bool = false, rate: Bool = false) -> AVAudioPlayer? {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.numberOfLoops = loop ? -1 : 0
        p.enableRate = rate
        p.prepareToPlay()
        return p
    }

    // N copies of the first URL, so rapid presses overlap on the same sound.
    private func makePool(_ urls: [URL], copies: Int, rate: Bool = false) -> [AVAudioPlayer] {
        guard let first = urls.first else { return [] }
        return (0..<max(1, copies)).compactMap { _ in makePlayer(first, rate: rate) }
    }

    // N copies of each distinct file (interleaved), so a press cycles through the
    // variations while still overlapping on rapid input.
    private func makeVariedPool(_ urls: [URL], copiesEach: Int, rate: Bool) -> [AVAudioPlayer] {
        var out: [AVAudioPlayer] = []
        for _ in 0..<max(1, copiesEach) {
            for u in urls { if let p = makePlayer(u, rate: rate) { out.append(p) } }
        }
        return out
    }

    private func load() {
        if let purrURL = files(prefix: "purr").first {
            purr = makePlayer(purrURL, loop: true)
            purr?.volume = 0
        }
        if let hissURL = files(prefix: "hiss").first {
            hiss = makePlayer(hissURL, loop: true)
            hiss?.volume = 0
        }

        // Click is the real keyboard taps (a varied pool); fall back to the system tick.
        let clickURLs = files(prefix: "click")
        clickPool = clickURLs.isEmpty
            ? makePool([systemSound(clickSystemSound)].compactMap { $0 }, copies: 8, rate: true)
            : makeVariedPool(clickURLs, copiesEach: 3, rate: true)
        // Bloop is the soft macOS "Tink" (or a dropped-in bloop_*.wav).
        let bloopURLs = files(prefix: "bloop").isEmpty
            ? [systemSound(bloopSystemSound)].compactMap { $0 } : files(prefix: "bloop")
        bloopPool = makePool(bloopURLs, copies: 6)
    }

    // MARK: - Selection & volume

    func set(_ s: CatSound) {
        if current == .purr && s != .purr { stopPurr(immediate: true) }
        if current == .hiss && s != .hiss { stopHiss(immediate: true) }
        current = s
        UserDefaults.standard.set(s.rawValue, forKey: kSound)
    }

    func setMasterVolume(_ v: Float) {
        masterVolume = max(0, min(1, v))
        UserDefaults.standard.set(masterVolume, forKey: kVol)
        if let purr = purr, purr.isPlaying { purr.volume = baseGain(.purr) * masterVolume }
        if let hiss = hiss, hiss.isPlaying { hiss.volume = baseGain(.hiss) * masterVolume }
    }

    // One ignored key or mouse press while locked. `isRepeat` is true for auto-repeat
    // keystrokes (a held key); Bloop/Keyboard skip those so one press is one sound.
    func input(isRepeat: Bool = false) {
        switch current {
        case .off:   break
        case .bloop: if !isRepeat { triggerOverlap(bloopPool, &bloopIdx, gain: baseGain(.bloop), vary: false) }
        case .click: if !isRepeat { triggerOverlap(clickPool, &clickIdx, gain: baseGain(.click), vary: true) }
        case .purr:  triggerPurr()   // continuous; held keys keep it alive
        case .hiss:  break           // continuous; driven by key-held state (setHissActive)
        }
    }

    // Called on unlock: let one-shots ring out, but stop the continuous loops.
    func stopAll() { stopPurr(immediate: false); stopHiss(immediate: false) }

    // MARK: - Purr (continuous loop, fade in / sustain / fade out)

    private func triggerPurr() {
        guard let purr = purr else { return }
        let target = baseGain(.purr) * masterVolume
        if !purr.isPlaying {
            purr.volume = 0
            purr.currentTime = 0
            purr.play()
            purr.setVolume(target, fadeDuration: 0.25)   // gentle fade-in
        } else {
            purr.setVolume(target, fadeDuration: 0.1)     // track live volume changes
        }
        purrStop?.invalidate(); purrStop = nil
        purrIdle?.invalidate()
        purrIdle = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.fadePurrOut()                           // 0.8s after the last key
        }
    }

    private func fadePurrOut() {
        guard let purr = purr, purr.isPlaying else { return }
        purr.setVolume(0, fadeDuration: 0.6)
        purrStop?.invalidate()
        purrStop = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            self?.purr?.stop()
        }
    }

    private func stopPurr(immediate: Bool) {
        purrIdle?.invalidate(); purrIdle = nil
        if immediate {
            purrStop?.invalidate(); purrStop = nil
            purr?.stop(); purr?.volume = 0
        } else {
            fadePurrOut()
        }
    }

    // MARK: - Hiss (continuous loop while any key is held)

    // Driven by the "is any key currently down?" state from the event tap. When the last
    // key lifts, the hiss keeps going for 0.8s before fading out (a new key cancels it).
    func setHissActive(_ active: Bool) {
        guard current == .hiss, let hiss = hiss else { return }
        if active {
            hissIdle?.invalidate(); hissIdle = nil
            hissStop?.invalidate(); hissStop = nil
            if !hiss.isPlaying { hiss.volume = 0; hiss.currentTime = 0; hiss.play() }
            hiss.setVolume(baseGain(.hiss) * masterVolume, fadeDuration: 0.12)
        } else {
            hissIdle?.invalidate()
            hissIdle = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.fadeHissOut()                       // 0.8s after the last key
            }
        }
    }

    private func fadeHissOut() {
        guard let hiss = hiss, hiss.isPlaying else { return }
        hiss.setVolume(0, fadeDuration: 0.4)
        hissStop?.invalidate()
        hissStop = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.hiss?.stop()
        }
    }

    private func stopHiss(immediate: Bool) {
        hissIdle?.invalidate(); hissIdle = nil
        if immediate {
            hissStop?.invalidate(); hissStop = nil
            hiss?.stop(); hiss?.volume = 0
        } else {
            fadeHissOut()
        }
    }

    // MARK: - One-shots

    // Bloop / Click: round-robin a copy pool so rapid presses overlap.
    private func triggerOverlap(_ pool: [AVAudioPlayer], _ idx: inout Int, gain: Float, vary: Bool) {
        guard !pool.isEmpty else { return }
        let p = pool[idx % pool.count]; idx += 1
        p.volume = gain * masterVolume
        if vary { p.rate = Float.random(in: 0.93...1.08) }   // slight pitch wobble per click
        p.currentTime = 0
        p.play()
    }
}
