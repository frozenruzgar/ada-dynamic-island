import AdaCore
import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var actions: QuickActionStore
    @ObservedObject var layout: DashboardLayoutStore
    @ObservedObject var media: NowPlayingStore
    var onUseNote: () -> Void = {}
    var onOpenAssistant: (AssistantProvider) -> Void = { _ in }
    var onAddTile: () -> Void = {}
    var onChangeTile: (DashboardTile) -> Void = { _ in }
    var requestedTileID: UUID?
    @State private var draftTask = ""
    @State private var todayOnly = false
    @State private var editingTaskDate: UUID?
    @State private var draftDueDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            grid.onChange(of: requestedTileID ?? layout.focusedTileID, initial: true) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(Array(layout.tiles.enumerated()), id: \.element.id) { index, tile in
                    Group {
                        if layout.isEditing {
                            editTile(tile, at: index)
                        } else {
                            tileView(tile)
                        }
                    }
                        .frame(height: 90)
                        .contextMenu {
                            Button(L10n.string("Değiştir")) { onChangeTile(tile) }
                            Button(L10n.string("Öne taşı")) { layout.move(id: tile.id, by: -1) }.disabled(index == 0)
                            Button(L10n.string("Arkaya taşı")) { layout.move(id: tile.id, by: 1) }.disabled(index == layout.tiles.count - 1)
                            Divider()
                            Button(L10n.string("Kutucuğu kaldır")) { layout.remove(id: tile.id) }
                        }
                        .id(tile.id)
                }
                if layout.tiles.count < DashboardLayoutStore.maxTiles {
                    Button(action: onAddTile) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").adaFont(size: 20, weight: .light)
                            Text(L10n.string("Kutucuk ekle")).adaFont(size: 11, weight: .medium)
                        }
                        .frame(maxWidth: .infinity).frame(height: 90)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: model.preferences.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: model.preferences.cardRadius)
                            .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .adaFont(size: 12)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: layout.tiles.map(\.id))
    }

    @ViewBuilder private func tileView(_ tile: DashboardTile) -> some View {
        switch tile.kind {
        case .quickActions: quickActions
        case .battery: batteryCard
        case .focus: focusCard
        case .notes: notesCard
        case .tasks: tasksCard
        case .localMusic: musicCard
        case .chatGPT: assistantCard(.chatGPT)
        case .claude: assistantCard(.claude)
        case .spotify: MediaTileView(store: media, source: .spotify, accent: model.accentColor)
        case .appleMusic: MediaTileView(store: media, source: .appleMusic, accent: model.accentColor)
        default: shortcutTile(tile)
        }
    }

    private func editTile(_ tile: DashboardTile, at index: Int) -> some View {
        VStack(spacing: 6) {
            Button { onChangeTile(tile) } label: {
                VStack(spacing: 4) {
                    Text(tile.title).adaFont(size: 12, weight: .semibold).lineLimit(1)
                    Label(L10n.string("Değiştir"), systemImage: "pencil")
                        .adaFont(size: 10).foregroundStyle(model.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.string("\(tile.title) kutucuğunu değiştir"))
            HStack(spacing: 14) {
                Button { layout.move(id: tile.id, by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22)
                }.disabled(index == 0).accessibilityLabel(L10n.string("\(tile.title) kutucuğunu öne taşı"))
                Button { layout.move(id: tile.id, by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 22, height: 22)
                }.disabled(index == layout.tiles.count - 1).accessibilityLabel(L10n.string("\(tile.title) kutucuğunu arkaya taşı"))
                Button { layout.remove(id: tile.id) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.85)).frame(width: 22, height: 22)
                }.accessibilityLabel(L10n.string("\(tile.title) kutucuğunu kaldır"))
            }.adaFont(size: 11).padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: model.preferences.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: model.preferences.cardRadius).strokeBorder(.white.opacity(0.17), lineWidth: 0.8))
        .buttonStyle(IslandButtonStyle())
    }

    private func shortcutTile(_ tile: DashboardTile) -> some View {
        Button { tile.openShortcut(model: model, actions: actions) } label: {
            HStack(spacing: 10) {
                if let url = tile.appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().scaledToFit().frame(width: 32, height: 32)
                } else {
                    Image(systemName: tile.symbol).adaFont(size: 24, weight: .medium)
                        .foregroundStyle(model.accentColor).frame(width: 32)
                }
                Text(tile.title).adaFont(size: 12, weight: .semibold).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").adaFont(size: 9).foregroundStyle(Palette.tertiaryText)
            }.glassCard(model)
        }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button(action: actions.performAirDrop) {
                VStack(spacing: 4) {
                    Image(systemName: "airplayaudio").adaFont(size: 17)
                    Text(L10n.string("AirDrop")).adaFont(size: 11, weight: .semibold)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(model)
            }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
            Button(action: actions.showMirror) {
                VStack(spacing: 4) {
                    Image(systemName: "camera").adaFont(size: 17)
                    Text(L10n.string("Ayna")).adaFont(size: 11, weight: .semibold)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(model)
            }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
        }
    }

    private var batteryCard: some View {
        HStack(spacing: 8) {
            Image(systemName: model.batterySymbol).adaFont(size: 19).foregroundStyle(model.batteryColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("Pil")).fontWeight(.semibold)
                Text(batteryDetail).adaFont(size: 10).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(model.batteryPercent.map { "\($0)%" } ?? "—")
                .adaFont(size: 19, weight: .medium, design: .rounded).monospacedDigit().fixedSize()
        }.glassCard(model)
    }

    private var batteryDetail: String {
        guard model.batteryPercent != nil else { return L10n.string("Bilgi yok") }
        if model.charging { return L10n.string("Şarj oluyor") }
        return model.pluggedIn ? L10n.string("Adaptörde") : L10n.string("Pil gücünde")
    }

    private var musicCard: some View {
        HStack(spacing: 7) {
            Image(systemName: "music.note").adaFont(size: 15)
                .frame(width: 27, height: 27).background(model.accentColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(actions.audioTitle).adaFont(size: 11, weight: .medium).lineLimit(1)
                Button(L10n.string("Dosya seç"), action: actions.chooseAudio)
                    .adaFont(size: 10).foregroundStyle(.white.opacity(0.65)).buttonStyle(IslandButtonStyle())
                    .accessibilityLabel(L10n.string("Ses dosyası seç"))
            }
            Spacer(minLength: 0)
            Button(action: actions.toggleAudio) {
                Image(systemName: actions.audioPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.opacity)
                    .frame(width: 25, height: 25).background(.white.opacity(0.15), in: Circle())
            }.buttonStyle(IslandButtonStyle(cornerRadius: 100)).help(actions.audioPlaying ? L10n.string("Müziği duraklat") : L10n.string("Müziği oynat"))
            .animation(.easeInOut(duration: 0.18), value: actions.audioPlaying)
            .accessibilityLabel(actions.audioPlaying ? L10n.string("Müziği duraklat") : L10n.string("Müziği oynat"))
        }.glassCard(model, highlighted: true)
    }

    private func assistantCard(_ provider: AssistantProvider) -> some View {
        Button { onOpenAssistant(provider) } label: {
            HStack(spacing: 10) {
                Image(systemName: provider.symbol).adaFont(size: 24, weight: .medium)
                    .foregroundStyle(model.accentColor).frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.title).adaFont(size: 13, weight: .semibold)
                    Text(L10n.string("Sohbete geç")).adaFont(size: 10).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").adaFont(size: 9)
            }.glassCard(model, highlighted: true)
        }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(L10n.string("Notlar"), systemImage: "note.text").fontWeight(.semibold)
                Spacer()
                Menu {
                    Button(L10n.string("Notu Asistana aktar"), action: onUseNote)
                        .disabled(workspace.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.string("Notu dışa aktar (.md)"), action: workspace.exportNote)
                    Button(L10n.string("Notu panoya kopyala")) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(workspace.note, forType: .string)
                    }
                    Button(L10n.string("Notu temizle")) { workspace.note = "" }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel(L10n.string("Not seçenekleri"))
            }
            ZStack(alignment: .topLeading) {
                if workspace.note.isEmpty {
                    Text(L10n.string("Not yaz…"))
                        .adaFont(size: 12)
                        .foregroundStyle(Palette.tertiaryText).padding(.top, 2).padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $workspace.note)
                    .adaFont(size: 12)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(L10n.string("Notlar"))
            }
            if let error = workspace.noteError ?? workspace.noteExportError {
                Text(error).adaFont(size: 10).foregroundStyle(.orange).lineLimit(2)
            }
        }.glassCard(model)
    }

    private var focusCard: some View {
        FocusCardView(model: model, focus: model.focus)
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.string("Görevler"), systemImage: "checklist").fontWeight(.semibold)
                Text("\(workspace.tasks.filter { !$0.done }.count)")
                    .adaFont(size: 9, weight: .semibold).padding(.horizontal, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                Spacer(minLength: 0)
                Button(todayOnly ? L10n.string("Bugün") : L10n.string("Tümü")) { todayOnly.toggle() }
                    .buttonStyle(IslandButtonStyle())
                    .help(L10n.string("Bugünün görevlerini filtrele"))
                    .accessibilityLabel(L10n.string("Bugünün görevlerini filtrele"))
                    .accessibilityAddTraits(todayOnly ? .isSelected : [])
            }
            HStack(spacing: 5) {
                TextField(L10n.string("Yeni görev…"), text: $draftTask).textFieldStyle(.plain)
                    .adaFont(size: 10).onSubmit(addTask)
                Button(L10n.string("Ekle"), action: addTask).adaFont(size: 10, weight: .medium)
                    .buttonStyle(IslandButtonStyle()).foregroundStyle(model.accentColor)
                    .disabled(draftTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(workspace.tasks.filter { !todayOnly || $0.isDueToday() }) { item in
                        HStack(spacing: 6) {
                            Button { workspace.toggleTask(item.id) } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .contentTransition(.opacity)
                                    .foregroundStyle(item.done ? model.accentColor : Palette.tertiaryText)
                            }.buttonStyle(IslandButtonStyle()).accessibilityLabel(item.done ? L10n.string("Görevi yeniden aç") : L10n.string("Görevi tamamla"))
                            .animation(.easeInOut(duration: 0.18), value: item.done)
                            Text(item.title).adaFont(size: 11).lineLimit(2)
                                .strikethrough(item.done).opacity(item.done ? 0.5 : 1)
                            Spacer(minLength: 1)
                            Menu {
                                Button(L10n.string("Bugün")) { workspace.setTaskDueDate(item.id, date: .now) }
                                Button(L10n.string("Tarih seç…")) {
                                    draftDueDate = item.dueDate ?? .now
                                    editingTaskDate = item.id
                                }
                                if item.dueDate != nil {
                                    Button(L10n.string("Tarihi kaldır")) { workspace.setTaskDueDate(item.id, date: nil) }
                                }
                                Divider()
                                Button(L10n.string("Öne taşı")) { workspace.moveTask(item.id, offset: -1) }
                                Button(L10n.string("Arkaya taşı")) { workspace.moveTask(item.id, offset: 1) }
                            } label: {
                                Image(systemName: item.dueDate == nil ? "calendar" : "calendar.badge.checkmark")
                            }.menuStyle(.borderlessButton).fixedSize()
                                .accessibilityLabel(L10n.string("Görev tarihi ve sırası"))
                                .help(item.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? L10n.string("Tarih seç…"))
                            Button { workspace.removeTask(item.id) } label: {
                                Image(systemName: "xmark").adaFont(size: 8).foregroundStyle(Palette.tertiaryText)
                            }.buttonStyle(IslandButtonStyle()).help(L10n.string("Görevi kaldır"))
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }.glassCard(model)
        .popover(isPresented: Binding(get: { editingTaskDate != nil }, set: { if !$0 { editingTaskDate = nil } })) {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker(L10n.string("Bitiş tarihi"), selection: $draftDueDate, displayedComponents: .date)
                Button(L10n.string("Kaydet")) {
                    if let id = editingTaskDate { workspace.setTaskDueDate(id, date: draftDueDate) }
                    editingTaskDate = nil
                }.keyboardShortcut(.defaultAction)
            }.padding(14)
        }
        .onChange(of: editingTaskDate) { _, id in model.panelPopoverOpen = id != nil }
        .onDisappear { if editingTaskDate != nil { model.panelPopoverOpen = false } }
    }
    private func addTask() { workspace.addTask(draftTask); draftTask = "" }
}

extension DashboardTile {
    @MainActor
    func openShortcut(model: IslandModel, actions: QuickActionStore) {
        switch kind {
        case .files: model.selectPage(.files)
        case .cloud: model.selectPage(.cloud)
        case .system: model.selectPage(.system)
        case .tools: model.selectPage(.tools)
        case .prompter: model.selectPage(.prompter)
        case .airDrop: actions.performAirDrop()
        case .mirror: actions.showMirror()
        case .app:
            guard let url = appURL else {
                actions.errorMessage = L10n.string("Bu uygulama bulunamadı. Kutucuğu değiştirerek yeniden seç.")
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { Task { @MainActor in actions.errorMessage = error.localizedDescription } }
            }
        case .website:
            if let url = websiteURL { NSWorkspace.shared.open(url) }
        default: break
        }
    }
}

private struct FocusCardView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var focus: FocusClockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(action: model.toggleTimer) {
                    Image(systemName: model.clock.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.opacity)
                        .adaFont(size: 12, weight: .semibold)
                        .frame(width: 28, height: 28)
                        .background(model.accentColor.opacity(0.6), in: Circle())
                        .overlay(Circle().trim(from: 0, to: focus.progress).stroke(.white.opacity(0.6), lineWidth: 2).rotationEffect(.degrees(-90)))
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100)).help(model.primaryTitle)
                .animation(.easeInOut(duration: 0.18), value: model.clock.isRunning)
                .accessibilityLabel(model.primaryTitle)
                VStack(alignment: .leading, spacing: 0) {
                    Text(focus.timeLabel)
                        .adaFont(size: 21, weight: .semibold, design: .rounded)
                        .monospacedDigit().lineLimit(1)
                    Text(model.isBreak ? L10n.string("Mola") : L10n.string("Odak")).adaFont(size: 10).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 1)
                Button(L10n.string("Sıfırla"), action: model.reset)
                    .adaFont(size: 9, weight: .medium).buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.65))
                    .fixedSize()
            }
            HStack(spacing: 7) {
                Menu {
                    ForEach([1, 5, 10, 15, 25, 30, 45, 50, 60, 90], id: \.self) { m in
                        Button(L10n.string("\(m) dakika")) { model.selectMinutes(m) }
                    }
                } label: { Text(L10n.string("\(model.selectedMinutes) dk")) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.clock.isRunning)
                Spacer(minLength: 0)
                Button(L10n.string("−5 dk")) { model.adjustMinutes(-5) }.buttonStyle(IslandButtonStyle())
                Button(L10n.string("+5 dk")) { model.adjustMinutes(5) }.buttonStyle(IslandButtonStyle())
            }.adaFont(size: 9).foregroundStyle(.white.opacity(0.65))
        }.glassCard(model, highlighted: true)
    }
}
