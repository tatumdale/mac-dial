//
//  HandyControl
//  MacDial
//
//  Press toggles Handy listening. Press-and-hold starts listening;
//  release stops it. Turning while pressed cancels the press: it stops
//  listening that this hold started, and the release then does nothing.
//  While double press is on, a short press toggles after the double-press
//  window, and a double press cancels it.
//

import AppKit

class ButtonHandyControl: DeviceControl {
    private let holdThreshold: TimeInterval = 0.35
    private var pressStartedAt: TimeInterval = 0
    private var isPressed = false
    private var isLongPress = false
    private var listening = false
    private var isPressRotated = false
    private var holdStartedListening = false
    private var pendingTap: DispatchWorkItem?
    private var holdTimer: DispatchWorkItem?

    func buttonPress(_ dial: Dial) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePress()
        }
    }

    func buttonRelease(_ dial: Dial) {
        let deferTap = dial.isDoublePressEnabled
        DispatchQueue.main.async { [weak self] in
            self?.handleRelease(deferTap: deferTap)
        }
    }

    func buttonDoublePressed(_ dial: Dial) {
        // Runs on the main thread, before the pending tap can fire.
        pendingTap?.cancel()
        pendingTap = nil
        log(tag: "Handy", "double press, single press cancelled")
    }

    func buttonPressRotated(_ dial: Dial) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePressRotated()
        }
    }

    func rotationChanged(_ dial: Dial, _ rotation: RotationState) -> Bool {
        false
    }

    private func handlePress() {
        isPressed = true
        isLongPress = false
        isPressRotated = false
        holdStartedListening = false
        pressStartedAt = Date.timeIntervalSinceReferenceDate

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPressed else { return }
            self.isLongPress = true
            if !self.listening {
                self.setListening(true)
                self.holdStartedListening = true
            }
        }
        holdTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
    }

    private func handlePressRotated() {
        guard isPressed, !isPressRotated else { return }
        isPressRotated = true

        holdTimer?.cancel()
        holdTimer = nil

        // Only stop listening that this hold started. Listening that an earlier short
        // press turned on keeps going.
        if holdStartedListening && listening {
            setListening(false)
        }
        holdStartedListening = false
        isLongPress = false
    }

    private func handleRelease(deferTap: Bool) {
        holdTimer?.cancel()
        holdTimer = nil
        isPressed = false

        if isPressRotated {
            isPressRotated = false
            return
        }

        if isLongPress {
            if listening {
                setListening(false)
            }
            isLongPress = false
            return
        }

        guard deferTap else {
            setListening(!listening)
            return
        }

        pendingTap?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingTap = nil
            self.setListening(!self.listening)
        }
        pendingTap = work
        // A little longer than the window, so a second press that lands right at the
        // edge still cancels this.
        DispatchQueue.main.asyncAfter(deadline: .now() + Dial.doublePressWindow + 0.03, execute: work)
    }

    private func setListening(_ on: Bool) {
        HandyApp.toggleListening()
        listening = on
        log(tag: "Handy", on ? "listening on" : "listening off")
    }
}

enum HandyApp {
    static func handIcon() -> NSImage {
        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Handy") {
                image.isTemplate = true
                return image
            }
        }
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.black.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: 2))
        path.line(to: NSPoint(x: 12, y: 6))
        path.line(to: NSPoint(x: 12, y: 10))
        path.line(to: NSPoint(x: 10, y: 14))
        path.line(to: NSPoint(x: 6, y: 14))
        path.line(to: NSPoint(x: 4, y: 10))
        path.line(to: NSPoint(x: 4, y: 6))
        path.close()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static let bundleIdentifiers = [
        "com.pais.handy",
        "computer.handy.app",
    ]

    static func toggleListening() {
        if invokeCLI() {
            return
        }
        postDefaultShortcut()
    }

    private static func handyExecutableURL() -> URL? {
        for identifier in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                let binary = appURL.appendingPathComponent("Contents/MacOS/Handy")
                if FileManager.default.isExecutableFile(atPath: binary.path) {
                    return binary
                }
            }
        }

        let fallbacks = [
            "/Applications/Handy.app/Contents/MacOS/Handy",
            NSHomeDirectory() + "/Applications/Handy.app/Contents/MacOS/Handy",
        ]
        for path in fallbacks where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    @discardableResult
    private static func invokeCLI() -> Bool {
        guard let executable = handyExecutableURL() else {
            log(tag: "Handy", "Handy.app not found; falling back to Option+Space")
            return false
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--toggle-transcription"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            log(tag: "Handy", "CLI failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Handy's default macOS shortcut is Option+Space (push-to-talk / toggle).
    private static func postDefaultShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let space: CGKeyCode = 49
        let flags: CGEventFlags = .maskAlternate

        let down = CGEvent(keyboardEventSource: source, virtualKey: space, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: space, keyDown: false)
        up?.flags = flags

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        log(tag: "Handy", "posted Option+Space")
    }
}
