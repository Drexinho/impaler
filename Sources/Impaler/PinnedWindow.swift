import AppKit
import ScreenCaptureKit

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Připnuté okno: sleduje ho přes AX a když není fokusované, překryje ho živým zrcadlem v úrovni .floating.
@MainActor
final class PinnedWindow: NSObject, SCStreamOutput {
    private let windowID: CGWindowID
    private let pid: pid_t
    private let axApp: AXUIElement
    private let axWindow: AXUIElement
    private let onUnpin: (String?) -> Void  // zpráva = odepnuto kvůli chybě
    private let mirror = PinnedWindow.panel(level: .floating)
    private let badge = PinnedWindow.panel(level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
    private var observer: AXObserver?
    private var stream: SCStream?
    private var scale: CGFloat = 2
    private var size = CGSize.zero
    private var closed = false
    private var handoff: Task<Void, Never>?  // běžící předání kliku ze zrcadla

    init?(windowID: CGWindowID, pid: pid_t, bounds: CGRect, onUnpin: @escaping (String?) -> Void) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        let candidates = value as? [AXUIElement] ?? []
        guard let window = candidates.first(where: {
            var id = CGWindowID(0)
            return _AXUIElementGetWindow($0, &id) == .success && id == windowID
        }) ?? candidates.first(where: { Self.frame(of: $0) == bounds }) else { return nil }
        self.windowID = windowID
        self.pid = pid
        self.axApp = app
        self.axWindow = window
        self.onUnpin = onUnpin
        super.init()

        let mirrorView = ClickView()
        mirrorView.wantsLayer = true
        mirrorView.layer?.contentsGravity = .resize
        mirrorView.onClick = { [weak self] in self?.clickThrough() }
        mirror.contentView = mirrorView
        let badgeView = BadgeView()
        badgeView.onClick = { onUnpin(nil) }
        badge.contentView = badgeView

        var observer: AXObserver?
        AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<PinnedWindow>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { me.handle(name) }  // zdroj běží na hlavním run loopu
        }, &observer)
        if let observer {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(observer, window, name as CFString, refcon)
            }
            AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            self.observer = observer
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        update()
        Task { await startStream() }
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        handoff?.cancel()
        if let stream {  // stream ve fázi startu tu ještě není; zastaví ho startStream()
            try? stream.removeStreamOutput(self, type: .screen)
            Task { try? await stream.stopCapture() }
        }
        stream = nil
        mirror.orderOut(nil)
        badge.orderOut(nil)
    }

    // MARK: Sledování okna

    private func handle(_ notification: String) {
        if notification == kAXUIElementDestroyedNotification { onUnpin(nil) } else { update() }
    }

    @objc private func appActivated(_ note: Notification) { update() }

    @objc private func appTerminated(_ note: Notification) {
        if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == pid { onUnpin(nil) }
    }

    private var isFocused: Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value)
        return value.map { CFEqual($0, axWindow) } ?? false
    }

    private func update() {
        guard !closed, let frame = Self.frame(of: axWindow) else { return }
        let height = NSScreen.screens[0].frame.height  // převod CG (počátek vlevo nahoře) → AppKit
        mirror.setFrame(CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height), display: false)
        badge.setFrame(CGRect(x: frame.maxX - 24, y: height - frame.minY - 24, width: 20, height: 20), display: true)
        badge.orderFrontRegardless()
        if isFocused || handoff != nil { mirror.orderOut(nil) } else { mirror.orderFrontRegardless() }
        if frame.size != size {
            size = frame.size
            if let stream {
                let configuration = makeConfiguration()
                Task { try? await stream.updateConfiguration(configuration) }
            }
        }
    }

    /// Klik do zrcadla: vynes reálné okno dopředu a klik zopakuj, až když má prokazatelně fokus.
    private func clickThrough() {
        guard handoff == nil else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: NSScreen.screens[0].frame.height - mouse.y)
        mirror.orderOut(nil)
        NSRunningApplication(processIdentifier: pid)?.activate()
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        handoff = Task {
            var focused = false
            for _ in 0..<25 where !focused {  // nejdéle ~500 ms
                try? await Task.sleep(for: .milliseconds(20))
                if Task.isCancelled || closed { return }
                focused = isFocused
            }
            if focused {
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
            }
            handoff = nil
            update()  // při neúspěchu se zrcadlo vrátí a klik se zahodí
        }
    }

    // MARK: Zrcadlo

    private func makeConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(size.width * scale))
        configuration.height = max(1, Int(size.height * scale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }

    private func startStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if closed { return }
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return onUnpin("Vybrané okno už neexistuje nebo ho nelze zachytit.")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            scale = CGFloat(filter.pointPixelScale)
            let started = size
            let stream = SCStream(filter: filter, configuration: makeConfiguration(), delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await stream.startCapture()
            if closed {  // odepnuto během startu: zastav až teď, po dokončeném startu
                try? stream.removeStreamOutput(self, type: .screen)
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            if size != started { try? await stream.updateConfiguration(makeConfiguration()) }
        } catch {
            if closed { return }
            onUnpin(CGPreflightScreenCaptureAccess()
                ? "Zachytávání okna se nepodařilo spustit."
                : "Impaler nemá oprávnění Nahrávání obrazovky (Nastavení systému › Soukromí a zabezpečení).")
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        MainActor.assumeIsolated { mirror.contentView?.layer?.contents = surface }  // sampleHandlerQueue je .main
    }

    // MARK: Pomocné

    /// Rám AX prvku v CG souřadnicích.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &rect.origin)
        AXValueGetValue(size as! AXValue, .cgSize, &rect.size)
        return rect
    }

    private static func panel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

private class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

private final class BadgeView: ClickView {
    override func draw(_ dirtyRect: NSRect) {
        ("📌" as NSString).draw(in: bounds, withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
    }
}
