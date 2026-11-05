import AppKit
import SwiftUI
import QuartzCore
import Combine
import AdaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private let filesShortcut = AdaGlobalShortcut(identifier: 2)
    private let media = NowPlayingStore()
    private let loginItem = LoginItemStore()
    private let notifications = FocusNotificationStore()
    private lazy var dashboard = DashboardLayoutStore(initialTiles: model.preferences.initialDashboardTiles)
    private var observations = Set<AnyCancellable>()
    private var activeShortcuts: [ShortcutBinding?] = []
    private let panelController = PanelController()
    private var panel: IslandPanel { panelController.panel }
    private var statusMenu: StatusMenuController!
    private var visible = true
    private var selectedScreen: NSScreen?
    private var lastTargetFrame: NSRect? { panelController.lastTargetFrame }
    private let settingsController = SettingsWindowController()
    private let welcomeController = WelcomeWindowController()
    private let showWelcomeOnLaunch: Bool
    private var settingsWindow: NSWindow? { settingsController.window }
    private var tilePickerWindow: NSWindow?
    private let hover = HoverController()
    private var animatingUntil: Date { panelController.animatingUntil }
    private var layoutTask: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var trackingMenus = Set<ObjectIdentifier>()
    private var terminationFlushInProgress = false
    private var launchReady = false
    private var pendingActivationAction: String?

    init(showWelcomeOnLaunch: Bool) {
        self.showWelcomeOnLaunch = showWelcomeOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        StatusMenuController.installEditingMenu(target: self, panelAction: #selector(togglePanelFromKeyboard),
            settingsAction: #selector(showSettings), quitAction: #selector(quit))
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(externalActivation(_:)),
            name: AppInstanceCoordinator.activationName, object: Bundle.main.bundleIdentifier ?? AdaInstallation.identifier)
        panel.onPrimaryClick = { [weak self] point in self?.openFromNotchClick(at: point, includeCompactPanel: true) ?? false }
        panelController.install(root: IslandView(model: model, workspace: workspace, actions: actions, shelf: shelf, prompter: prompter, assistant: assistant, monitor: monitor, cloud: cloud, awake: awake, dashboard: dashboard, media: media,
            onExpand: { [weak self] page in self?.expand(to: page) },
            onOpenCompact: { [weak self] in self?.openCompactIsland() },
            onSettings: { [weak self] in self?.showSettings() },
            onAddTile: { [weak self] in self?.showDashboardPicker() },
            onChangeTile: { [weak self] tile in self?.showDashboardPicker(replacing: tile.id) },
            onRequestKeyboardFocus: { [weak self] in self?.panel.makeKey() },
            onDismiss: { [weak self] in self?.collapse() }))
        shelf.shareAnchor = panel.contentView
        panel.onFilePaste = { [weak self] in
            guard let self, self.model.expanded, self.model.page == .files else { return false }
            self.shelf.pasteFiles()
            return true
        }
        statusMenu = StatusMenuController { [weak self] menu in self?.populateStatusMenu(menu) }
        model.activities.visibilityChanged = { [weak self] in
            self?.model.objectWillChange.send()
            self?.position(animated: true)
        }
        model.completed = { [weak self] in self?.showCompletion() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuStartedTracking),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuStoppedTracking),
            name: NSMenu.didEndTrackingNotification, object: nil)
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
        hover.monitor.onPointerUpdate = { [weak self] in self?.checkPointer() }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pointer = NSEvent.mouseLocation
                // The system menu bar can receive events in the camera band before
                // our panel does. Observe those clicks without consuming them.
                if event.type == .leftMouseDown, !event.modifierFlags.contains(.control),
                   self.openFromNotchClick(at: pointer, includeCompactPanel: false) {
                    return
                }
                guard !self.pointerNearPanel(pointer),
                      !self.dragInProgress,
                      !self.keepsPanelOpen,
                      !self.model.pinned, self.model.expanded, !self.model.preferences.hoverToOpen else { return }
                self.collapse()
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(panelKeyChanged), name: NSWindow.didBecomeKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(panelKeyChanged), name: NSWindow.didResignKeyNotification, object: panel)
        // Power-state notifications may arrive on a background queue.
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.model.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }.store(in: &observations)
        launchReady = true
        configureFeatures()
        updateScreen()
        checkPointer()
        panel.orderFrontRegardless()
        if CommandLine.arguments.contains("--settings") || pendingActivationAction == "settings" { showSettings() }
        else if CommandLine.arguments.contains("--preview") || pendingActivationAction != nil { openFromShortcut() }
        else if showWelcomeOnLaunch { showWelcome() }
        pendingActivationAction = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        model.save()
        model.shutdown()
        hover.stop()
        actions.shutdown()
        assistant.shutdown()
        monitor.stop()
        media.stop()
        awake.stop()
        shortcut.stop()
        filesShortcut.stop()
        prompter.pause()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    @objc private func externalActivation(_ notification: Notification) {
        guard let pid = notification.userInfo?["targetPID"] as? NSNumber,
              pid.int32Value == ProcessInfo.processInfo.processIdentifier else { return }
        let action = notification.userInfo?["action"] as? String ?? "activate"
        guard launchReady else { pendingActivationAction = action; return }
        NSApp.activate()
        if action == "settings" { showSettings() } else { openFromShortcut() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
        if media.permissionDenied { media.retryPermissions() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing settings or collapsing the island leaves the menu bar app running.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationFlushInProgress else { return .terminateLater }
        terminationFlushInProgress = true
        Task {
            var allow = await workspace.flushNote()
            if !allow {
                let alert = NSAlert()
                alert.messageText = L10n.string("Not kaydedilemedi.")
                alert.informativeText = workspace.noteError ?? ""
                alert.addButton(withTitle: L10n.string("Çıkışı iptal et"))
                alert.addButton(withTitle: L10n.string("Kaydetmeden çık"))
                NSApp.activate()
                allow = alert.runModal() == .alertSecondButtonReturn
            }
            terminationFlushInProgress = false
            sender.reply(toApplicationShouldTerminate: allow)
        }
        return .terminateLater
    }

    private func updateScreen(animated: Bool = false) {
        let builtin = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        })
        selectedScreen = model.preferences.displayChoice == .main ? NSScreen.screens.first : builtin
        selectedScreen = selectedScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = selectedScreen else { return }
        model.availableScreenWidth = screen.frame.width
        let geometry = geometry(on: screen)
        model.menuBarHeight = geometry.menuBarHeight
        model.notchWidth = geometry.notchWidth
        position(animated: animated)
    }

    private func geometry(on screen: NSScreen) -> ScreenGeometry {
        ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                       statusBarHeight: NSStatusBar.system.thickness,
                       auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
    }

    private func position(animated: Bool = false) {
        guard let screen = selectedScreen else { return }
        let frame = geometry(on: screen).panelFrame(size: CGSize(width: model.width, height: model.height),
            attached: model.attached, flushToTop: model.flushToTop, floatingGap: model.preferences.floatingGap)
        panelController.position(frame: frame, attached: model.attached, expanded: model.expanded, animated: animated)
    }

    private func cameraInputFrame(horizontalPadding: CGFloat = 0, below: CGFloat = 0) -> NSRect? {
        guard let screen = selectedScreen else { return nil }
        return geometry(on: screen).cameraInputFrame(attached: model.attached, horizontalPadding: horizontalPadding, below: below)
    }

    private func pointerNearPanel(_ pointer: NSPoint) -> Bool {
        let visibleFrame = model.expanded || model.compactVisible ? (lastTargetFrame ?? panel.frame) : nil
        let target = IslandHoverRegion(panel: visibleFrame, camera: cameraInputFrame(horizontalPadding: 3, below: 8))
        if target.contains(pointer) { return true }
        // A narrowing page may still be under the pointer until its resize ends.
        // When collapsed, only the compact target can reopen the island.
        return model.expanded && Date() < animatingUntil &&
            IslandHoverRegion(panel: panel.frame).contains(pointer)
    }

    private func preferencesChanged() {
        // Coalesce slider changes so editing the panel size stays responsive.
        layoutTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.model.pinned && self.settingsWindow?.isVisible != true { self.expand() }
            self.configureFeatures()
            self.updateScreen(animated: self.model.expanded)
        }
        layoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: task)
    }

    private func configureFeatures() {
        hover.monitor.configure(mode: PointerTrackingPolicy.mode(visible: visible,
            hoverEnabled: model.preferences.hoverToOpen, expanded: model.expanded))
        media.setEnabled(model.preferences.showNowPlaying)
        media.setPanelOpen(visible && model.expanded)
        if model.preferences.monitoringEnabled && visible && model.expanded && model.page == .system {
            if !monitor.sampling { monitor.start() }
        } else if monitor.sampling { monitor.stop() }
        let useShortcuts = model.preferences.globalShortcutEnabled && !model.recordingShortcut
        let keys: [ShortcutBinding?] = useShortcuts
            ? [model.preferences.panelShortcut, model.preferences.filesShortcut] : [nil, nil]
        if activeShortcuts != keys {
            activeShortcuts = keys
            shortcut.stop()
            filesShortcut.stop()
            if let panelKey = keys[0] {
                shortcut.start(binding: panelKey) { [weak self] in self?.togglePanelFromKeyboard() }
            }
            if let filesKey = keys[1] {
                filesShortcut.start(binding: filesKey) { [weak self] in self?.openFromShortcut(to: .files) }
            }
            model.shortcutStatus = [shortcut.errorMessage, filesShortcut.errorMessage].compactMap { $0 }.joined(separator: " ")
        }
    }

    private func openFromShortcut(to page: IslandPage? = nil) {
        // Give keyboard users time to reach the panel from another part of the screen.
        hover.holdOpenUntil = Date().addingTimeInterval(4)
        if let page { model.selectPage(page) }
        expand(to: page)
        hover.keyboardHeld = true
        panel.makeKey()
    }

    @objc private func togglePanelFromKeyboard() {
        if model.expanded { collapse() }
        else { openFromShortcut() }
    }

    @objc private func openAssistant() { openFromShortcut(to: .assistant) }
    @objc private func openSystem() { openFromShortcut(to: .system) }
    @objc private func openCloud() { openFromShortcut(to: .cloud) }

    @objc private func panelKeyChanged() {
        model.panelIsKey = panel.isKeyWindow
        if !panel.isKeyWindow { hover.keyboardHeld = false }
    }

    private func checkPointer() {
        let inside = visible && pointerNearPanel(NSEvent.mouseLocation)
        if model.pointerInside != inside { model.pointerInside = inside }
        hover.checkPointer(blocked: !visible || settingsWindow?.isVisible == true || tilePickerWindow?.isVisible == true || welcomeController.isVisible,
            inside: inside, expanded: model.expanded,
            hoverEnabled: model.preferences.hoverToOpen &&
                (model.preferences.openShelfOnDrag || NSEvent.pressedMouseButtons == 0),
            expand: { [weak self] in self?.expandFromNotch() },
            scheduleCollapse: { [weak self] in self?.scheduleCollapse() })
    }

    private func openFromNotchClick(at point: NSPoint, includeCompactPanel: Bool) -> Bool {
        guard visible, settingsWindow?.isVisible != true, tilePickerWindow?.isVisible != true,
              !welcomeController.isVisible, trackingMenus.isEmpty, !dragInProgress,
              !model.expanded || (model.mediaIsPlaying && model.page != .player) else { return false }

        let clickedCamera = cameraInputFrame()?.contains(point) == true
        let clickedCompact = includeCompactPanel && !model.expanded && model.compactVisible &&
            (lastTargetFrame ?? panel.frame).contains(point)
        guard clickedCamera || clickedCompact else { return false }
        openCompactIsland()
        return true
    }

    private func openCompactIsland() {
        hover.holdOpenUntil = Date().addingTimeInterval(1)
        expandFromNotch()
        panel.makeKey()
    }

    private func expandFromNotch() {
        if model.mediaIsPlaying {
            let returnPage = model.expanded ? nil : startupPage()
            model.openUtility(.player, returningTo: returnPage)
            expand(to: .player)
        } else {
            expand()
        }
    }

    private func startupPage() -> IslandPage {
        switch model.preferences.startupPage {
        case .claude:
            assistant.provider = .claude
            return .assistant
        case .chatGPT:
            assistant.provider = .chatGPT
            return .assistant
        default:
            return IslandPage(rawValue: model.preferences.startupPage.rawValue) ?? .home
        }
    }

    private func expand(to destination: IslandPage? = nil) {
        cancelCollapse()
        if !visible { visible = true; panel.orderFrontRegardless() }
        if let destination {
            model.page = destination
        } else if !model.expanded {
            model.page = startupPage()
        }
        guard !model.expanded else { return }
        model.expanded = true
        configureFeatures()
        panel.orderFrontRegardless()
        position(animated: true)
    }

    private func collapse() {
        guard model.expanded, !dragInProgress else { return }
        cancelCollapse()
        hover.holdOpenUntil = .distantPast
        hover.keyboardHeld = false
        panel.resignKey()
        model.expanded = false
        configureFeatures()
        position(animated: true)
        hover.suppressUntilExit = pointerNearPanel(NSEvent.mouseLocation)
    }

    private var dragInProgress: Bool {
        model.interactionHeld && NSEvent.pressedMouseButtons != 0
    }

    private var isReadingScript: Bool {
        model.page == .prompter && prompter.isPlaying
    }

    private var keepsPanelOpen: Bool {
        isReadingScript || hover.keyboardHeld || model.panelPopoverOpen || (model.page == .home && dashboard.isEditing) || (model.page == .files && shelf.isSharing)
    }

    private var mayAutoCollapse: Bool {
        model.expanded && model.preferences.hoverToOpen && !model.pinned && !keepsPanelOpen &&
        NSEvent.pressedMouseButtons == 0 && trackingMenus.isEmpty &&
        Date() >= hover.holdOpenUntil && Date() >= animatingUntil
    }

    @objc private func menuStartedTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        trackingMenus.insert(ObjectIdentifier(menu))
        cancelCollapse()
    }

    @objc private func menuStoppedTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        trackingMenus.remove(ObjectIdentifier(menu))
    }

    private func cancelCollapse() { hover.cancelCollapse() }

    private func scheduleCollapse() {
        hover.scheduleCollapse(delay: model.preferences.closeDelay, canCollapse: { [weak self] in
            guard let self else { return false }
            return self.mayAutoCollapse && !self.pointerNearPanel(NSEvent.mouseLocation)
        }, collapse: { [weak self] in self?.collapse() })
    }

    @objc private func togglePin() {
        model.pinned.toggle()
        if model.pinned { expand() }
    }

    private func showCompletion() {
        let presentation = FocusCompletionPresentation(islandVisible: visible,
            openPanel: model.preferences.showOnCompletion, notifications: model.preferences.notifyOnCompletion)
        if presentation.shouldNotify {
            let isBreak = model.isBreak
            Task { await notifications.sendCompletion(enabled: true, isBreak: isBreak) }
        }
        guard presentation.shouldOpenPanel else { return }
        hover.holdOpenUntil = Date().addingTimeInterval(6)
        expand()
    }

    @objc private func screenChanged() { updateScreen() }
    @objc private func wokeUp() {
        model.refreshBattery()
        model.activities.completeIfNeeded()
        updateScreen()
    }

    private func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: L10n.string("Ada · Çentik çalışma alanı"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        add(menu, visible ? L10n.string("Adayı gizle") : L10n.string("Adayı göster"), #selector(toggleVisible))
        add(menu, L10n.string("Paneli aç / kapat"), #selector(togglePanelFromKeyboard))
        add(menu, L10n.string("Paneli açık tut"), #selector(togglePin), checked: model.pinned)
        add(menu, L10n.string("Asistan · ChatGPT / Claude"), #selector(openAssistant))
        add(menu, L10n.string("Sistem bilgileri"), #selector(openSystem))
        add(menu, L10n.string("Bulut ve klasörler"), #selector(openCloud))
        add(menu, L10n.string("Ayarlar…"), #selector(showSettings), key: ",")
        menu.addItem(.separator())
        add(menu, model.clock.isRunning ? L10n.string("Odağı duraklat") : L10n.string("Odağı başlat"), #selector(toggleTimer))
        add(menu, L10n.string("Sayacı sıfırla"), #selector(resetTimer))
        add(menu, L10n.string("Bitiş sesi"), #selector(toggleSound), checked: model.soundEnabled)
        if model.activityOptions.countdown {
            if model.activities.deadline == nil {
                add(menu, L10n.string("5 dk geri sayım başlat"), #selector(startCountdown))
            } else {
                add(menu, L10n.string("Geri sayımı durdur"), #selector(stopCountdown))
            }
        }
        menu.addItem(.separator())
        add(menu, L10n.string("Ada hakkında"), #selector(about))
        add(menu, L10n.string("Ada’dan çık"), #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     checked: Bool = false, key: String = "") {
        statusMenu.add(to: menu, title: title, action: action, target: self, checked: checked, key: key)
    }

    private func showWelcome() {
        collapse()
        welcomeController.show(textScale: model.preferences.textScale,
            shortcut: model.preferences.globalShortcutEnabled ? model.preferences.panelShortcut.title : nil)
        WelcomePresentation.recordPresentation(defaults: .standard)
    }

    @objc private func showSettings() {
        loginItem.refresh()
        settingsController.prepare {
            SettingsView(model: model, shelf: shelf, dashboard: dashboard, workspace: workspace, loginItem: loginItem, notifications: notifications, assistant: assistant, preview: { [weak self] in
                self?.expand()
                self?.hover.holdOpenUntil = Date().addingTimeInterval(4)
            }, customizeDashboard: { [weak self] in
                guard let self else { return }
                self.settingsWindow?.close()
                self.dashboard.isEditing = true
                self.openFromShortcut(to: .home)
            }, addTile: { [weak self] in self?.showDashboardPicker() }, showWelcome: { [weak self] in
                self?.showWelcome()
            })
        }
        collapse()
        settingsController.show()
    }

    private func showDashboardPicker(replacing identifier: UUID? = nil) {
        if identifier == nil && dashboard.tiles.count >= DashboardLayoutStore.maxTiles { return }
        tilePickerWindow?.close()
        collapse()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = identifier == nil ? L10n.string("Ada · Kutucuk ekle") : L10n.string("Ada · Kutucuğu değiştir")
        window.isReleasedWhenClosed = false
        var selectionApplied = false
        window.contentView = NSHostingView(rootView: DashboardTilePicker(
            title: identifier == nil ? L10n.string("Ne eklemek istersin?") : L10n.string("Bu kutucukta ne olsun?"),
            onCancel: { [weak self] in self?.tilePickerWindow?.close() }
        ) { [weak self] tile in
            guard let self, !selectionApplied else { return }
            selectionApplied = true
            var tile = tile
            if tile.kind == .app {
                if tile.appBundleID == MediaSource.spotify.bundleIdentifier { tile.kind = .spotify }
                if tile.appBundleID == MediaSource.appleMusic.bundleIdentifier { tile.kind = .appleMusic }
            }
            let saved = identifier.map { self.dashboard.replace(id: $0, with: tile) } ?? self.dashboard.add(tile)
            guard saved else { selectionApplied = false; return }
            self.dashboard.isEditing = false
            self.tilePickerWindow?.close()
            self.configureFeatures()
            self.openFromShortcut(to: .home)
        }.environment(\.adaTextScale, model.preferences.textScale).adaFont().tint(model.accentColor).accentColor(model.accentColor))
        window.center()
        tilePickerWindow = window
        NSApp.activate()
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
    @objc private func toggleSound() { model.soundEnabled.toggle() }
    @objc private func startCountdown() { model.activities.startCountdown(minutes: 5) }
    @objc private func stopCountdown() { model.activities.cancelCountdown() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = L10n.string("Ada \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        alert.informativeText = L10n.string("Çentiğinde küçük bir çalışma alanı.\n\nAna: notlar, görevler, pil ve odak\nDosyalar: bırak, aç veya dışarı sürükle\nMenü: asistan, donanım, bulut ve araçlar\nMetin: kameranın altında teleprompter\n\nAyarlar’dan boyutu, kartları, temayı ve davranışı değiştirebilirsin.")
        alert.informativeText += "\n\n" + L10n.string("Ada bağımsız bir projedir; Apple, Spotify, OpenAI veya Anthropic ile bağlantılı değildir. Ticari markalar ilgili sahiplerine aittir.")
        alert.addButton(withTitle: L10n.string("Tamam"))
        NSApp.activate()
        alert.runModal()
    }
}
