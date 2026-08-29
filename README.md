![MacDial](https://i.imgur.com/sEMVkMG.png)

<h3 align="center">Use your Surface Dial with macOS</h4>

The Surface Dial can be paired through Bluetooth with macOS, but sends invalid inputs by default, resulting in the dial having no functionality. This app reads the raw data from the dial and translates it to various actions to act as a customizable input device.

Built as a native macOS app as to use as little resource consumption as possible, with easy customization from the menu bar. Every option in the app can additionally be scripted with both [Shortcuts](https://support.apple.com/en-ca/guide/shortcuts-mac/welcome/mac) as well as [AppleScript](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/introduction/ASLR_intro.html)/[JXA](https://bru6.de/jxa/).

Supports macOS 10.13 (High Sierra) to macOS 26 (Tahoe)

## Usage

The app will continuously try to open any Surface Dial connected to the computer and then process input controls. You will need to pair and connect the device as any other bluetooth device.

There are three mode types that you can select from:
- **Rotation Mode:** Allows for rotational feature control with the dial (eg: scrolling, volume/brightness control)
- **Button Mode:** Allows for pressed feature control with the dial (eg: media control, mouse click, Handy)
- **Multi Mode:** Allows for both rotational & pressed control to work together for a single feature (eg: color picker control)

## Handy speech-to-text

Mac Dial can drive the official [Handy](https://handy.computer) app. Do not fork or rebuild Handy for this — install the release from the website or Homebrew.

| Dial | Handy |
| --- | --- |
| Short press | Toggle listening on/off |
| Press and hold | Start listening; release stops (push-to-talk) |

Enable it from the menu bar icon → **Button Mode → Handy** (hand icon). Handy is the default button mode. Choose **None** (or another mode) to turn it off.

Mac Dial prefers `Handy --toggle-transcription` on the running official app (`com.pais.handy`). If the binary is missing it sends **Option+Space**, Handy's default shortcut.

## Run on another Mac

1. Install official Handy (`brew install --cask handy` or [handy.computer](https://handy.computer)) and launch it. Grant **Microphone** and **Accessibility**.
2. Clone and build this Mac Dial (Xcode required):

```bash
git clone https://github.com/tatumdale/mac-dial.git
cd mac-dial
xcodebuild -scheme MacDial -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
ditto "build/Build/Products/Release/MacDial.app" "$HOME/Applications/MacDial.app"
open "$HOME/Applications/MacDial.app"
```

3. Grant **Accessibility** to this Mac Dial build when prompted (required to send the Handy shortcut fallback).
4. Pair the Surface Dial in **System Settings → Bluetooth**. If pairing stalls, hold the button **under the battery cover** until the LED blinks slowly. Unpair it from Windows first if the LED blinks three times.
5. In Mac Dial, confirm **Button Mode → Handy**. Keep Handy running.

Install this build under `~/Applications`. The notarized store/GitHub Mac Dial in `/Applications` is a different binary and can fight this one for the Dial. Quit the other copy if both appear in the menu bar.

Agent-oriented build notes: [AGENTS.md](AGENTS.md).

## Screenshots
| | |
|:-:|:-:|
| ![Rotation Mode](https://i.imgur.com/edPui4t.png) | ![Button Mode](https://i.imgur.com/g1lULZd.png) |
 | ![Multi Mode](https://i.imgur.com/q4vikn5.png) | ![Key/Scroll Modifiers](https://i.imgur.com/ZqQk3P7.png) |

## Scripting Examples

### AppleScript
```applescript
tell application "MacDial"
    set rotation mode scrolling
    set wheel sensitivity custom
    set custom sensitivity 500
    set key scroll modifiers with shift and control without command and option
    set haptics true
end tell
```

### JXA
```js
(() => {
    const MacDial = Application("MacDial");

    MacDial.setRotationMode("scrolling");
    MacDial.setWheelSensitivity("custom");
    MacDial.setCustomSensitivity(500);
    MacDial.setKeyScrollModifiers({
        shift: true,
        command: false,
        option: false,
        control: true
    });
    MacDial.setHaptics(true);
})()
```

### Shortcuts
![](https://i.imgur.com/MDrCKId.png)

## Credits
- https://github.com/SoCuul/mac-dial - Native IOKit Mac Dial this tree is based on
- https://github.com/andreasjhkarlsson/mac-dial - The original implementation of the Surface Dial on macOS
- https://github.com/bealex/mac-dial - Rewrite of the original project to make use of native IOKit APIs and an AppKit-based UI
- https://handy.computer — Official Handy speech-to-text app (used as-is via CLI)