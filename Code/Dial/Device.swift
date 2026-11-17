//
//  Device
//  MacDial
//
//  Created by Alex Babaev
//
//  Based on Andreas Karlsson sources
//  https://github.com/andreasjhkarlsson/mac-dial
//
//  License: MIT
//

import AppKit

// Identifiers for the Surface Dial
private let _dialVendorId: UInt16 = 0x045E
private let _dialProductId: UInt16 = 0x091B

/// The Dial reports rotation as a signed relative value. It is normally ±1, but a busy
/// run loop or a fast spin can coalesce several detents into one report. Cap the
/// replay so one corrupt report cannot jump the volume to 0 or 100%.
private let _maxRotationStepsPerReport: Int = 10

private var _connectedSerialNumbers: [String] = []
private var _setDevicePointerHandler: (IOHIDDevice, String) -> Void = { _, _ in }

private var _buttonHandler: (ButtonState) -> Void = { _ in }
private var _rotationHandler: (RotationState) -> Bool = { _ in false }
private var _connectionHandler: (_ serialNumber: String) -> Void = { _ in }
private var _disconnectionHandler: () -> Void = {}
private var _sendHapticsTapToDialHandler: () -> Void = {}

/// True only after `IOHIDDeviceOpen` succeeded. Input values arriving before that are ignored.
private var _isDeviceReady: Bool = false

private var _queue: IOHIDQueue?

private var _hapticsElementManualTrigger: IOHIDElement?

/// Haptic output reports are synchronous Bluetooth writes that take 10 to 40 ms each.
/// Running them on the main run loop delays the next rotation report, so they run on
/// their own queue, and a new tap is dropped while the previous one is still being sent.
private let _hapticsQueue = DispatchQueue(label: "com.socuul.macdial.haptics", qos: .userInteractive)
private var _isHapticInFlight = false

class DialDevice {
    // MARK: - Temporary state

    var isHittingBounds: Bool = false

    // MARK: - Private state

    private var dialDevice: IOHIDDevice?
    private var serialNumber: String = "—"

    var isConnected: Bool { dialDevice != nil && _isDeviceReady }

    private var keepAliveTimer: DispatchSourceTimer?

    // MARK: - Init

    init(
        buttonHandler: @escaping (ButtonState) -> Void,
        rotationHandler: @escaping (RotationState) -> Bool,
        connectionHandler: @escaping (_ serialNumber: String) -> Void,
        disconnectionHandler: @escaping () -> Void
    ) {
        _buttonHandler = buttonHandler
        _rotationHandler = rotationHandler
        _connectionHandler = connectionHandler
        _disconnectionHandler = { [self] in
            let wasConnected = isConnected
            closeDevice()
            if wasConnected {
                disconnectionHandler()
            }
        }
        _sendHapticsTapToDialHandler = { [self] in
            let haptic: DeviceHaptic = isHittingBounds ? .rumble : .click

            sendHaptic(pattern: haptic)
        }

        startManager()
    }

    deinit {
        stopManager()
    }

    // MARK: HIDManager

    private var hidManager: IOHIDManager?

    /// Closes the HID manager and opens a new one. Use this after macOS grants
    /// Input Monitoring, or when the Dial is paired but the app never received it.
    func restart() {
        log(tag: "Manager", "restarting")
        _disconnectionHandler()
        stopManager()
        startManager()
    }

    private func startManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matchingDictionary: NSMutableDictionary = .init()
        matchingDictionary[kIOHIDVendorIDKey as NSString] = NSNumber(value: _dialVendorId)
        matchingDictionary[kIOHIDProductIDKey as NSString] = NSNumber(value: _dialProductId)
        IOHIDManagerSetDeviceMatching(manager, matchingDictionary)

        IOHIDManagerRegisterInputValueCallback(manager, Self.inputCallback, nil)
        registerDeviceMatching(manager)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Without Input Monitoring this returns kIOReturnNotPermitted. Keep the manager
        // anyway: the app restarts it when the permission arrives.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            log(tag: "Manager", "opened")
        } else {
            log(tag: "Manager", "open error: \(hex: UInt32(bitPattern: result))")
        }

        hidManager = manager
    }

    private func stopManager() {
        guard let manager = hidManager else { return }

        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        log(tag: "Manager", "closed")
    }

    private static let inputCallback: IOHIDValueCallback = { _, result, _, value in
        guard _isDeviceReady else { return }

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usageId = IOHIDElementGetUsage(element)

        //    0x9|0x1|0x1: Button page, primary button. 1 when pressed, 0 when released.
        //    0x1|0x37|0x1: Generic Desktop page, Dial. Signed relative value, positive is clockwise.
        //
        //   Not used:
        //    0xd|0x48|0x1: Digitizer page, Width
        //    0x1|0x30|0x1, 0x1|0x31|0x1: Generic Desktop page, X and Y (on-screen puck position)
        //    0xd|0x33|0x1: Digitizer page, Touch

        switch (usagePage, usageId) {
            case (0x01, 0x37): // Generic page; Dial
                let rawValue = IOHIDValueGetIntegerValue(value)
                var needHaptics = false

                if rawValue == 0 {
                    needHaptics = _rotationHandler(.stationary)
                } else {
                    let isClockwise = (rawValue > 0) == (UserSettings.wheelDirection == .clockwise)
                    let sensitivity = UserSettings.sensitivity
                    let direction: RotationState = isClockwise ? .clockwise(sensitivity) : .counterclockwise(sensitivity)
                    let steps = min(abs(rawValue), _maxRotationStepsPerReport)
                    for _ in 0 ..< steps {
                        needHaptics = _rotationHandler(direction) || needHaptics
                    }
                }

                if needHaptics {
                    _sendHapticsTapToDialHandler()
                }

            case (0x09, 0x01): // Generic page; Button
                let stateValue = IOHIDValueGetIntegerValue(value)
                _buttonHandler(stateValue == 1 ? .pressed : .released)

            default:
                break
        }
    }

    private func registerDeviceMatching(_ manager: IOHIDManager) {
        _setDevicePointerHandler = { [self] device, serialNumber in
            guard dialDevice == nil else {
                log(tag: "Manager", "ignoring a second dial: \(serialNumber)")
                return
            }

            dialDevice = device
            self.serialNumber = serialNumber
            _connectedSerialNumbers.append(serialNumber)

            if openDevice() {
                _connectionHandler(serialNumber)
            } else {
                // Leave no trace, so the next restart or re-pairing tries this dial again.
                closeDevice()
            }
        }

        let hidDeviceMatchingCallback: IOHIDDeviceCallback = { context, result, _, device in
            log(tag: "Manager", "Monitoring detected a dial...")

            // Some firmware versions report no serial number over Bluetooth.
            let serialNumber = (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as NSString) as? String)
                ?? (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as NSString) as? NSNumber).map { "loc-\($0)" }
                ?? "unknown"
            guard !_connectedSerialNumbers.contains(serialNumber) else { return }

            log(tag: "Manager", "Found dial, serial number: \(serialNumber)")
            _setDevicePointerHandler(device, serialNumber)
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchingCallback, nil)
        log(tag: "Manager", "Monitoring started")
    }

    func disconnect() {
        _disconnectionHandler()
        stopManager()
    }

    // MARK: Setup device input

    /// Opens the device, finds the haptics output element, and starts the keep-alive timer.
    /// Returns false when macOS refuses access, for example before Input Monitoring is granted.
    private func openDevice() -> Bool {
        guard let dialDevice else { return false }

        let result = IOHIDDeviceOpen(dialDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            log(tag: "Device", "open error: \(hex: UInt32(bitPattern: result))")
            return false
        }
        log(tag: "Device", "opened")

        findHapticsElement(dialDevice)
        startDebugQueue(dialDevice)

        IOHIDDeviceScheduleWithRunLoop(dialDevice, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let removalCallback: IOHIDCallback = { _, result, data in
            log(tag: "Device", "removed")
            _disconnectionHandler()
        }
        IOHIDDeviceRegisterRemovalCallback(dialDevice, removalCallback, nil)

        _isDeviceReady = true
        setupKeepAlive()
        return true
    }

    private func closeDevice() {
        _isDeviceReady = false

        if let dialDevice {
            IOHIDDeviceRegisterRemovalCallback(dialDevice, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(dialDevice, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(dialDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            log(tag: "Device", "closed")
        }
        if let queue = _queue {
            IOHIDQueueStop(queue)
            IOHIDQueueUnscheduleFromRunLoop(queue, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            log(tag: "Queue", "stopped")
            _queue = nil
        }

        dialDevice = nil
        _connectedSerialNumbers = _connectedSerialNumbers.filter { $0 != serialNumber }
        serialNumber = "—"
        _hapticsElementManualTrigger = nil

        destroyKeepAlive()
    }

    private func findHapticsElement(_ device: IOHIDDevice) {
        guard
            let cfElements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)),
            let elements = (cfElements as [AnyObject]) as? [IOHIDElement]
        else { return }

        _hapticsElementManualTrigger = elements.first { element in
            IOHIDElementGetUsagePage(element) == 0x0e
                && IOHIDElementGetUsage(element) == 0x21
                && IOHIDElementGetReportID(element) == 0x01
                && IOHIDElementGetType(element) == kIOHIDElementTypeOutput
        }
        log(tag: "Device Descriptor", _hapticsElementManualTrigger == nil ? "no haptics element" : "haptics manual trigger found")
    }

    /// Debug builds log the Dial's other input elements, which helps when mapping new usages.
    private func startDebugQueue(_ device: IOHIDDevice) {
        guard debugBuild, let queue = IOHIDQueueCreate(nil, device, 16, IOOptionBits(kIOHIDOptionsTypeNone)) else { return }
        _queue = queue

        if let cfElements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)),
           let elements = (cfElements as [AnyObject]) as? [IOHIDElement] {
            elements
                .filter { element in
                    let type = IOHIDElementGetType(element)
                    let isInput = type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button || type == kIOHIDElementTypeInput_Axis
                    let usage = (IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element))
                    let isHandled = usage == (0x01, 0x37) || usage == (0x09, 0x01) || usage == (0x0d, 0x33)
                    return isInput && !isHandled
                }
                .forEach { IOHIDQueueAddElement(queue, $0) }
        }

        let queueCallback: IOHIDCallback = { _, _, _ in
            guard let queue = _queue else { return }

            while let value = IOHIDQueueCopyNextValue(queue) {
                let element = IOHIDValueGetElement(value)
                let data = Data(bytes: IOHIDValueGetBytePtr(value), count: IOHIDValueGetLength(value))
                log(tag: "Queue", "got value: \(hex: IOHIDElementGetUsagePage(element))|\(hex: IOHIDElementGetUsage(element)): \(data.map { "\(hex: $0)" }.joined(separator: ", "))")
            }
        }
        IOHIDQueueRegisterValueAvailableCallback(queue, queueCallback, nil)
        IOHIDQueueScheduleWithRunLoop(queue, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDQueueStart(queue)
        log(tag: "Queue", "started")
    }

    // MARK: Keep device alive

    /// The Surface Dial has a timeout of exactly **5 minutes** of not being used, before disconnecting. \
    /// Sending empty haptic feedback to the dial every **270 seconds (4m30s)** keeps it connected, any longer causes accidental disconnects.
    private func setupKeepAlive() {
        destroyKeepAlive()
        keepAliveTimer = DispatchSource.makeTimerSource(queue: .main)
        keepAliveTimer?.schedule(deadline: .now() + 5, repeating: 270)
        keepAliveTimer?.setEventHandler { [weak self] in
            self?.sendKeepAlive()
        }
        keepAliveTimer?.resume()
    }

    private func destroyKeepAlive() {
        keepAliveTimer?.cancel()

        keepAliveTimer = nil
    }

    /// Sends empty haptic feedback to the dial to keep it connected
    public func sendKeepAlive() {
        if isConnected && UserSettings.keepDialAwake {
            log(tag:"Device", "sending keep alive haptic")

            sendHaptic(pattern: .none, force: true)
        }
    }

    // MARK: Device haptics

    public enum DeviceHaptic: Int {
        case click = 0x1003
        case rumble = 0x1005

        case buzz = 0x1004

        case none = 0x1000
    }

    /// Call on the main thread. The write itself runs on `_hapticsQueue`.
    public func sendHaptic(pattern haptic: DeviceHaptic, force: Bool = false) {
        guard force || UserSettings.hapticsEnabled else { return }
        guard let dialDevice, let element = _hapticsElementManualTrigger, _isDeviceReady else { return }
        guard !_isHapticInFlight else { return }

        _isHapticInFlight = true
        _hapticsQueue.async {
            let value = IOHIDValueCreateWithIntegerValue(nil, element, 0, haptic.rawValue)
            let result = IOHIDDeviceSetValue(dialDevice, element, value)

            DispatchQueue.main.async {
                _isHapticInFlight = false
                if result != kIOReturnSuccess {
                    log(tag: "Device", "\(haptic == .none ? "keep alive" : "haptics tap") error: \(hex: UInt32(bitPattern: result))")
                }
            }
        }
    }
}

extension DefaultStringInterpolation {
    mutating func appendInterpolation(hex: any FixedWidthInteger) {
        appendInterpolation("0x\(String(hex, radix: 16))")
    }
}
