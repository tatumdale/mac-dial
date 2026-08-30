# AGENTS.md

Guidance for building and running this Mac Dial on a Mac. Handy stays the official app — do not edit Handy source for Dial support.

## What this app does

Native macOS **menu-bar** app that owns the Microsoft Surface Dial (IOKit, vendor `0x045E` / product `0x091B`) and maps rotation, click, and hold to system actions.

`LSUIElement` is set: there is **no Dock icon**. After launch, the status item is a dial glyph plus the title **Dial** on the right side of the menu bar. Click it for settings.

**Handy button mode** (default):

- Short press → `Handy --toggle-transcription` (toggle listening)
- Press and hold (~350ms) → start listening; release → stop

Menu item label is **Handy**; icon is SF Symbol `hand.raised.fill`.

## Prerequisites

- macOS 10.13+ (developed against macOS 26 / Apple Silicon; ad-hoc sign to run locally)
- Xcode (or Xcode Command Line Tools plus the MacDial scheme)
- Official [Handy](https://handy.computer) installed and running (`brew install --cask handy` is fine) if using Handy button mode
- Surface Dial paired over Bluetooth

Do not compile Handy from this workspace. The official bundle id is `com.pais.handy`.

## Build and run

From this repository root. Install local builds to `/Applications` (Finder’s Applications folder):

```bash
xcodebuild -scheme MacDial -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
ditto "build/Build/Products/Release/MacDial.app" "/Applications/MacDial.app"
open "/Applications/MacDial.app"
```

`Code/` is an Xcode synchronized root — new Swift files under `Code/` are picked up automatically.

Quit any other Mac Dial first (including `~/Applications/MacDial.app`). Two copies contend for the Dial. After `open`, confirm Activity Monitor shows `MacDial` from `/Applications/MacDial.app` and that **Dial** is in the menu bar (check the overflow on notched displays).

## Permissions

- **Mac Dial → Accessibility** (key-event fallback and some click modes)
- **Handy → Microphone** and **Accessibility** (Handy button mode)
- After an ad-hoc rebuild, macOS may keep a stale Accessibility row. Quit Mac Dial, remove the old entry, reopen, and grant again.

## Pairing the Dial

1. System Settings → Bluetooth
2. If Connect never finishes: hold the pairing button **under the battery cover** until a slow blink
3. Unpair from Windows first if the LED blinks three times (already bonded elsewhere)

## Handy integration

Implementation: `Code/Controls/Button/HandyControl.swift`

1. Resolve `Handy.app` via `com.pais.handy` / `computer.handy.app`, then `/Applications` and `~/Applications`
2. Run `Handy --toggle-transcription` (single-instance plugin forwards to the running app)
3. If the binary is missing, post **Option+Space**

Handy only exposes toggle, not start/stop. Hold/release is two toggles plus local `listening` state — it can drift if the user also uses Option+Space or the tray.

## Layout

```
Code/
  Controls/Button/HandyControl.swift   # tap / hold → Handy
  Presentation/AppController.swift     # menu bar item + Button Mode → Handy
  UserSettings.swift                   # ButtonOperationMode.handy = 4
Resources/Localizable.xcstrings        # menu.buttonMode.handy = "Handy"
```

Default `settings.buttonMode` is Handy (`4`).

The status item is created in `AppController.init` (`isVisible`, dial image, title **Dial**) so the menu bar extra is present even before the storyboard finishes loading.

## Do not

- Fork or patch Handy for Dial support
- Commit `build/` or `xcuserdata/`
- Leave two Mac Dial processes running (they will contend for the Dial)
