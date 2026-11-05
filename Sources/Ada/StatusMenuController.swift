import AdaCore
import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let update: (NSMenu) -> Void
    init(update: @escaping (NSMenu) -> Void) {
        self.update = update
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Ada")
        item.button?.toolTip = L10n.string("Ada · Çentik çalışma alanı")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) { update(menu) }
    func add(to menu: NSMenu, title: String, action: Selector, target: AnyObject, checked: Bool, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target; item.state = checked ? .on : .off; menu.addItem(item)
    }
    static func installEditingMenu(target: AnyObject, panelAction: Selector, settingsAction: Selector, quitAction: Selector) {
        // Accessory apps still need a standard Edit menu for text responder shortcuts.
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Ada")
        let panelItem = NSMenuItem(title: L10n.string("Paneli aç / kapat"), action: panelAction, keyEquivalent: "")
        panelItem.target = target
        appMenu.addItem(panelItem)
        let settingsItem = NSMenuItem(title: L10n.string("Ayarlar…"), action: settingsAction, keyEquivalent: ",")
        settingsItem.target = target
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.string("Ada’dan çık"), action: quitAction, keyEquivalent: "q")
        quitItem.target = target
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.string("Düzenle"))
        let commands: [(String, Selector, String)] = [
            (L10n.string("Geri al"), Selector(("undo:")), "z"),
            (L10n.string("Kes"), #selector(NSText.cut(_:)), "x"),
            (L10n.string("Kopyala"), #selector(NSText.copy(_:)), "c"),
            (L10n.string("Yapıştır"), #selector(NSText.paste(_:)), "v"),
            (L10n.string("Tümünü seç"), #selector(NSText.selectAll(_:)), "a")
        ]
        for (title, selector, key) in commands {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        editItem.submenu = edit
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

}
