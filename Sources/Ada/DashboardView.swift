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
    @State private var draftTask = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(Array(layout.tiles.enumerated()), id: \.element.id) { index, tile in
                    tileView(tile)
                        .frame(height: 90)
                        .opacity(layout.isEditing ? 0 : 1)
                        .allowsHitTesting(!layout.isEditing)
                        .accessibilityHidden(layout.isEditing)
                        .overlay {
                            if layout.isEditing { editTile(tile, at: index) }
                        }
                        .contextMenu {
                            Button("Değiştir") { onChangeTile(tile) }
                            Button("Öne taşı") { layout.move(id: tile.id, by: -1) }.disabled(index == 0)
                            Button("Arkaya taşı") { layout.move(id: tile.id, by: 1) }.disabled(index == layout.tiles.count - 1)
                            Divider()
                            Button("Kutucuğu kaldır") { layout.remove(id: tile.id) }
                        }
                }
                if layout.tiles.count < DashboardLayoutStore.maxTiles {
                    Button(action: onAddTile) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .light))
                            Text("Kutucuk ekle").font(.system(size: 11, weight: .medium))
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
        .scrollIndicators(.hidden)
        .font(.system(size: 12 * model.preferences.textScale))
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
            Text(tile.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Button("Değiştir") { onChangeTile(tile) }
                .font(.system(size: 10)).foregroundStyle(model.accentColor)
                .accessibilityLabel("\(tile.title) kutucuğunu değiştir")
            HStack(spacing: 14) {
                Button { layout.move(id: tile.id, by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22)
                }.disabled(index == 0).accessibilityLabel("\(tile.title) kutucuğunu öne taşı")
                Button { layout.move(id: tile.id, by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 22, height: 22)
                }.disabled(index == layout.tiles.count - 1).accessibilityLabel("\(tile.title) kutucuğunu arkaya taşı")
                Button { layout.remove(id: tile.id) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.85)).frame(width: 22, height: 22)
                }.accessibilityLabel("\(tile.title) kutucuğunu kaldır")
            }.font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: model.preferences.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: model.preferences.cardRadius).strokeBorder(.white.opacity(0.17), lineWidth: 0.8))
        .buttonStyle(IslandButtonStyle())
    }

    private func shortcutTile(_ tile: DashboardTile) -> some View {
        Button { open(tile) } label: {
            HStack(spacing: 10) {
                if let url = tile.appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().scaledToFit().frame(width: 32, height: 32)
                } else {
                    Image(systemName: tile.symbol).font(.system(size: 24, weight: .medium))
                        .foregroundStyle(model.accentColor).frame(width: 32)
                }
                Text(tile.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }.glassCard(model)
        }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
    }

    private func open(_ tile: DashboardTile) {
        switch tile.kind {
        case .files: model.selectPage(.files)
        case .cloud: model.selectPage(.cloud)
        case .system: model.selectPage(.system)
        case .tools: model.selectPage(.tools)
        case .prompter: model.selectPage(.prompter)
        case .airDrop: actions.performAirDrop()
        case .mirror: actions.showMirror()
        case .app:
            guard let url = tile.appURL else { actions.errorMessage = "Bu uygulama bulunamadı. Kutucuğu değiştirerek yeniden seç."; return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { Task { @MainActor in actions.errorMessage = error.localizedDescription } }
            }
        case .website:
            if let url = tile.websiteURL { NSWorkspace.shared.open(url) }
        default: break
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button(action: actions.performAirDrop) {
                VStack(spacing: 4) {
                    Image(systemName: "airplayaudio").font(.system(size: 17))
                    Text("AirDrop").font(.system(size: 11, weight: .semibold))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(model)
            }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
            Button(action: actions.showMirror) {
                VStack(spacing: 4) {
                    Image(systemName: "camera").font(.system(size: 17))
                    Text("Ayna").font(.system(size: 11, weight: .semibold))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard(model)
            }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
        }
    }

    private var batteryCard: some View {
        HStack(spacing: 8) {
            Image(systemName: model.batterySymbol).font(.system(size: 19)).foregroundStyle(model.batteryColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pil").fontWeight(.semibold)
                Text(batteryDetail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(model.batteryPercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit().fixedSize()
        }.glassCard(model)
    }

    private var batteryDetail: String {
        guard model.batteryPercent != nil else { return "Bilgi yok" }
        if model.charging { return "Şarj oluyor" }
        return model.pluggedIn ? "Adaptörde" : "Pil gücünde"
    }

    private var musicCard: some View {
        HStack(spacing: 7) {
            Image(systemName: "music.note").font(.system(size: 15))
                .frame(width: 27, height: 27).background(model.accentColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(actions.audioTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Button("Dosya seç", action: actions.chooseAudio)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).buttonStyle(IslandButtonStyle())
                    .accessibilityLabel("Ses dosyası seç")
            }
            Spacer(minLength: 0)
            Button(action: actions.toggleAudio) {
                Image(systemName: actions.audioPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.opacity)
                    .frame(width: 25, height: 25).background(.white.opacity(0.15), in: Circle())
            }.buttonStyle(IslandButtonStyle(cornerRadius: 100)).help(actions.audioPlaying ? "Müziği duraklat" : "Müziği oynat")
            .animation(.easeInOut(duration: 0.18), value: actions.audioPlaying)
            .accessibilityLabel(actions.audioPlaying ? "Müziği duraklat" : "Müziği oynat")
        }.glassCard(model, highlighted: true)
    }

    private func assistantCard(_ provider: AssistantProvider) -> some View {
        Button { onOpenAssistant(provider) } label: {
            HStack(spacing: 10) {
                Image(systemName: provider.symbol).font(.system(size: 24, weight: .medium))
                    .foregroundStyle(model.accentColor).frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.title).font(.system(size: 13, weight: .semibold))
                    Text("Sohbete geç").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9))
            }.glassCard(model, highlighted: true)
        }.buttonStyle(IslandButtonStyle(cornerRadius: model.preferences.cardRadius, emphasis: true))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Notlar", systemImage: "note.text").fontWeight(.semibold)
                Spacer()
                Menu {
                    Button("Notu Asistana aktar", action: onUseNote)
                        .disabled(workspace.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Notu panoya kopyala") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(workspace.note, forType: .string)
                    }
                    Button("Notu temizle") { workspace.note = "" }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Not seçenekleri")
            }
            ZStack(alignment: .topLeading) {
                if workspace.note.isEmpty {
                    Text("Not yaz…")
                        .font(.system(size: 12 * model.preferences.textScale))
                        .foregroundStyle(.white.opacity(0.35)).padding(.top, 2).padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $workspace.note)
                    .font(.system(size: 12 * model.preferences.textScale))
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Notlar")
            }
        }.glassCard(model)
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(action: model.toggleTimer) {
                    Image(systemName: model.clock.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.opacity)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(model.accentColor.opacity(0.6), in: Circle())
                        .overlay(Circle().trim(from: 0, to: model.progress).stroke(.white.opacity(0.6), lineWidth: 2).rotationEffect(.degrees(-90)))
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100)).help(model.primaryTitle)
                .animation(.easeInOut(duration: 0.18), value: model.clock.isRunning)
                .accessibilityLabel(model.primaryTitle)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.timeLabel)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
                    Text(model.isBreak ? "Mola" : "Odak").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 1)
                Button("Sıfırla", action: model.reset)
                    .font(.system(size: 9, weight: .medium)).buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.65))
                    .fixedSize()
            }
            HStack(spacing: 7) {
                Menu {
                    ForEach([1, 5, 10, 15, 25, 30, 45, 50, 60, 90], id: \.self) { m in
                        Button("\(m) dakika") { model.selectMinutes(m) }
                    }
                } label: { Text("\(model.selectedMinutes) dk") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.clock.isRunning)
                Spacer(minLength: 0)
                Button("−5 dk") { model.adjustMinutes(-5) }.buttonStyle(IslandButtonStyle())
                Button("+5 dk") { model.adjustMinutes(5) }.buttonStyle(IslandButtonStyle())
            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
        }.glassCard(model, highlighted: true)
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Görevler", systemImage: "checklist").fontWeight(.semibold)
                Text("\(workspace.tasks.filter { !$0.done }.count)")
                    .font(.system(size: 9, weight: .semibold)).padding(.horizontal, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                Spacer()
            }
            HStack(spacing: 5) {
                TextField("Yeni görev…", text: $draftTask).textFieldStyle(.plain)
                    .font(.system(size: 10)).onSubmit(addTask)
                Button("Ekle", action: addTask).font(.system(size: 10, weight: .medium))
                    .buttonStyle(IslandButtonStyle()).foregroundStyle(model.accentColor)
                    .disabled(draftTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(workspace.tasks) { item in
                        HStack(spacing: 6) {
                            Button { workspace.toggleTask(item.id) } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .contentTransition(.opacity)
                                    .foregroundStyle(item.done ? model.accentColor : .white.opacity(0.55))
                            }.buttonStyle(IslandButtonStyle()).accessibilityLabel(item.done ? "Görevi yeniden aç" : "Görevi tamamla")
                            .animation(.easeInOut(duration: 0.18), value: item.done)
                            Text(item.title).font(.system(size: 11)).lineLimit(2)
                                .strikethrough(item.done).opacity(item.done ? 0.5 : 1)
                            Spacer(minLength: 1)
                            Button { workspace.removeTask(item.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            }.buttonStyle(IslandButtonStyle()).help("Görevi kaldır")
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }.glassCard(model)
    }
    private func addTask() { workspace.addTask(draftTask); draftTask = "" }
}
