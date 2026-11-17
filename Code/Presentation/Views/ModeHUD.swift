//
//  ModeHUD
//  MacDial
//
//  A short on-screen badge, like the system volume overlay, that names the Dial's
//  new rotation mode. It never takes focus or mouse clicks.
//

import AppKit

@MainActor
enum ModeHUD {
    private static var panel: NSPanel?
    private static var iconView: NSImageView?
    private static var label: NSTextField?
    private static var hideWork: DispatchWorkItem?

    private static let size = NSSize(width: 160, height: 140)
    private static let visibleDuration: TimeInterval = 1.0

    static func show(symbol: String, text: String) {
        let panel = panel ?? makePanel()

        iconView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        label?.stringValue = text

        // The screen with the pointer, so the badge appears where the user is working.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.2))
        }

        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true

        let icon = NSImageView(frame: NSRect(x: 0, y: 50, width: size.width, height: 64))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor

        let text = NSTextField(labelWithString: "")
        text.frame = NSRect(x: 8, y: 16, width: size.width - 16, height: 24)
        text.alignment = .center
        text.font = .systemFont(ofSize: 17, weight: .semibold)
        text.textColor = .labelColor

        background.addSubview(icon)
        background.addSubview(text)
        panel.contentView = background

        self.panel = panel
        self.iconView = icon
        self.label = text
        return panel
    }
}
