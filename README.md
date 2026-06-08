# 🐱 Catwalk

**Lock your Mac's keyboard and trackpad so your cat can walk across it — no consequences.**

Catwalk lives in your menu bar as a little cat. Click it, and every keystroke, click, and
scroll is ignored until you click it again. Your screen stays exactly where you left it —
the video keeps playing, your work stays put — so it's perfect for the moment a cat decides
your keyboard is the comfiest spot in the house.

<!-- Add a screenshot here: docs/screenshot.png -->

## Features

- **One-click lock** from the menu bar — the cat fills in solid while it's active.
- **Nothing gets through** — keyboard, clicks, and scrolling are all blocked.
- **Your screen stays live** — when the cat touches something, the screen dims with a
  spotlight on the menu-bar cat and a friendly *“Input ignored!”*, so you always know
  what's going on.
- **Easy to unlock** — click the cat, or press **⌃⌘L** (handy when a paw is on the trackpad).
- **Optional sounds** — play a **Purr**, **Hiss**, **Bloop**, or **Keyboard** sound while
  the cat is on the keys, with a volume slider. Right-click the cat to choose.

## Install

### Download
Grab the latest **`Catwalk.app.zip`** from the [Releases page](../../releases), unzip it,
and drag **Catwalk** to your Applications folder. (macOS 13+, Apple Silicon or Intel.)

> On first launch macOS may say it's from an unidentified developer. Right-click the app →
> **Open** → **Open**. (Catwalk is open source and not notarized.)

### Build from source
Requires the Xcode command-line tools.

```bash
git clone https://github.com/CatwalkDev/catwalk.git
cd catwalk
./build.sh
open Catwalk.app
```

## Using it

1. Click the **cat in your menu bar**.
2. The first time, macOS asks for **Accessibility** permission — turn Catwalk on in
   **System Settings → Privacy & Security → Accessibility**.
3. Click the cat to **lock**. Walk away. Let the cat be a cat.
4. **Unlock** by clicking the cat again, or pressing **⌃⌘L**.

Right-click the cat for **sound** options and a **volume** slider.

## Why does it need Accessibility permission?

Blocking the keyboard and trackpad requires a system-level input tap, and macOS keeps that
behind the Accessibility permission. Catwalk uses it for one thing only: ignoring input
while locked. Nothing is recorded, sent, or stored — and the whole source is right here for
you to read.

## Credits

Bundled sounds come from Wikimedia Commons and procedural synthesis — see
[`Sounds/CREDITS.txt`](Sounds/CREDITS.txt). The keyboard-tap sound is © its author under
CC BY 4.0.

## License

Code is released under the [MIT License](LICENSE). Bundled audio keeps its own licenses
(see credits above).

---

Made with 🐾 for cats and the people who love them.
