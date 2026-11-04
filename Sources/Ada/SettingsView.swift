import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var dashboard: DashboardLayoutStore
    @ObservedObject var loginItem: LoginItemStore
    var preview: () -> Void
    var customizeDashboard: () -> Void
    var addTile: () -> Void
    @State private var section = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ada · Senin çalışma alanın").font(.system(size: 21, weight: .semibold))
                    Text("Değişiklikler adaya anında uygulanır.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Paneli göster", action: preview)
            }.padding(24)
            Picker("Ayar bölümü", selection: $section) {
                Text("Görünüm").tag(0)
                Text("Ana ekran").tag(1)
                Text("Davranış").tag(2)
                Text("Odak").tag(3)
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 8)
            Form {
                switch section {
                case 1: contentSettings
                case 2: behaviorSettings
                case 3: focusSettings
                default: appearanceSettings
                }
            }.formStyle(.grouped)
            HStack {
                Text("Ada 0.9.1").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Görünümü sıfırla") { model.preferences = IslandPreferences() }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 620, height: 660)
        .buttonStyle(IslandButtonStyle(bordered: true))
        .tint(model.accentColor)
        .onChange(of: model.pinned) { _, _ in model.layoutChanged?() }
    }

    @ViewBuilder private var appearanceSettings: some View {
        Section("Açılış ekranı") {
            Picker("Ada açıldığında", selection: $model.preferences.startupPage) {
                Text("ChatGPT").tag("chatGPT")
                Text("Claude").tag("claude")
                ForEach(IslandPage.allCases) { page in
                    Text(page.title).tag(page.rawValue)
                }
            }
            Text("Menüden bölüm seçtiğinde Ada o bölümü hatırlar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Yerleşim ve boyut") {
            Picker("Yerleşim", selection: $model.preferences.style) {
                ForEach(IslandStyle.allCases) { style in Text(style.title).tag(style.rawValue) }
            }
            HStack {
                Text("Hazır boyut")
                Spacer()
                ForEach([620, 660, 760], id: \.self) { width in
                    Button("\(width) pt") { model.preferences.expandedWidth = Double(width) }
                        .tint(model.preferences.expandedWidth == Double(width) ? model.accentColor : .secondary)
                }
            }
            metric("Panel genişliği", value: $model.preferences.expandedWidth, range: 620...880)
            if model.preferences.style == "notch" {
                Text("Panelin üst kenarı ekranın üstüne oturur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            metric("İçerik yüksekliği", value: $model.preferences.contentHeight, range: 210...340)
            if model.preferences.style == "floating" {
                metric("Üstten uzaklık", value: $model.preferences.floatingGap, range: 0...40)
            }
        }
        Section("Tema ve kartlar") {
            Picker("Panel teması", selection: $model.preferences.palette) {
                Text("Aurora · Mavi / mor").tag("aurora")
                Text("Mor").tag("purple")
                Text("Grafit").tag("graphite")
                Text("Orman").tag("forest")
            }
            Picker("Vurgu rengi", selection: $model.preferences.accent) {
                Text("Mavi").tag("blue"); Text("Mor").tag("purple")
                Text("Nane").tag("mint"); Text("Turuncu").tag("orange")
            }
            metric("Cam tonu", value: $model.preferences.panelOpacity, range: 0.30...0.95, step: 0.01, percentage: true)
            metric("Kart görünürlüğü", value: $model.preferences.cardOpacity, range: 0.05...0.3, step: 0.01, percentage: true)
            metric("Kart köşe yuvarlaklığı", value: $model.preferences.cardRadius, range: 10...28)
            metric("Not yazısı boyutu", value: $model.preferences.textScale, range: 0.9...1.15, step: 0.05, percentage: true)
        }
    }

    @ViewBuilder private var contentSettings: some View {
        Section("Kutucuklar") {
            Text("\(dashboard.tiles.count) / \(DashboardLayoutStore.maxTiles) kutucuk")
            HStack {
                Button("Kutucuk ekle", action: addTile)
                    .disabled(dashboard.tiles.count >= DashboardLayoutStore.maxTiles)
                Button("Ana ekranı düzenle", action: customizeDashboard)
            }
            Text("Ana ekrandaki + ile ekle; Düzenle ile değiştir, sırala veya kaldır.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Müzik") {
            Toggle("Çalan parçayı adada göster", isOn: $model.preferences.showNowPlaying)
            Text("Spotify veya Apple Müzik kutucuğu eklediğinde etkinleşir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Dosya rafı") {
            Picker("Kopyaları saklama süresi", selection: $shelf.retentionDays) {
                Text("1 gün").tag(1); Text("2 gün").tag(2); Text("3 gün").tag(3)
                Text("1 hafta").tag(7); Text("Ben kaldırana kadar").tag(0)
            }
            Text("Dosya rafı orijinallerin yerine kendi kopyalarını kullanır.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Yerel araçlar") {
            Text("Ses dosyaları için Yerel müzik, kamera önizlemesi için Ayna kutucuğunu ekle.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var behaviorSettings: some View {
        Section("Başlangıç") {
            Toggle("Mac açıldığında başlat", isOn: Binding(
                get: { loginItem.enabled },
                set: { loginItem.setEnabled($0) }
            )).disabled(loginItem.isBusy)
            if let message = loginItem.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if loginItem.requiresApproval {
                Button("macOS ayarlarını aç", action: loginItem.openSettings)
            }
        }
        Section("Açılma ve kapanma") {
            Toggle("Üzerine gelince aç ve uzaklaşınca kapat", isOn: $model.preferences.hoverToOpen)
            Text("Kapalıyken tıklayarak veya dosya sürükleyerek açılır. Panelin dışına tıklayınca küçülür.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Paneli açık tut", isOn: $model.pinned)
            Picker("Uzaklaşınca kapanma gecikmesi", selection: $model.preferences.closeDelay) {
                Text("Hızlı · 0,2 sn").tag(0.2)
                Text("Normal · 0,4 sn").tag(0.4)
                Text("Rahat · 0,8 sn").tag(0.8)
            }.disabled(!model.preferences.hoverToOpen)
            Toggle("Küçük görünümde pil yüzdesi", isOn: $model.preferences.showCompactBattery)
        }
        Section("Hızlı erişim ve sistem") {
            Toggle("Genel klavye kısayolu · ⌃⌥A", isOn: $model.preferences.globalShortcutEnabled)
            Text(model.shortcutStatus).font(.caption).foregroundStyle(.secondary)
            Toggle("Donanım bilgilerini izle", isOn: $model.preferences.monitoringEnabled)
            Text("Ölçümler Menü → Sistem açıkken güncellenir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Ekran") {
            Picker("Panelin görüneceği ekran", selection: $model.preferences.displayChoice) {
                Text("MacBook’un dahili ekranı").tag("builtin")
                Text("Ana ekran").tag("main")
            }
            Text("Seçilen ekran bağlı değilse kullanılabilir ekrana geçilir. Kamera alanı otomatik ölçülür.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var focusSettings: some View {
        Section("Odak ve mola") {
            Stepper("Odak süresi: \(model.preferences.defaultMinutes) dakika", value: $model.preferences.defaultMinutes, in: 1...180)
            Button("Bu süreyi sayaca uygula") { model.selectMinutes(model.preferences.defaultMinutes) }
                .disabled(model.clock.isRunning)
            Toggle("Odak bitince mola hazırla", isOn: $model.preferences.pomodoro)
            Stepper("Mola süresi: \(model.preferences.breakMinutes) dakika", value: $model.preferences.breakMinutes, in: 1...30)
                .disabled(!model.preferences.pomodoro)
            Text("Odak tamamlandığında bir sonraki Başlat düğmesi molayı başlatır. Mola kendiliğinden başlamaz.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Oturum sonunda") {
            Toggle("Ses çal", isOn: $model.soundEnabled).onChange(of: model.soundEnabled) { _, _ in model.save() }
            Toggle("Paneli aç", isOn: $model.preferences.showOnCompletion)
        }
    }

    private func metric(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, percentage: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(percentage ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue)) pt")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }.padding(.vertical, 3)
    }
}
