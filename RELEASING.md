# Publishing Catwalk

Developer notes for putting Catwalk on GitHub and cutting a release. (Users don't need this —
it's just for whoever maintains the repo.)

## Project layout

```
Catwalk/
├── README.md            user-facing landing page
├── LICENSE              MIT (code)
├── RELEASING.md         this file
├── build.sh             compiles Sources/ → Catwalk.app and signs it
├── Info.plist           app bundle metadata
├── generate_sounds.py   regenerates Purr + Hiss (procedural)
├── fetch_clicks.py      (re)builds the Keyboard-Taps pool from Wikimedia Commons
├── Sources/             Swift source
│   ├── main.swift         entry point, menu, and the input-blocking event tap
│   ├── Overlay.swift      the "Input ignored!" overlay + icon spotlight
│   ├── SoundManager.swift sound loading/playback
│   └── AccentSlider.swift accent-colored volume slider
└── Sounds/              bundled audio + CREDITS.txt
```

## One-time: first upload

Run these from the project folder. Requires the [GitHub CLI](https://cli.github.com)
(`gh auth login` first).

```bash
cd ~/MyGames/Catwalk

git init
git config user.name  "CatwalkDev"                                # the publishing account
git config user.email "<ID>+CatwalkDev@users.noreply.github.com"  # your <ID> from GitHub → Settings → Emails
git add .
git commit -m "Catwalk 1.0"

# Create the public repo and push (rename "catwalk" if you like).
gh repo create catwalk --public --source=. --remote=origin --push \
  --description "Lock your Mac's keyboard and trackpad so your cat can walk on it."
```

## Cutting a release (with a downloadable app)

```bash
# 1. Build a fresh, ad-hoc-signed app (no identity embedded).
CATWALK_SIGN_ID=- ./build.sh

# 2. Zip it (ditto preserves the bundle + signature correctly; plain `zip` can corrupt it).
ditto -c -k --sequesterRsrc --keepParent Catwalk.app Catwalk.app.zip

# 3. Tag and publish, attaching the zip.
git tag v1.0
git push origin v1.0
gh release create v1.0 Catwalk.app.zip \
  --title "Catwalk 1.0" \
  --notes "Menu-bar cat that locks your keyboard and trackpad. Download Catwalk.app.zip, unzip, then right-click → Open on first launch."
```

For later releases, bump the version in `Info.plist`, then repeat with a new tag (`v1.1`, …).

## Signing & staying anonymous

`build.sh` **ad-hoc signs by default** — no developer identity is embedded, so a released
binary reveals nothing about who built it, and anyone can build from source. Downloaders
right-click → **Open** once to clear Gatekeeper (the README explains this).

- **Development:** `export CATWALK_SIGN_ID=<identity-hash>`
  (`security find-identity -v -p codesigning`) so the macOS Accessibility grant survives
  rebuilds. That signs your *local* builds with your identity — never publish one of those.
- **Release builds:** always `CATWALK_SIGN_ID=- ./build.sh` (forces ad-hoc), so your Apple
  identity can't leak into the published `.app`.

To stay pseudonymous on GitHub: the repo's git identity must be the **CatwalkDev** account
(set *before the first commit* — see the upload steps above), and `README.md`'s clone URL
already points at `CatwalkDev`.

Notarizing gives a seamless, warning-free install — but for an **individual** Apple Developer
account it embeds your **legal name** in the signature, so it's incompatible with staying
anonymous. Use an **Organization** account if you ever want both.
