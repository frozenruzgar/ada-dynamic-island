import AdaCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var dashboard: DashboardLayoutStore
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var loginItem: LoginItemStore
    @ObservedObject var notifications: FocusNotificationStore
    @ObservedObject var assistant: AssistantStore
    var preview: () -> Void
    var customizeDashboard: () -> Void
    var addTile: () -> Void
    var showWelcome: () -> Void
    @State private var section = 0
    @State private var confirmSessionClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Ada · Senin çalışma alanın")).adaFont(size: 21, weight: .semibold)
                    Text(L10n.string("Değişiklikler adaya anında uygulanır.")).adaFont(size: 12).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.string("Paneli göster"), action: preview)
            }.padding(24)
            Picker(L10n.string("Ayar bölümü"), selection: $section) {
                Text(L10n.string("Görünüm")).tag(0)
                Text(L10n.string("Ana ekran")).tag(1)
                Text(L10n.string("Davranış")).tag(2)
                Text(L10n.string("Odak")).tag(3)
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 8)
            Form {
                switch section {
                case 1: contentSettings
                case 2: behaviorSettings
                case 3: focusSettings
                default: appearanceSettings
                }
            }.formStyle(.grouped)
            if !model.preferences.supportsPersistence {
                Text(L10n.string("Ayarlar daha yeni bir Ada sürümüne ait. Bu sürümdeki değişiklikler kaydedilmeyecek."))
                    .adaFont(size: 10).foregroundStyle(.orange).padding(.horizontal, 24)
            }
            HStack {
                Text(L10n.string("Ada \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"))
                    .adaFont(size: Typography.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("Görünümü sıfırla")) { model.preferences.resetAppearance() }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: SettingsWindowLayout.contentSize.width, height: SettingsWindowLayout.contentSize.height)
        .buttonStyle(IslandButtonStyle(bordered: true))
        .environment(\.adaTextScale, model.preferences.textScale)
        .adaFont()
        .tint(model.accentColor)
        .onChange(of: model.pinned) { _, _ in model.layoutChanged?() }
    }

    @ViewBuilder private var appearanceSettings: some View {
        Section(L10n.string("Açılış ekranı")) {
            optionPicker(L10n.string("Ada açıldığında"), selection: $model.preferences.startupPage, label: { $0.title })
            Text(L10n.string("Menüden bölüm seçtiğinde Ada o bölümü hatırlar."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("Yerleşim ve boyut")) {
            optionPicker(L10n.string("Yerleşim"), selection: $model.preferences.style, label: { $0.title })
            HStack {
                Text(L10n.string("Hazır boyut"))
                Spacer()
                ForEach([620, 660, 760], id: \.self) { width in
                    Button(L10n.string("\(width) pt")) { model.preferences.expandedWidth = Double(width) }
                        .tint(model.preferences.expandedWidth == Double(width) ? model.accentColor : .secondary)
                }
            }
            metric(L10n.string("Panel genişliği"), value: $model.preferences.expandedWidth, range: 620...880)
            if model.preferences.style == .notch {
                Text(L10n.string("Panelin üst kenarı ekranın üstüne oturur."))
                    .adaFont(size: Typography.caption).foregroundStyle(.secondary)
            }
            metric(L10n.string("İçerik yüksekliği"), value: $model.preferences.contentHeight, range: 210...340)
            if model.preferences.style == .floating {
                metric(L10n.string("Üstten uzaklık"), value: $model.preferences.floatingGap, range: 0...40)
            }
        }
        Section(L10n.string("Tema ve kartlar")) {
            optionPicker(L10n.string("Panel teması"), selection: $model.preferences.palette, label: { $0.title })
            optionPicker(L10n.string("Arka plan hareketi"), selection: $model.preferences.backgroundMotion, label: { $0.title })
            optionPicker(L10n.string("Vurgu rengi"), selection: $model.preferences.accent, label: { $0.title })
            metric(model.preferences.usesNebulaPalette ? L10n.string("Renk yoğunluğu") : L10n.string("Cam tonu"),
                   value: $model.preferences.panelOpacity, range: 0.30...0.95, step: 0.01, percentage: true)
            metric(L10n.string("Kart görünürlüğü"), value: $model.preferences.cardOpacity, range: 0.05...0.3, step: 0.01, percentage: true)
            metric(L10n.string("Kart köşe yuvarlaklığı"), value: $model.preferences.cardRadius, range: 10...28)
            metric(L10n.string("Yazı boyutu"), value: $model.preferences.textScale, range: 0.9...1.15, step: 0.05, percentage: true)
        }
    }

    @ViewBuilder private var contentSettings: some View {
        Section(L10n.string("Kutucuklar")) {
            Text(L10n.string("\(dashboard.tiles.count) / \(DashboardLayoutStore.maxTiles) kutucuk"))
            HStack {
                Button(L10n.string("Kutucuk ekle"), action: addTile)
                    .disabled(dashboard.tiles.count >= DashboardLayoutStore.maxTiles)
                Button(L10n.string("Ana ekranı düzenle"), action: customizeDashboard)
            }
            Text(L10n.string("Ana ekrandaki + ile ekle; Düzenle ile değiştir, sırala veya kaldır."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("Müzik")) {
            Toggle(L10n.string("Çalan parçayı adada göster"), isOn: $model.preferences.showNowPlaying)
            Text(L10n.string("Spotify veya Apple Müzik kutucuğu eklediğinde etkinleşir."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("Dosya rafı")) {
            Toggle(L10n.string("Dosya sürüklerken rafı aç"), isOn: $model.preferences.openShelfOnDrag)
            Picker(L10n.string("Raf boyut sınırı"), selection: $shelf.maximumBytes) {
                Text(L10n.string("Sınır yok")).tag(Int64(0))
                Text(L10n.string("2 GB")).tag(Int64(2_000_000_000))
                Text(L10n.string("5 GB")).tag(Int64(5_000_000_000))
                Text(L10n.string("10 GB")).tag(Int64(10_000_000_000))
            }
            Text(L10n.string("Raf toplamı 2 GB’ı aşacaksa kopyalamadan önce onay istenir."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
            Picker(L10n.string("Kopyaları saklama süresi"), selection: $shelf.retentionDays) {
                Text(L10n.string("1 gün")).tag(1); Text(L10n.string("2 gün")).tag(2); Text(L10n.string("3 gün")).tag(3)
                Text(L10n.string("1 hafta")).tag(7); Text(L10n.string("Ben kaldırana kadar")).tag(0)
            }
            Text(L10n.string("Dosya rafı orijinallerin yerine kendi kopyalarını kullanır.")).adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("Yerel araçlar")) {
            Text(L10n.string("Ses dosyaları için Yerel müzik, kamera önizlemesi için Ayna kutucuğunu ekle."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var behaviorSettings: some View {
        Section(L10n.string("Başlangıç")) {
            Button(L10n.string("Başlangıç rehberini aç"), action: showWelcome)
            Toggle(L10n.string("Mac açıldığında başlat"), isOn: Binding(
                get: { loginItem.enabled },
                set: { loginItem.setEnabled($0) }
            )).disabled(loginItem.isBusy)
            if let message = loginItem.statusMessage {
                Text(message).adaFont(size: Typography.caption).foregroundStyle(.secondary)
            }
            if loginItem.requiresApproval {
                Button(L10n.string("macOS ayarlarını aç"), action: loginItem.openSettings)
            }
        }
        Section(L10n.string("Açılma ve kapanma")) {
            Toggle(L10n.string("Üzerine gelince aç ve uzaklaşınca kapat"), isOn: $model.preferences.hoverToOpen)
            Text(L10n.string("Kapalıyken tıklayarak veya dosya sürükleyerek açılır. Panelin dışına tıklayınca küçülür."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
            Toggle(L10n.string("Paneli açık tut"), isOn: $model.pinned)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L10n.string("Uzaklaşınca kapanma gecikmesi"))
                    Spacer()
                    Text(L10n.string("\(model.preferences.closeDelay.formatted(.number.precision(.fractionLength(2)))) sn"))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.preferences.closeDelay, in: IslandPreferences.closeDelayRange, step: 0.01)
                    .accessibilityLabel(L10n.string("Uzaklaşınca kapanma gecikmesi"))
            }.disabled(!model.preferences.hoverToOpen)
            Toggle(L10n.string("Küçük görünümde pil yüzdesi"), isOn: $model.preferences.showCompactBattery)
        }
        Section(L10n.string("Hızlı erişim ve sistem")) {
            ShortcutSettingsView(model: model)
            Toggle(L10n.string("Donanım bilgilerini izle"), isOn: $model.preferences.monitoringEnabled)
            Text(L10n.string("Ölçümler Menü → Sistem açıkken güncellenir."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
        WorkspaceBackupView(model: model, workspace: workspace, dashboard: dashboard)
        Section(L10n.string("Canlı etkinlikler")) {
            Toggle(L10n.string("Güç adaptörü değişiklikleri"), isOn: $model.activityOptions.power)
            Toggle(L10n.string("Düşük pil göstergesi"), isOn: $model.activityOptions.lowBattery)
            Toggle(L10n.string("Bluetooth bağlantıları"), isOn: $model.activityOptions.bluetooth)
            Toggle(L10n.string("Menü çubuğunda geri sayım"), isOn: $model.activityOptions.countdown)
        }
        UpdateCheckView()
        Section(L10n.string("Sohbet gizliliği")) {
            Button(L10n.string("Sohbet oturumlarını temizle"), role: .destructive) {
                confirmSessionClear = true
            }
            .disabled(assistant.clearingSessions)
            .confirmationDialog(L10n.string("Ada’daki sohbet oturumları temizlensin mi?"),
                                isPresented: $confirmSessionClear, titleVisibility: .visible) {
                Button(L10n.string("Temizle"), role: .destructive) {
                    Task { await assistant.clearSessions() }
                }
            } message: {
                Text(L10n.string("ChatGPT ve Claude pencereleri kapanır. Ada içindeki oturumlara yeniden giriş yapman gerekir."))
            }
            if let status = assistant.sessionStatus { Text(status).adaFont(size: Typography.caption) }
        }
        Section(L10n.string("Ekran")) {
            optionPicker(L10n.string("Panelin görüneceği ekran"), selection: $model.preferences.displayChoice, label: { $0.title })
            Text(L10n.string("Seçilen ekran bağlı değilse kullanılabilir ekrana geçilir. Kamera alanı otomatik ölçülür."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var focusSettings: some View {
        Section(L10n.string("Odak ve mola")) {
            Stepper(L10n.string("Odak süresi: \(model.preferences.defaultMinutes) dakika"), value: $model.preferences.defaultMinutes, in: 1...180)
            Button(L10n.string("Bu süreyi sayaca uygula")) { model.selectMinutes(model.preferences.defaultMinutes) }
                .disabled(model.clock.isRunning)
            Toggle(L10n.string("Odak bitince mola hazırla"), isOn: $model.preferences.pomodoro)
            Stepper(L10n.string("Mola süresi: \(model.preferences.breakMinutes) dakika"), value: $model.preferences.breakMinutes, in: 1...30)
                .disabled(!model.preferences.pomodoro)
            Text(L10n.string("Odak tamamlandığında bir sonraki Başlat düğmesi molayı başlatır. Mola kendiliğinden başlamaz."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("Oturum sonunda")) {
            Toggle(L10n.string("Ses çal"), isOn: $model.soundEnabled)
            Toggle(L10n.string("Paneli aç"), isOn: $model.preferences.showOnCompletion)
            Toggle(L10n.string("Odak bitince bildirim göster"), isOn: Binding(
                get: { model.preferences.notifyOnCompletion },
                set: { enabled in
                    if !enabled { model.preferences.notifyOnCompletion = false; return }
                    Task { model.preferences.notifyOnCompletion = await notifications.requestEnable() }
                }
            )).disabled(notifications.isRequesting)
            Text(L10n.string("Ada gizliyken de tamamlanmayı bildirir. İzin yalnız etkinleştirdiğinde istenir."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
            if let message = notifications.statusMessage {
                Text(message).adaFont(size: Typography.caption).foregroundStyle(.secondary)
            }
        }
    }

    // A single Option type ties the binding and every tag together at compile time.
    private func optionPicker<Option: IslandPreferenceOption>(_ title: String, selection: Binding<Option>,
                                                              label: @escaping (Option) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(Option.allCases)) { option in Text(label(option)).tag(option) }
        }
    }

    private func metric(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, percentage: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(percentage ? "\(Int((value.wrappedValue * 100).rounded()))%" : L10n.string("\(Int(value.wrappedValue)) pt"))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }.padding(.vertical, 3)
    }
}
