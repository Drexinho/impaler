import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var picker: Picker?
    private var pinned: [PinnedWindow] = []  // v pořadí priority: první je nejvíc v popředí

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
            for (index, window) in pinned.enumerated() {
                let submenu = NSMenu()
                // Položka bez akce je zakázaná (krajní posuny).
                for (title, action) in [("Posunout nahoru", index > 0 ? #selector(moveUp) : nil),
                                        ("Posunout dolů", index < pinned.count - 1 ? #selector(moveDown) : nil),
                                        ("Odepnout", #selector(unpinItem))] {
                    let item = submenu.addItem(withTitle: title, action: action, keyEquivalent: "")
                    item.target = self
                    item.tag = Int(window.windowID)
                }
                let item = menu.addItem(withTitle: window.title, action: nil, keyEquivalent: "")
                item.state = .on
                item.submenu = submenu
            }
            menu.addItem(withTitle: "Odepnout vše", action: #selector(unpinAll), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let badge = NSMenu()
        let show = badge.addItem(withTitle: "Zobrazovat", action: #selector(toggleBadge), keyEquivalent: "")
        show.target = self
        show.state = BadgeSettings.hidden ? .off : .on
        for (titles, action, current) in [(["Vpravo nahoře", "Uprostřed nahoře", "Vlevo nahoře"], #selector(setBadgePosition), BadgeSettings.position),
                                          (["Červený", "Bílý", "Černý"], #selector(setBadgeColor), BadgeSettings.color)] {
            badge.addItem(.separator())
            for (tag, title) in titles.enumerated() {
                let item = badge.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
                item.tag = tag
                item.state = tag == current ? .on : .off
            }
        }
        menu.addItem(withTitle: "Odznak", action: nil, keyEquivalent: "").submenu = badge
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ukončit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func pin() {
        let panels = pinned.reduce(into: [:]) { $0.merge($1.panels) { first, _ in first } }
        picker = Picker(panels: panels) { [weak self] target in
            guard let self else { return }
            self.picker = nil
            guard let target, self.index(of: target.id) == nil else { return }  // už připnuté okno: nic
            let window = PinnedWindow(windowID: target.id, pid: target.pid, bounds: target.bounds) { [weak self] in
                self?.restack()
            } onUnpin: { [weak self] error in
                self?.unpin(target.id)
                if let error { self?.alert(error) }
            }
            if let window {
                self.pinned.insert(window, at: 0)  // nové okno má nejvyšší prioritu
                self.restack()
            } else {
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

    private func index(of id: CGWindowID) -> Int? {
        pinned.firstIndex { $0.windowID == id }
    }

    /// Vrstvení podle priority: od nejnižší po nejvyšší dá dopředu zrcadlo a nad něj jeho odznak.
    private func restack() {
        pinned.reversed().forEach { $0.raise() }
    }

    @objc private func toggleBadge() {
        BadgeSettings.hidden.toggle()
        applyBadge()
    }

    @objc private func setBadgePosition(_ sender: NSMenuItem) {
        BadgeSettings.position = sender.tag
        applyBadge()
    }

    @objc private func setBadgeColor(_ sender: NSMenuItem) {
        BadgeSettings.color = sender.tag
        applyBadge()
    }

    /// Změna nastavení odznaku se hned projeví u všech připnutých oken.
    private func applyBadge() {
        pinned.forEach { $0.badgeChanged() }
        restack()
    }

    private func move(_ sender: NSMenuItem, by delta: Int) {
        guard let index = index(of: CGWindowID(sender.tag)), pinned.indices.contains(index + delta) else { return }
        pinned.swapAt(index, index + delta)
        restack()
    }

    @objc private func moveUp(_ sender: NSMenuItem) { move(sender, by: -1) }
    @objc private func moveDown(_ sender: NSMenuItem) { move(sender, by: 1) }

    private func unpin(_ id: CGWindowID) {
        guard let index = index(of: id) else { return }
        pinned.remove(at: index).close()
        restack()
    }

    @objc private func unpinItem(_ sender: NSMenuItem) {
        unpin(CGWindowID(sender.tag))
    }

    @objc private func unpinAll() {
        pinned.forEach { $0.close() }
        pinned = []
    }
}
