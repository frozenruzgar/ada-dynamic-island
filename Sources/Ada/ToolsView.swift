import SwiftUI
import AppKit

struct ToolsView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var workspace: WorkspaceStore
    @State private var monthOffset = 0
    @State private var amount = "10"
    @State private var conversion = 0

    var body: some View {
        HStack(spacing: 12) {
            battery.glassCard(model)
            converter.glassCard(model)
            shortcuts.glassCard(model)
            calendar.glassCard(model)
        }.font(.system(size: 11))
    }

    private var battery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pil durumu", systemImage: "battery.100percent").fontWeight(.semibold)
            Spacer(minLength: 0)
            Text(model.batteryPercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 35, weight: .medium, design: .rounded)).foregroundStyle(model.accentColor)
            Text(model.batteryDescription).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            ProgressView(value: Double(model.batteryPercent ?? 0), total: 100).tint(model.accentColor)
            Spacer(minLength: 0)
            Button("Bilgiyi yenile", action: model.refreshBattery).buttonStyle(IslandButtonStyle()).foregroundStyle(model.accentColor)
        }
    }

    private var converter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Birim çevir", systemImage: "arrow.left.arrow.right").fontWeight(.semibold)
            Spacer(minLength: 0)
            Picker("Dönüşüm", selection: $conversion) {
                Text("cm → inç").tag(0)
                Text("kg → lb").tag(1)
                Text("°C → °F").tag(2)
            }.labelsHidden()
            TextField("Değer", text: $amount).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Çevrilecek değer")
            Text(result).font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(model.accentColor).minimumScaleFactor(0.6).lineLimit(1)
            Spacer(minLength: 0)
            Text("Çevrimdışı hesaplanır").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
    }
    private var result: String {
        guard let n = Double(amount.replacingOccurrences(of: ",", with: ".")), n.isFinite else { return "—" }
        let value = conversion == 0 ? n / 2.54 : conversion == 1 ? n * 2.2046226218 : n * 1.8 + 32
        return String(format: "%.2f %@", value, conversion == 0 ? "inç" : conversion == 1 ? "lb" : "°F")
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Kısayollar", systemImage: "square.grid.2x2").fontWeight(.semibold)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    if i < workspace.shortcuts.count {
                        let path = workspace.shortcuts[i]
                        Button { workspace.openApp(path) } label: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().scaledToFit().frame(width: 34, height: 34)
                                .frame(maxWidth: .infinity).frame(height: 43)
                        }.buttonStyle(IslandButtonStyle())
                        .help(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .accessibilityLabel(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .contextMenu { Button("Kısayolu kaldır") { workspace.shortcuts.remove(at: i) } }
                    } else {
                        Button(action: workspace.chooseShortcut) {
                            Image(systemName: "plus").foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity).frame(height: 43)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }.buttonStyle(IslandButtonStyle()).help("Uygulama ekle").accessibilityLabel("Uygulama kısayolu ekle")
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Kaldırmak için sağ tıkla").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
    }

    private var calendar: some View {
        VStack(spacing: 7) {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Önceki ay")
                Spacer(minLength: 0)
                Text(monthTitle).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Sonraki ay")
            }.buttonStyle(IslandButtonStyle())
            HStack(spacing: 0) {
                ForEach(Array(["P", "S", "Ç", "P", "C", "C", "P"].enumerated()), id: \.offset) { _, day in
                    Text(day).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.4)).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 3) {
                ForEach(0..<42, id: \.self) { index in
                    let day = index - leadingDays + 1
                    let valid = day > 0 && day <= daysInMonth
                    let today = monthOffset == 0 && day == Calendar.current.component(.day, from: Date())
                    Text(valid ? "\(day)" : " ")
                        .font(.system(size: 9, weight: today ? .bold : .medium))
                        .frame(width: 18, height: 17)
                        .background(today ? model.accentColor.opacity(0.8) : .clear, in: Circle())
                        .foregroundStyle(valid ? .white.opacity(today ? 1 : 0.7) : .clear)
                }
            }
            Spacer(minLength: 0)
            Button("Bugüne dön") { monthOffset = 0 }.font(.system(size: 9)).buttonStyle(IslandButtonStyle()).foregroundStyle(model.accentColor)
        }
    }
    private var month: Date { Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date() }
    private var firstDay: Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month)) ?? month }
    private var leadingDays: Int { (Calendar.current.component(.weekday, from: firstDay) + 5) % 7 }
    private var daysInMonth: Int { Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30 }
    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "MMM yyyy"; return f.string(from: month).uppercased()
    }
}
