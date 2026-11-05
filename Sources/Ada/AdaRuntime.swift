import AppKit

public func runAda() {
    if CommandLine.arguments.contains("--check-localization") {
        let english = L10n.string("Ana ekran", language: "en")
        let turkish = L10n.string("Ana ekran", language: "tr")
        guard english == "Home", turkish == "Ana ekran",
              let resources = Bundle.main.resourceURL,
              L10n.resources.bundleURL.path.hasPrefix(resources.path + "/") else {
            FileHandle.standardError.write(Data("Packaged localization validation failed.\n".utf8))
            exit(1)
        }
        print("PASS: packaged TR/EN resources: \(L10n.resources.bundleURL.path)")
        exit(0)
    }

    MainActor.assumeIsolated {
        let app = NSApplication.shared
        guard let instanceLock = AppInstanceCoordinator.prepare() else { exit(0) }
        let storage = AdaInstallation.storage
        do {
            try AdaInstallation.migrate(defaults: .standard,
                legacyValues: UserDefaults.standard.persistentDomain(forName: AdaInstallation.legacyIdentifier) ?? [:],
                parent: AdaInstallation.supportParent)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = L10n.string("Ada verilerini taşıyamadı. Sonraki açılışta tekrar deneyecek.")
            app.setActivationPolicy(.accessory)
            app.activate()
            alert.runModal()
            exit(1)
        }
        let showWelcome = WelcomePresentation.shouldShowOnLaunch(defaults: .standard, storage: storage)
        let delegate = AppDelegate(showWelcomeOnLaunch: showWelcome)
        app.delegate = delegate
        withExtendedLifetime((delegate, instanceLock)) { app.run() }
    }

}
