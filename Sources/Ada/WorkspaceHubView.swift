import SwiftUI

enum IslandPage: String, CaseIterable, Identifiable {
    case home, menu, assistant, files, system, cloud, tools, prompter

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "Ana ekran"
        case .menu: return "Menü"
        case .assistant: return "Asistan"
        case .files: return "Dosyalar"
        case .system: return "Sistem"
        case .cloud: return "Bulut"
        case .tools: return "Araçlar"
        case .prompter: return "Teleprompter"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .menu: return "square.grid.2x2"
        case .assistant: return "sparkles"
        case .files: return "tray"
        case .system: return "cpu"
        case .cloud: return "icloud"
        case .tools: return "wrench.and.screwdriver"
        case .prompter: return "text.viewfinder"
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case .assistant: return 238
        case .system: return 305
        case .cloud: return 253
        default: return 0
        }
    }
}

struct WorkspaceHubView: View {
    @ObservedObject var model: IslandModel
    var onSettings: () -> Void

    private let rows: [[IslandPage]] = [
        [.home, .assistant, .files, .system],
        [.cloud, .tools, .prompter]
    ]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(rows[row]) { page in
                        tile(page.title, symbol: page.symbol) { model.selectPage(page) }
                    }
                    if row == 1 { tile("Ayarlar", symbol: "gearshape", action: onSettings) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(IslandControlSurface())
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(IslandButtonStyle(cornerRadius: 16, emphasis: true))
    }
}
