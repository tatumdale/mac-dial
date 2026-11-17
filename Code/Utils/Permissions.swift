//
//  Permissions
//  MacDial
//
//  Tracks the two privacy permissions Mac Dial needs and reports changes while the app runs.
//
//  - Accessibility lets the app post key, scroll and click events.
//  - Input Monitoring (kTCCServiceListenEvent) lets the app read the Dial through IOKit.
//    The Dial's HID descriptor includes a System Control collection (Sys Wake Up), and
//    macOS can refuse `IOHIDManagerOpen` and `IOHIDDeviceOpen` for such devices until
//    this is granted.
//
//  macOS does not notify an app when either permission is granted, and a HID manager
//  opened before the grant keeps failing. The monitor polls, and the app restarts the
//  HID manager when Input Monitoring arrives.
//

import AppKit
import IOKit.hid

final class PermissionMonitor {
    struct State: Equatable {
        var accessibility: Bool
        var inputMonitoring: Bool

        var allGranted: Bool { accessibility && inputMonitoring }
    }

    private(set) var state: State
    var onChange: ((_ old: State, _ new: State) -> Void)?

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    init() {
        state = Self.currentState()
    }

    deinit {
        timer?.invalidate()
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    static func currentState() -> State {
        State(accessibility: AXIsProcessTrusted(), inputMonitoring: isInputMonitoringGranted())
    }

    static func isInputMonitoringGranted() -> Bool {
        if #available(macOS 10.15, *) {
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
        return true
    }

    /// Shows the system prompt the first time. After that it only returns the current answer.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        if #available(macOS 10.15, *) {
            return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        return true
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        // Posted when any app's Accessibility row changes. tccd writes the new value
        // just after posting, so read it a moment later.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
            }
        }

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let newState = Self.currentState()
        guard newState != state else { return }

        let oldState = state
        state = newState
        log(tag: "Permissions", "accessibility: \(newState.accessibility), input monitoring: \(newState.inputMonitoring)")
        onChange?(oldState, newState)
    }
}
