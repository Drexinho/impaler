import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let unpinItem = NSMenuItem(title: "Odepnout", action: #selector(unpin), keyEquivalent: "")
    private var picker: Picker?
    private var pinned: PinnedWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Impaler")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Připnout okno", action: #selector(pin), keyEquivalent: "").target = self
        unpinItem.target = self
        menu.addItem(unpinItem)
        menu.addItem(withTitle: "Ukončit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        CGRequestScreenCaptureAccess()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        unpinItem.isHidden = pinned == nil
    }

    @objc private func pin() {
        picker = Picker { [weak self] target in
            guard let self else { return }
            self.picker = nil
            guard let target else { return }
            self.unpin()
            self.pinned = PinnedWindow(windowID: target.id, pid: target.pid, bounds: target.bounds) { [weak self] error in
                self?.unpin()
                if let error { self?.alert(error) }
            }
            if self.pinned == nil {
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

    @objc private func unpin() {
        pinned?.close()
        pinned = nil
    }
}
