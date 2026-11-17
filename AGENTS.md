# AGENTS.md

Guidance for building and running this Mac Dial on a Mac. Handy stays the official app — do not edit Handy source for Dial support.

## What this app does

Native macOS **menu-bar** app that owns the Microsoft Surface Dial (IOKit, vendor `0x045E` / product `0x091B`) and maps rotation, click, and hold to system actions.

`LSUIElement` is set: there is **no Dock icon**. After launch, the status item is a dial glyph plus the title **Dial** on the right side of the menu bar. Click it for settings.

**Handy button mode** (default):

- Short press → `Handy --toggle-transcription` (toggle listening)
- Press and hold (~350ms) → start listening; release → stop

Menu item label is **Handy**; icon is SF Symbol `hand.raised.fill`.

**Press + Turn** (default Scroll Left/Right): turning while the button is held sends horizontal scroll events to whatever is under the pointer. Clockwise scrolls right. The first detent cancels the press: Handy stops listening if this hold started it, and the release does nothing. Mute and Playback discard the release the same way. `Dial.pressRotationControl` routes these turns, and stationary (0) reports never trigger it, because the Dial sends them constantly while touched. Set the submenu to Same as Rotation for the old behaviour. Multi mode (color picker) turns it off.

**Double Press** (default Toggle Zoom): two short presses with at most 300 ms between the first release and the second press switch rotation to zoom mode, which sends vertical scroll with Control held (pen.dev's zoom). Double press again to go back. Each switch plays two short haptic clicks spaced like the two presses (clamped to 0.08 to 0.5 s), shows a badge (`Code/Presentation/Views/ModeHUD.swift`) and changes the menu bar item to a magnifier titled **Zoom**. `Dial.doublePressAction` swallows the second press. While it is set, Handy and Mute wait 330 ms after a short press before acting, so a double press can cancel them. Double press is off in Playback and Left Click modes, which use double clicks themselves, and in multi mode. Picking a rotation mode in the menu leaves zoom mode. Zoom uses Control, not Command, because macOS screen zoom (Accessibility, "Use scroll gesture with modifier keys to zoom") is often bound to Command + scroll.

## Prerequisites

- macOS 10.13+ (developed against macOS 26 / Apple Silicon; ad-hoc sign to run locally)
- Xcode (or Xcode Command Line Tools plus the MacDial scheme)
- Official [Handy](https://handy.computer) installed and running (`brew install --cask handy` is fine) if using Handy button mode
- Surface Dial paired over Bluetooth

Do not compile Handy from this workspace. The official bundle id is `com.pais.handy`.

## Build and run

From this repository root:

```bash
scripts/install-local.sh
```

The script builds Release, re-signs the app with the first Apple Development certificate in the keychain, quits the running copy, installs to `/Applications/MacDial.app` and opens it. Set `MACDIAL_SIGN_IDENTITY` to pick a different certificate.

Do not install an ad-hoc signed build. macOS ties privacy grants to the designated requirement, and an ad-hoc requirement is the cdhash, which changes on every build. System Settings then shows the switch as on while `AXIsProcessTrusted()` returns false and the Dial stays closed. The certificate-based requirement survives rebuilds.

The deployment target is macOS 12.0, the lowest the current Xcode accepts.

`Code/` is an Xcode synchronized root — new Swift files under `Code/` are picked up automatically.

Quit any other Mac Dial first (including `~/Applications/MacDial.app`). Two copies contend for the Dial. After `open`, confirm Activity Monitor shows `MacDial` from `/Applications/MacDial.app` and that **Dial** is in the menu bar (check the overflow on notched displays).

## Permissions

- **Mac Dial → Input Monitoring** (reading the Dial through IOKit). Without it `IOHIDManagerOpen` or `IOHIDDeviceOpen` fails and the menu shows "Needs Input Monitoring permission!".
- **Mac Dial → Accessibility** (key, scroll and click events, and the Option+Space fallback)
- **Handy → Microphone** and **Accessibility** (Handy button mode)

`Code/Utils/Permissions.swift` polls both Mac Dial permissions every 2 seconds and on the `com.apple.accessibility.api` notification. When Input Monitoring arrives, `AppController` restarts the HID manager, so no relaunch or settings toggle is needed. A watchdog also restarts it every 20 seconds while no Dial is open.

If a grant looks stuck after switching from an ad-hoc build, run `scripts/install-local.sh --reset-permissions`, then turn both switches on again.

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

Rotation handling lives in `Code/Dial/Device.swift`. Haptic writes run on a background queue and a tap is dropped while the previous one is in flight, because each write is a synchronous Bluetooth report that blocked the main run loop and delayed rotation. Rotation reports larger than ±1 are replayed as single steps, capped at 10.

The status item is created in `AppController.init` (`isVisible`, dial image, title **Dial**) so the menu bar extra is present even before the storyboard finishes loading.

## Do not

- Fork or patch Handy for Dial support
- Commit `build/` or `xcuserdata/`
- Leave two Mac Dial processes running (they will contend for the Dial)
