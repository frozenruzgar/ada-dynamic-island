import AdaCore
import SwiftUI
import AppKit

struct IslandSearchView: View {
    let tiles: [DashboardTile]
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var shelf: ShelfStore
    let accent: Color
    let onPage: (IslandPage) -> Void
    let onTile: (DashboardTile) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var alternate = false
    @State private var applications: [URL] = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let results = searchResults
        VStack(alignment: .leading, spacing: 8) {
            searchField(results: results)
            if results.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .adaFont(size: 22, weight: .light)
                    Text(L10n.string("Sonuç bulunamadı"))
                        .adaFont(size: 13, weight: .semibold)
                    Text(L10n.string("Not, görev, dosya veya uygulama ara. Hesap için 2 + 2 yaz."))
                        .adaFont(size: 11)
                }
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList(results)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(IslandControlSurface(cornerRadius: 16))
        .task {
            await Task.yield()
            fieldFocused = true
            applications = await Task.detached(priority: .utility) { Self.localApplications() }.value
        }
        .onChange(of: query) { selectedIndex = 0; alternate = false }
        .onExitCommand(perform: onClose)
    }

    private func searchField(results: [Result]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .adaFont(size: 13, weight: .semibold)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            TextField(L10n.string("Ada’da ara veya hesapla"), text: $query)
                .textFieldStyle(.plain)
                .adaFont(size: 13, weight: .medium)
                .focused($fieldFocused)
                .onSubmit {
                    if results.indices.contains(selectedIndex) { open(results[selectedIndex], alternate: alternate) }
                }
                .onKeyPress(.downArrow) { moveSelection(by: 1, in: results) }
                .onKeyPress(.upArrow) { moveSelection(by: -1, in: results) }
                .onKeyPress(.tab) {
                    guard results.indices.contains(selectedIndex), results[selectedIndex].hasAlternate else { return .ignored }
                    alternate.toggle()
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.tertiaryText)
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(IslandButtonStyle(cornerRadius: 8))
                .accessibilityLabel(L10n.string("Aramayı temizle"))
            }
            Button(action: onClose) {
                Text(L10n.string("Esc"))
                    .adaFont(size: 10, weight: .semibold, design: .monospaced)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(IslandButtonStyle(cornerRadius: 6))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(L10n.string("Aramayı kapat"))
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 11))
    }

    private func resultsList(_ results: [Result]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result, selected: index == selectedIndex)
                            .id(result.id)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
            .onChange(of: selectedIndex) {
                if results.indices.contains(selectedIndex) {
                    proxy.scrollTo(results[selectedIndex].id)
                }
            }
            .onChange(of: query) {
                if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private func resultRow(_ result: Result, selected: Bool) -> some View {
        Button { open(result, alternate: selected && alternate) } label: {
            HStack(spacing: 8) {
                Group {
                    if case .tile(let tile) = result, tile.kind == .spotify {
                        SpotifyBrandIcon(size: 26)
                    } else {
                        Image(systemName: result.symbol)
                            .adaFont(size: 12, weight: .medium)
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 26)
                .accessibilityHidden(true)
                Text(result.title)
                    .adaFont(size: 12, weight: .medium)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(selected && result.hasAlternate ? result.actionTitle(alternate: alternate) : result.category)
                    .adaFont(size: 10)
                    .foregroundStyle(Palette.tertiaryText)
                Image(systemName: selected ? "return" : "arrow.up.right")
                    .adaFont(size: 9, weight: .semibold)
                    .foregroundStyle(.white.opacity(selected ? 0.8 : 0.42))
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background(selected ? accent.opacity(0.20) : .white.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle(cornerRadius: 8))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(result.hasAlternate ? L10n.string("Tab ile eylemi değiştir") : "")
    }

    private func moveSelection(by offset: Int, in results: [Result]) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        selectedIndex = min(results.count - 1, max(0, selectedIndex + offset))
        alternate = false
        return .handled
    }

    private func open(_ result: Result, alternate: Bool) {
        switch result {
        case .page(let page): onPage(page)
        case .tile(let tile): onTile(tile)
        case .note:
            copy(workspace.note)
        case .task(let task):
            if alternate { copy(task.title) }
            else { workspace.toggleTask(task.id) }
        case .file(let item):
            if alternate { shelf.reveal(item) }
            else { shelf.open(item) }
        case .application(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .calculation(let result):
            copy(result)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onClose()
    }

    private nonisolated static func localApplications() -> [URL] {
        let manager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"),
                     URL(fileURLWithPath: "/System/Applications"),
                     URL(fileURLWithPath: "/System/Applications/Utilities"),
                     manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        return roots.flatMap { root in
            (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                              options: .skipsHiddenFiles)) ?? []
        }.filter { $0.pathExtension.lowercased() == "app" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private var searchResults: [Result] {
        let pages = IslandPage.allCases.filter { $0 != .menu && $0 != .search }
        let pageTitles = Set(pages.map { Self.fold($0.title) })
        let shortcuts = tiles.filter {
            switch $0.kind {
            case .files, .cloud, .system, .tools, .prompter:
                return !pageTitles.contains(Self.fold($0.title))
            default: return true
            }
        }
        let normalizedQuery = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let words = normalizedQuery.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return Array(shortcuts.prefix(3)).map(Result.tile) + pages.map(Result.page) +
                shortcuts.dropFirst(3).map(Result.tile)
        }
        var candidates = pages.map(Result.page) + shortcuts.map(Result.tile)
        candidates += workspace.tasks.map(Result.task)
        candidates += shelf.items.map(Result.file)
        if normalizedQuery.count >= 2 { candidates += applications.map(Result.application) }
        if !workspace.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(.note(String(workspace.note.prefix(20_000))))
        }
        let calculation = CommandCalculation.evaluate(query).map { [Result.calculation($0)] } ?? []
        var ranked: [(index: Int, rank: Int, result: Result)] = []
        for (index, result) in candidates.enumerated() {
            let title = Self.fold(result.title)
            let searchable = title + " " + Self.fold(result.keywords)
            guard words.allSatisfy({ searchable.contains($0) }) else { continue }
            let rank: Int
            if title == normalizedQuery { rank = 0 }
            else if title.hasPrefix(normalizedQuery) { rank = 1 }
            else if words.allSatisfy({ title.contains($0) }) { rank = 2 }
            else { rank = 3 }
            ranked.append((index, rank, result))
        }
        ranked.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.index < $1.index
        }
        return calculation + ranked.prefix(40).map { $0.result }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    private enum Result: Identifiable {
        case page(IslandPage)
        case tile(DashboardTile)
        case note(String)
        case task(TaskItem)
        case file(ShelfItem)
        case application(URL)
        case calculation(String)

        var hasAlternate: Bool {
            switch self {
            case .task, .file: return true
            default: return false
            }
        }

        func actionTitle(alternate: Bool) -> String {
            switch self {
            case .task(let task):
                if alternate { return L10n.string("Kopyala") }
                return task.done ? L10n.string("Görevi yeniden aç") : L10n.string("Görevi tamamla")
            case .file: return alternate ? L10n.string("Finder’da göster") : L10n.string("Aç")
            default: return category
            }
        }

        var id: String {
            switch self {
            case .page(let page): return page.rawValue
            case .tile(let tile): return tile.id.uuidString
            case .note: return "note"
            case .task(let task): return "task-\(task.id)"
            case .file(let item): return "file-\(item.id)"
            case .application(let url): return url.path
            case .calculation: return "calculation"
            }
        }

        var title: String {
            switch self {
            case .page(let page): return page.title
            case .tile(let tile): return tile.title
            case .note: return L10n.string("Notlar")
            case .task(let task): return task.title
            case .file(let item): return item.name
            case .application(let url): return url.deletingPathExtension().lastPathComponent
            case .calculation(let value): return value
            }
        }

        var symbol: String {
            switch self {
            case .page(let page): return page.symbol
            case .tile(let tile): return tile.symbol
            case .note: return "note.text"
            case .task: return "checklist"
            case .file: return "doc"
            case .application: return "app"
            case .calculation: return "equal.circle"
            }
        }

        var category: String {
            switch self {
            case .page: return L10n.string("Bölüm")
            case .tile: return L10n.string("Kutucuk")
            case .note: return L10n.string("Notu panoya kopyala")
            case .task: return L10n.string("Görev")
            case .file: return L10n.string("Dosya")
            case .application: return L10n.string("Uygulama")
            case .calculation: return L10n.string("Sonucu kopyala")
            }
        }

        var keywords: String {
            switch self {
            case .page(let page):
                switch page {
                case .home: return L10n.string("ana sayfa")
                case .assistant: return L10n.string("ChatGPT Claude yapay zeka")
                case .files: return L10n.string("raf sürükle belge")
                case .system: return L10n.string("donanım RAM işlemci disk")
                case .cloud: return L10n.string("iCloud Drive")
                case .tools: return L10n.string("takvim hesaplayıcı")
                case .prompter: return L10n.string("metin konuşma")
                case .player: return L10n.string("müzik çalan Spotify Apple Music takvim")
                case .menu, .search: return ""
                }
            case .tile(let tile):
                return [tile.kind.title, tile.websiteURL?.host].compactMap { $0 }.joined(separator: " ")
            case .note(let contents): return contents
            case .task, .file, .application, .calculation: return category
            }
        }
    }
}
