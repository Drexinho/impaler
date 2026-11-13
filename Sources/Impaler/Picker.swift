import AppKit

/// Výběr okna: průhledná vrstva na každé obrazovce, modrý rámeček kolem okna pod kurzorem.
@MainActor
final class Picker {
    typealias Target = (id: CGWindowID, pid: pid_t, bounds: CGRect)  // bounds v CG souřadnicích

    private var windows: [NSWindow] = []
    private var escMonitor: Any?
    private var target: Target?
    private let done: (Target?) -> Void

    init(done: @escaping (Target?) -> Void) {
        self.done = done
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor(white: 0, alpha: 0.05)  // ne zcela průhledné, jinak by kliky propadly
            window.isReleasedWhenClosed = false
            let view = OverlayView()
            view.picker = self
            view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: view))
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSApp.activate()
        // Kdyby se aktivace nepovedla, Esc dorazí aspoň přes globální monitor.
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(pick: false) }
        }
        hover()
    }

    func hover() {
        let mouse = NSEvent.mouseLocation
        let height = NSScreen.screens[0].frame.height  // CG má počátek vlevo nahoře na primární obrazovce
        let point = CGPoint(x: mouse.x, y: height - mouse.y)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        target = nil
        for info in list {  // seznam je seřazen odshora dolů
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.contains(point) else { continue }
            target = (id, pid, bounds)
            break
        }
        let rect = target.map { CGRect(x: $0.bounds.minX, y: height - $0.bounds.maxY, width: $0.bounds.width, height: $0.bounds.height) }
        for window in windows {
            (window.contentView as? OverlayView)?.highlight = rect?.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        }
    }

    func finish(pick: Bool) {
        guard !windows.isEmpty else { return }
        if pick { hover() }
        escMonitor.map(NSEvent.removeMonitor)
        windows.forEach { $0.orderOut(nil) }
        windows = []
        done(pick ? target : nil)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    weak var picker: Picker?
    var highlight: CGRect? { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { picker?.hover() }
    override func mouseDown(with event: NSEvent) { picker?.finish(pick: true) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { picker?.finish(pick: false) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlight else { return }
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: highlight.insetBy(dx: 2, dy: 2))
        path.lineWidth = 4
        path.stroke()
    }
}
