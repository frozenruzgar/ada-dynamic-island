import AdaCore
import SwiftUI
import AppKit

struct ToolsView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var workspace: WorkspaceStore
    @State private var monthOffset = 0
    @State private var amount = "10"
    @State private var conversion = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    battery.glassCard(model)
                    converter.glassCard(model)
                    shortcuts.glassCard(model)
                    calendar.glassCard(model)
                }.frame(height: 183)
                UpcomingEventsView(enabled: $model.preferences.showCalendarEvents)
                    .padding(8).islandCardSurface()
            }
        }.adaFont(size: 11)
    }

    private var battery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("Pil durumu"), systemImage: "battery.100percent").fontWeight(.semibold)
            Spacer(minLength: 0)
            Text(model.batteryPercent.map { "\($0)%" } ?? "—")
                .adaFont(size: 35, weight: .medium, design: .rounded).foregroundStyle(model.accentColor)
            Text(model.batteryDescription).adaFont(size: 10).foregroundStyle(.white.opacity(0.6))
            ProgressView(value: Double(model.batteryPercent ?? 0), total: 100).tint(model.accentColor)
            Spacer(minLength: 0)
            Button(L10n.string("Bilgiyi yenile"), action: model.refreshBattery).buttonStyle(IslandButtonStyle()).foregroundStyle(model.accentColor)
        }
    }

    private var converter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("Birim çevir"), systemImage: "arrow.left.arrow.right").fontWeight(.semibold)
            Spacer(minLength: 0)
            Picker(L10n.string("Dönüşüm"), selection: $conversion) {
                Text(L10n.string("cm → inç")).tag(0)
                Text(L10n.string("kg → lb")).tag(1)
                Text(L10n.string("°C → °F")).tag(2)
            }.labelsHidden()
            TextField(L10n.string("Değer"), text: $amount).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.string("Çevrilecek değer"))
            Text(result).adaFont(size: 23, weight: .medium, design: .rounded)
                .foregroundStyle(model.accentColor).lineLimit(1)
            Spacer(minLength: 0)
            Text(L10n.string("Çevrimdışı hesaplanır")).adaFont(size: 9).foregroundStyle(Palette.tertiaryText)
        }
    }
    private var result: String {
        guard let n = Double(amount.replacingOccurrences(of: ",", with: ".")), n.isFinite else { return "—" }
        let value = conversion == 0 ? n / 2.54 : conversion == 1 ? n * 2.2046226218 : n * 1.8 + 32
        return String(format: "%.2f %@", value, conversion == 0 ? L10n.string("inç") : conversion == 1 ? "lb" : "°F")
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(L10n.string("Kısayollar"), systemImage: "square.grid.2x2").fontWeight(.semibold)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    if i < workspace.shortcuts.count {
                        let shortcut = workspace.shortcuts[i]
                        Button { workspace.openApp(shortcut) } label: {
                            Image(nsImage: shortcut.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
                                .resizable().scaledToFit().frame(width: 34, height: 34)
                                .frame(maxWidth: .infinity).frame(height: 43)
                        }.buttonStyle(IslandButtonStyle())
                        .help(shortcut.title)
                        .accessibilityLabel(shortcut.title)
                        .contextMenu { Button(L10n.string("Kısayolu kaldır")) { workspace.removeShortcut(shortcut.id) } }
                    } else {
                        Button(action: workspace.chooseShortcut) {
                            Image(systemName: "plus").foregroundStyle(Palette.tertiaryText)
                                .frame(maxWidth: .infinity).frame(height: 43)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }.buttonStyle(IslandButtonStyle()).help(L10n.string("Uygulama ekle")).accessibilityLabel(L10n.string("Uygulama kısayolu ekle"))
                    }
                }
            }
            Spacer(minLength: 0)
            if let error = workspace.shortcutError {
                Text(error).adaFont(size: 10).foregroundStyle(.orange).lineLimit(2)
            } else {
                Text(L10n.string("Kaldırmak için sağ tıkla")).adaFont(size: 10).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var calendar: some View {
        VStack(spacing: 7) {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel(L10n.string("Önceki ay"))
                Spacer(minLength: 0)
                Text(monthTitle).adaFont(size: 10, weight: .semibold).lineLimit(1)
                Spacer(minLength: 0)
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.accessibilityLabel(L10n.string("Sonraki ay"))
            }.buttonStyle(IslandButtonStyle())
            HStack(spacing: 0) {
                ForEach(Array(CalendarPresentation.weekdays().enumerated()), id: \.offset) { _, day in
                    Text(day).adaFont(size: 8, weight: .semibold).foregroundStyle(Palette.tertiaryText).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 3) {
                ForEach(0..<42, id: \.self) { index in
                    let day = index - leadingDays + 1
                    let valid = day > 0 && day <= daysInMonth
                    let today = monthOffset == 0 && day == Calendar.current.component(.day, from: Date())
                    Text(valid ? "\(day)" : " ")
                        .adaFont(size: 9, weight: today ? .bold : .medium)
                        .frame(width: 18, height: 17)
                        .background(today ? model.accentColor.opacity(0.8) : .clear, in: Circle())
                        .foregroundStyle(valid ? .white.opacity(today ? 1 : 0.7) : .clear)
                }
            }
            Spacer(minLength: 0)
            Button(L10n.string("Bugüne dön")) { monthOffset = 0 }.adaFont(size: 9).buttonStyle(IslandButtonStyle()).foregroundStyle(model.accentColor)
        }
    }
    private var month: Date { Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date() }
    private var firstDay: Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month)) ?? month }
    private var leadingDays: Int { CalendarPresentation.leadingDays(for: firstDay) }
    private var daysInMonth: Int { Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30 }
    private var monthTitle: String {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.calendar = .autoupdatingCurrent; f.setLocalizedDateFormatFromTemplate("MMM yyyy"); return f.string(from: month)
    }
}
