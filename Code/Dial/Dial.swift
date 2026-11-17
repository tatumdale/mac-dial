//
//  Dial
//  MacDial
//
//  Created by Alex Babaev
//
//  Based on Andreas Karlsson sources
//  https://github.com/andreasjhkarlsson/mac-dial
//
//  License: MIT
//

import Foundation

class Dial {
    // MARK: - Temporary state
    
    var controls: [DeviceControl] = []

    /// Receives rotation while the button is held. When nil, turning while pressed goes
    /// to `controls` like any other turn.
    var pressRotationControl: DeviceControl?

    /// Maximum gap between releasing the first press and starting the second one.
    static let doublePressWindow: TimeInterval = 0.3
    /// A press longer than this is a hold, so it cannot start a double press.
    private static let tapMaxDuration: TimeInterval = 0.35

    /// Runs on a double press. When nil, double press detection is off and every press
    /// goes to `controls`. Controls with a single-press action should defer that action
    /// by `doublePressWindow` while this is set, and cancel it in `buttonDoublePressed`.
    /// Receives the time from the first press to the second one.
    var doublePressAction: ((_ pressInterval: TimeInterval) -> Void)?
    var isDoublePressEnabled: Bool { doublePressAction != nil }
    
    var isHittingBounds: Bool {
        get { device.isHittingBounds }
        set { device.isHittingBounds = newValue }
    }
    
    // MARK: - Device

    private var device: DialDevice!

    init(
        connectionHandler: @escaping (_ serialNumber: String) -> Void,
        disconnectionHandler: @escaping () -> Void
    ) {
        device = DialDevice(
            buttonHandler: processButton,
            rotationHandler: processRotation,
            connectionHandler: connectionHandler,
            disconnectionHandler: disconnectionHandler
        )
    }

    deinit {
        device.disconnect()
    }

    private var lastButtonState: ButtonState = .released
    private var isPressRotating = false
    private var pressStartedAt: TimeInterval = 0
    private var lastTapReleasedAt: TimeInterval = 0
    private var isSwallowingPress = false

    private func processButton(state: ButtonState) {
        let lastButtonState = lastButtonState
        self.lastButtonState = state
        let now = Date.timeIntervalSinceReferenceDate

        switch (lastButtonState, state) {
            case (.released, .pressed):
                isPressRotating = false

                if let doublePressAction, now - lastTapReleasedAt <= Self.doublePressWindow {
                    lastTapReleasedAt = 0
                    isSwallowingPress = true
                    // pressStartedAt still holds the first press, because the second is swallowed.
                    let pressInterval = now - pressStartedAt
                    controls.forEach { $0.buttonDoublePressed(self) }
                    doublePressAction(pressInterval)
                    return
                }

                pressStartedAt = now
                controls.forEach { $0.buttonPress(self) }

            case (.pressed, .released):
                let wasPressRotating = isPressRotating
                isPressRotating = false

                if isSwallowingPress {
                    isSwallowingPress = false
                    return
                }

                // Only a short press with no turn can be the first half of a double press.
                let wasTap = !wasPressRotating && now - pressStartedAt < Self.tapMaxDuration
                lastTapReleasedAt = wasTap ? now : 0
                controls.forEach { $0.buttonRelease(self) }

            default: break
        }
    }

    private func processRotation(state: RotationState) -> Bool {
        // Reset haptic bounds
        self.isHittingBounds = false

        if lastButtonState == .pressed, let pressRotationControl {
            // The Dial sends stationary (0) reports while it is touched or pressed.
            // Only a real detent turns the press into a press-and-turn.
            guard state != .stationary else { return false }

            if !isPressRotating {
                isPressRotating = true
                controls.forEach { $0.buttonPressRotated(self) }
            }
            return pressRotationControl.rotationChanged(self, state)
        }
        
        var result = false
        controls.forEach { result = $0.rotationChanged(self, state) || result }
        return result
    }
    
    var isConnected: Bool { device.isConnected }

    /// Reopens the HID manager, for example after macOS grants Input Monitoring.
    func restart() {
        lastButtonState = .released
        isPressRotating = false
        isSwallowingPress = false
        lastTapReleasedAt = 0
        device.restart()
    }

    public func sendKeepAlive() {
        device.sendKeepAlive()
    }
    
    /// Two short clicks, `interval` apart, so the Dial echoes the rhythm of a double press.
    /// The interval is clamped to 0.08 to 0.5 s: shorter and the second write is dropped
    /// while the first is still in flight, longer and it no longer feels like one gesture.
    public func sendDoubleClickHaptic(interval: TimeInterval) {
        let gap = min(max(interval, 0.08), 0.5)
        device.sendHaptic(pattern: .click)
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
            self?.device.sendHaptic(pattern: .click)
        }
    }

    public func sendHaptic(pattern: DialDevice.DeviceHaptic) {
        device.sendHaptic(pattern: pattern)
    }
}
