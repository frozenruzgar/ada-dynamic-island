import AppKit
import SwiftUI
import QuartzCore
import Combine

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var usesFullScreenFrame = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The controller already fits the flush frame to the display. Do not
        // constrain it again to the work area beneath the menu bar.
        usesFullScreenFrame ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = IslandModel()
    private let workspace = WorkspaceStore()
    private let actions = QuickActionStore()
    private let shelf = ShelfStore.shared
    private let prompter = PrompterStore()
    private let assistant = AssistantStore()
    private let monitor = SystemMonitor(startImmediately: false)
    private let cloud = CloudWorkspaceStore()
    private let awake = AwakeStore()
    private let shortcut = AdaGlobalShortcut()
    private let media = NowPlayingStore()
    private let loginItem = LoginItemStore()
    private lazy var dashboard = DashboardLayoutStore(initialTiles: model.preferences.initialDashboardTiles)
    private var observations = Set<AnyCancellable>()
    private var shortcutEnabled: Bool?
    private var panel: IslandPanel!
    private var statusItem: NSStatusItem!
    private var collapseTask: DispatchWorkItem?
    private var holdOpenUntil = Date.distantPast
    private var suppressHoverUntilExit = false
    private var visible = true
    private var selectedScreen: NSScreen?
    private var lastTargetFrame: NSRect?
    private var settingsWindow: NSWindow?
    private var tilePickerWindow: NSWindow?
    private var pointerTimer: Timer?
    private var animatingUntil = Date.distantPast
    private var layoutTask: DispatchWorkItem?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditingMenu()
        // Avoid two independent islands when the user opens another copy of the app.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil)
            return
        }
        panel = IslandPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        // Place the island below system menu titles and status items.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: IslandView(model: model, workspace: workspace, actions: actions, shelf: shelf, prompter: prompter, assistant: assistant, monitor: monitor, cloud: cloud, awake: awake, dashboard: dashboard, media: media,
            onExpand: { [weak self] page in self?.expand(to: page) },
            onSettings: { [weak self] in self?.showSettings() },
            onAddTile: { [weak self] in self?.showDashboardPicker() },
            onChangeTile: { [weak self] tile in self?.showDashboardPicker(replacing: tile.id) }))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Ada")
        statusItem.button?.toolTip = "Ada · Çentik çalışma alanı"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        model.completed = { [weak self] in self?.showCompletion() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp),
            name: NSWorkspace.didWakeNotification, object: nil)
        model.layoutChanged = { [weak self] in self?.preferencesChanged() }
        dashboard.objectWillChange.sink { [weak self] _ in self?.preferencesChanged() }.store(in: &observations)
        media.$track.sink { [weak self] track in
            guard let self else { return }
            let playing = self.model.preferences.showNowPlaying && track?.isPlaying == true
            if self.model.mediaIsPlaying != playing {
                self.model.mediaIsPlaying = playing
                self.position(animated: true)
            }
        }.store(in: &observations)
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        if let pointerTimer {
            pointerTimer.tolerance = 0.012
            RunLoop.main.add(pointerTimer, forMode: .common)
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.frame.contains(NSEvent.mouseLocation),
                      !self.dragInProgress,
                      !self.model.pinned, self.model.expanded, !self.model.preferences.hoverToOpen else { return }
                self.collapse()
            }
        }
        configureFeatures()
        updateScreen()
        panel.orderFrontRegardless()
        if CommandLine.arguments.contains("--preview") { expand() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.save()
        actions.shutdown()
        assistant.shutdown()
        monitor.stop()
        media.stop()
        awake.stop()
        shortcut.stop()
        prompter.pause()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
        if media.permissionDenied { media.retryPermissions() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing settings or collapsing the island leaves the menu bar app running.
        false
    }

    private func installEditingMenu() {
        // Accessory apps still need a standard Edit menu for text responder shortcuts.
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Ada")
        let panelItem = NSMenuItem(title: "Paneli aç / kapat", action: #selector(togglePanelFromKeyboard), keyEquivalent: "a")
        panelItem.keyEquivalentModifierMask = [.control, .option]
        panelItem.target = self
        appMenu.addItem(panelItem)
        let settingsItem = NSMenuItem(title: "Ayarlar…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Ada’dan çık", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Düzenle")
        let commands: [(String, Selector, String)] = [
            ("Geri al", Selector(("undo:")), "z"),
            ("Kes", #selector(NSText.cut(_:)), "x"),
            ("Kopyala", #selector(NSText.copy(_:)), "c"),
            ("Yapıştır", #selector(NSText.paste(_:)), "v"),
            ("Tümünü seç", #selector(NSText.selectAll(_:)), "a")
        ]
        for (title, selector, key) in commands {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        editItem.submenu = edit
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    private func updateScreen() {
        let builtin = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        })
        selectedScreen = model.preferences.displayChoice == "main" ? NSScreen.screens.first : builtin
        selectedScreen = selectedScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = selectedScreen else { return }
        model.availableScreenWidth = screen.frame.width
        model.menuBarHeight = screen.frame.maxY - menuBottom(on: screen)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            model.notchWidth = max(0, right.minX - left.maxX)
        } else {
            model.notchWidth = 0
        }
        position()
    }

    private func position(animated: Bool = false) {
        guard let screen = selectedScreen else { return }
        panel.usesFullScreenFrame = model.attached
        let top = panelTop(on: screen)
        let frame = NSRect(x: cameraCenterX(on: screen) - model.width / 2,
                           y: top - model.height,
                           width: model.width, height: model.height)
        // Page changes can trigger a queued layout while the window is resizing.
        guard frame != lastTargetFrame else { return }
        lastTargetFrame = frame
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate {
            let duration = model.expanded ? 0.42 : 0.38
            animatingUntil = Date().addingTimeInterval(duration)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.28, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
    }

    private func menuBottom(on screen: NSScreen) -> CGFloat {
        min(screen.visibleFrame.maxY,
            screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
    }

    private func panelTop(on screen: NSScreen) -> CGFloat {
        if model.flushToTop { return screen.frame.maxY }
        return menuBottom(on: screen) - (model.attached ? 2 : model.preferences.floatingGap)
    }

    private func cameraCenterX(on screen: NSScreen) -> CGFloat {
        if model.attached, let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }

    private func pointerInNotch(_ pointer: NSPoint) -> Bool {
        guard model.attached, let screen = selectedScreen else { return false }
        let center = cameraCenterX(on: screen)
        // The cursor can sit exactly at maxY. CGRect.contains excludes that edge.
        return abs(pointer.x - center) <= model.notchWidth / 2 + 3 &&
            pointer.y >= menuBottom(on: screen) - 8 &&
            pointer.y <= screen.frame.maxY + 0.5
    }

    private func pointerNearPanel(_ pointer: NSPoint) -> Bool {
        if pointerInNotch(pointer) { return true }
        if model.mediaIsPlaying && !model.expanded {
            let bounds = panel.frame.insetBy(dx: -3, dy: -3)
            return pointer.x >= bounds.minX && pointer.x <= bounds.maxX &&
                pointer.y >= bounds.minY && pointer.y <= bounds.maxY + 0.5
        }
        if model.flushToTop, let screen = selectedScreen, pointer.y >= menuBottom(on: screen) {
            return false
        }
        return panel.frame.insetBy(dx: -4, dy: -4).contains(pointer)
    }

    private func preferencesChanged() {
        // Coalesce slider changes so editing the panel size stays responsive.
        layoutTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.model.pinned && self.settingsWindow?.isVisible != true { self.expand() }
            self.configureFeatures()
            self.updateScreen()
        }
        layoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: task)
    }

    private func configureFeatures() {
        let hasMediaTile = dashboard.tiles.contains { $0.kind == .spotify || $0.kind == .appleMusic }
        media.setEnabled(model.preferences.showNowPlaying && hasMediaTile)
        if model.preferences.monitoringEnabled && visible && model.expanded && model.page == .system {
            if !monitor.sampling { monitor.start() }
        } else if monitor.sampling { monitor.stop() }
        if shortcutEnabled != model.preferences.globalShortcutEnabled {
            shortcutEnabled = model.preferences.globalShortcutEnabled
            if model.preferences.globalShortcutEnabled {
                shortcut.start { [weak self] in self?.togglePanelFromKeyboard() }
            } else { shortcut.stop() }
            model.shortcutStatus = shortcut.statusDescription
        }
    }

    private func openFromShortcut(to page: IslandPage? = nil) {
        // Give keyboard users time to reach the panel from another part of the screen.
        holdOpenUntil = Date().addingTimeInterval(4)
        if let page { model.selectPage(page) }
        expand(to: page)
        panel.makeKey()
    }

    @objc private func togglePanelFromKeyboard() {
        guard model.preferences.globalShortcutEnabled else { return }
        if model.expanded { collapse() }
        else { openFromShortcut() }
    }

    @objc private func openAssistant() { openFromShortcut(to: .assistant) }
    @objc private func openSystem() { openFromShortcut(to: .system) }
    @objc private func openCloud() { openFromShortcut(to: .cloud) }

    private func checkPointer() {
        guard visible, Date() >= animatingUntil else { return }
        if pointerNearPanel(NSEvent.mouseLocation) {
            cancelCollapse()
            if model.expanded { holdOpenUntil = .distantPast }
            if !model.expanded && model.preferences.hoverToOpen && !suppressHoverUntilExit {
                expand()
            }
        } else {
            suppressHoverUntilExit = false
            scheduleCollapse()
        }
    }

    private func expand(to destination: IslandPage? = nil) {
        cancelCollapse()
        if !visible { visible = true; panel.orderFrontRegardless() }
        if let destination {
            model.page = destination
        } else if !model.expanded {
            switch model.preferences.startupPage {
            case "claude":
                assistant.provider = .claude
                model.page = .assistant
            case "chatGPT":
                assistant.provider = .chatGPT
                model.page = .assistant
            default:
                model.page = IslandPage(rawValue: model.preferences.startupPage) ?? .home
            }
        }
        guard !model.expanded else { return }
        model.expanded = true
        configureFeatures()
        position(animated: true)
    }

    private func collapse() {
        guard model.expanded, !dragInProgress else { return }
        cancelCollapse()
        suppressHoverUntilExit = pointerInNotch(NSEvent.mouseLocation)
        holdOpenUntil = .distantPast
        panel.resignKey()
        model.expanded = false
        configureFeatures()
        position(animated: true)
    }

    private var dragInProgress: Bool {
        model.interactionHeld && NSEvent.pressedMouseButtons != 0
    }

    private var mayAutoCollapse: Bool {
        model.expanded && model.preferences.hoverToOpen && !model.pinned &&
        !dragInProgress && Date() >= holdOpenUntil
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func scheduleCollapse() {
        guard mayAutoCollapse, collapseTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseTask = nil
            guard self.mayAutoCollapse,
                  !self.pointerNearPanel(NSEvent.mouseLocation) else { return }
            self.collapse()
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + model.preferences.closeDelay, execute: task)
    }

    @objc private func togglePin() {
        model.pinned.toggle()
        if model.pinned { expand() }
    }

    private func showCompletion() {
        guard visible, model.preferences.showOnCompletion else { return }
        holdOpenUntil = Date().addingTimeInterval(6)
        expand()
    }

    @objc private func screenChanged() { updateScreen() }
    @objc private func wokeUp() { model.refreshBattery(); updateScreen() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Ada · Çentik çalışma alanı", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        add(menu, visible ? "Adayı gizle" : "Adayı göster", #selector(toggleVisible))
        add(menu, "Paneli açık tut", #selector(togglePin), checked: model.pinned)
        add(menu, "Asistan · ChatGPT / Claude", #selector(openAssistant))
        add(menu, "Sistem bilgileri", #selector(openSystem))
        add(menu, "Bulut ve klasörler", #selector(openCloud))
        add(menu, "Ayarlar…", #selector(showSettings), key: ",")
        menu.addItem(.separator())
        add(menu, model.clock.isRunning ? "Odağı duraklat" : "Odağı başlat", #selector(toggleTimer))
        add(menu, "Sayacı sıfırla", #selector(resetTimer))
        add(menu, "Bitiş sesi", #selector(toggleSound), checked: model.soundEnabled)
        menu.addItem(.separator())
        add(menu, "Ada hakkında", #selector(about))
        add(menu, "Ada’dan çık", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     checked: Bool = false, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    @objc private func showSettings() {
        loginItem.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Ada Ayarları"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, shelf: shelf, dashboard: dashboard, loginItem: loginItem, preview: { [weak self] in
                self?.expand()
                self?.holdOpenUntil = Date().addingTimeInterval(4)
            }, customizeDashboard: { [weak self] in
                guard let self else { return }
                self.settingsWindow?.close()
                self.dashboard.isEditing = true
                self.openFromShortcut(to: .home)
            }, addTile: { [weak self] in self?.showDashboardPicker() }))
            window.center()
            settingsWindow = window
        }
        collapse()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showDashboardPicker(replacing identifier: UUID? = nil) {
        if identifier == nil && dashboard.tiles.count >= DashboardLayoutStore.maxTiles { return }
        tilePickerWindow?.close()
        collapse()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = identifier == nil ? "Ada · Kutucuk ekle" : "Ada · Kutucuğu değiştir"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DashboardTilePicker(
            title: identifier == nil ? "Ne eklemek istersin?" : "Bu kutucukta ne olsun?",
            onCancel: { [weak self] in self?.tilePickerWindow?.close() }
        ) { [weak self] tile in
            guard let self else { return }
            var tile = tile
            if tile.kind == .app {
                if tile.appBundleID == MediaSource.spotify.bundleIdentifier { tile.kind = .spotify }
                if tile.appBundleID == MediaSource.appleMusic.bundleIdentifier { tile.kind = .appleMusic }
            }
            let saved = identifier.map { self.dashboard.replace(id: $0, with: tile) } ?? self.dashboard.add(tile)
            guard saved else { return }
            self.tilePickerWindow?.close()
            self.configureFeatures()
            self.openFromShortcut(to: .home)
        }.tint(model.accentColor).accentColor(model.accentColor))
        window.center()
        tilePickerWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleVisible() {
        visible.toggle()
        cancelCollapse()
        if visible { updateScreen(); panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
        configureFeatures()
    }
    @objc private func toggleTimer() { model.toggleTimer() }
    @objc private func resetTimer() { model.reset() }
    @objc private func toggleSound() { model.soundEnabled.toggle(); model.save() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Ada \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        alert.informativeText = "Çentiğinde küçük bir çalışma alanı.\n\nAna: notlar, görevler, pil ve odak\nDosyalar: bırak, aç veya dışarı sürükle\nMenü: asistan, donanım, bulut ve araçlar\nMetin: kameranın altında teleprompter\n\nAyarlar’dan boyutu, kartları, temayı ve davranışı değiştirebilirsin."
        alert.addButton(withTitle: "Tamam")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
