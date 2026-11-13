import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var picker: Picker?
    private var pinned: [CGWindowID: PinnedWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Impaler")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        CGRequestScreenCaptureAccess()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Připnout okno", action: #selector(pin), keyEquivalent: "").target = self
        if !pinned.isEmpty {
            menu.addItem(.separator())
            for (id, window) in pinned.sorted(by: { $0.key < $1.key }) {
                let item = menu.addItem(withTitle: window.title, action: #selector(unpinItem), keyEquivalent: "")
                item.target = self
                item.state = .on
                item.tag = Int(id)
            }
            menu.addItem(withTitle: "Odepnout vše", action: #selector(unpinAll), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ukončit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func pin() {
        let panels = pinned.values.reduce(into: [:]) { $0.merge($1.panels) { first, _ in first } }
        picker = Picker(panels: panels) { [weak self] target in
            guard let self else { return }
            self.picker = nil
            guard let target, self.pinned[target.id] == nil else { return }  // už připnuté okno: nic
            let window = PinnedWindow(windowID: target.id, pid: target.pid, bounds: target.bounds) { [weak self] error in
                self?.unpin(target.id)
                if let error { self?.alert(error) }
            }
            self.pinned[target.id] = window
            if window == nil {
                self.alert(AXIsProcessTrusted()
                    ? "Vybrané okno se nepodařilo najít přes rozhraní zpřístupnění."
                    : "Impaler nemá oprávnění Zpřístupnění (Nastavení systému › Soukromí a zabezpečení).")
            }
        }
    }

    private func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate()
        alert.runModal()
    }

    private func unpin(_ id: CGWindowID) {
        pinned.removeValue(forKey: id)?.close()
    }

    @objc private func unpinItem(_ sender: NSMenuItem) {
        unpin(CGWindowID(sender.tag))
    }

    @objc private func unpinAll() {
        pinned.keys.forEach(unpin)
    }
}
