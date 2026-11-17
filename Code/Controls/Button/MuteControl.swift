//
//  MuteControl
//  MacDial
//
//  Created by Daniel Costa
//
//  License: MIT
//

import AppKit

class ButtonMuteControl: DeviceControl {
    func buttonPress(_ dial: Dial) {
        startedPressingAt = Date.timeIntervalSinceReferenceDate
    }
    
    private var startedPressingAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    private var pendingTap: DispatchWorkItem?

    func buttonDoublePressed(_ dial: Dial) {
        pendingTap?.cancel()
        pendingTap = nil
    }

    func buttonPressRotated(_ dial: Dial) {
        // A zero start time makes the release look like a long hold, which is discarded.
        startedPressingAt = 0
    }

    func buttonRelease(_ dial: Dial) {
        if ((Date.timeIntervalSinceReferenceDate - startedPressingAt) >= 0.35) {
            log(tag: "Mute", "button held for extended period, discarding input")
            
            return
        }
        startedPressingAt = 0

        guard dial.isDoublePressEnabled else {
            toggleMute()
            return
        }

        pendingTap?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingTap = nil
            self?.toggleMute()
        }
        pendingTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Dial.doublePressWindow + 0.03, execute: work)
    }

    private func toggleMute() {
        guard var isMuted = Sound.isMuted() else { return }
        isMuted = !isMuted
        
        Sound.mute(isMuted)
        
        log(tag:"Mute", "\(isMuted)")
        
        if (UserSettings.showOSD) {
            if let currentVolume = Sound.volume() {
                OSD.show(
                    isMuted ? OSD.images.mute : OSD.images.volume,
                    UInt32(isMuted ? 0 : (currentVolume * 100))
                )
            }
        }
    }

    func rotationChanged(_ dial: Dial, _ rotation: RotationState) -> Bool {
        false
    }
}
