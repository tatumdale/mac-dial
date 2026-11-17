//
//  RotationScrollControl
//  MacDial
//
//  Created by Daniel Costa
//
//  Based on Alex Babaev sources
//  https://github.com/bealex/mac-dial
//
//  Based on Andreas Karlsson sources
//  https://github.com/andreasjhkarlsson/mac-dial
//
//  License: MIT
//

import AppKit

class RotationScrollControl: DeviceControl {
    enum Axis {
        /// Clockwise scrolls up.
        case vertical
        /// Clockwise scrolls right. No modifier keys, because Shift and friends change
        /// what a horizontal scroll does in many apps.
        case horizontal
    }

    private let axis: Axis
    /// Replaces the user's scroll modifier keys. Zoom mode uses Control, which apps
    /// such as pen.dev treat as pinch zoom.
    private let forcedFlags: CGEventFlags?

    init(axis: Axis = .vertical, forcedFlags: CGEventFlags? = nil) {
        self.axis = axis
        self.forcedFlags = forcedFlags
    }

    func buttonPress(_ dial: Dial) {
    }

    func buttonRelease(_ dial: Dial) {
    }

    func rotationChanged(_ dial: Dial, _ rotation: RotationState) -> Bool {
        // Distance to scroll (in pixels)
        let changeIncrements: [WheelSensitivity: Int] = [
            .low: 1,
            .medium: 40,
            .high: 80,
            .custom: UserSettings.customSensitivity
        ]
        
        var wheel1: Int
        switch rotation {
            case .stationary:
                return false
            case .clockwise:
                wheel1 = changeIncrements[rotation.sensitivity] ?? 0
            case .counterclockwise:
                wheel1 = (changeIncrements[rotation.sensitivity] ?? 0) * -1
        }

        if axis == .horizontal {
            // A positive wheel2 delta scrolls left, so flip it to make clockwise go right.
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: Int32(-wheel1),
                wheel3: 0
            )
            event?.post(tap: CGEventTapLocation.cghidEventTap)
            log(tag: "Scroll", wheel1 > 0 ? "Right" : "Left")
            return true
        }

        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(wheel1),
            wheel2: 0,
            wheel3: 0
        )
        
        var flags: CGEventFlags = []
        if UserSettings.keyScrollModifiers.shift { flags.insert(.maskShift) }
        if UserSettings.keyScrollModifiers.command { flags.insert(.maskCommand) }
        if UserSettings.keyScrollModifiers.option { flags.insert(.maskAlternate) }
        if UserSettings.keyScrollModifiers.control { flags.insert(.maskControl) }
        
        event?.flags = forcedFlags ?? flags
        event?.post(tap: CGEventTapLocation.cghidEventTap)
        
        log(tag: "Scroll", wheel1 > 0 ? "Up" : "Down")

        return true
    }
}
