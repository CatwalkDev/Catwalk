# 🐱 Catwalk

**Lock your Mac's keyboard so that your cat can walk across it without any consequences.**

Catwalk lives in your menu bar as a little cat icon. Click it, and every keystroke, click, and
scroll is ignored until you click the icon again. Now you can leave your video conference or vibe coding session open,
enable Catwalk, and confidently walk away from your computer knowing that Mr. Whiskers isnt going to send
the message "jkdsfaksfdh" to your manager.

<!-- Add a screenshot here: docs/screenshot.png -->

## Optional Sounds
You can right click the cat icon for additional sound options:
- Bloop: Make your cat feel productive!
- Keyboard: Make your cat feel like a great novelist!
- Purr: Make your cat happy!
- Hiss: Subtly tell your cat to get the f*** off of your keyboard.

## Install
Grab the latest **`Catwalk.app.zip`** from the [Releases page](../../releases), unzip it,
and drag **Catwalk** to your Applications folder. (macOS 13+, Apple Silicon or Intel.)

> On first launch macOS may say it's from an unidentified developer. Right-click the app →
> **Open** → **Open**.
> Accessibility permission is used for blocking the keyboard and mouse input only.

## Build from source
Requires the Xcode command-line tools.

```bash
git clone https://github.com/CatwalkDev/catwalk.git
cd catwalk
./build.sh
open Catwalk.app
```

## License

Code is released under the [MIT License](LICENSE). Bundled audio keeps its own licenses
(see credits above).
