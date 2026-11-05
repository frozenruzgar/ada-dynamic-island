import AppKit
import SwiftUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var store: ShelfStore
    var accent: Color = .blue
    var onInteraction: (Bool) -> Void = { _ in }
    @State private var targeted = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L10n.string("Dosyalar"), systemImage: "tray.full.fill")
                    .adaFont(size: 12, weight: .semibold)
                Text("\(store.items.count)").adaFont(size: 10, weight: .semibold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
                Text(store.totalBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                     ?? L10n.string("Boyut hesaplanıyor"))
                    .adaFont(size: 10).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if store.isImporting {
                    ProgressView(value: Double(store.completedCount), total: Double(max(1, store.totalCount)))
                        .frame(width: 45)
                    Text(L10n.string("\(store.completedCount)/\(store.totalCount) · \(store.queuedCount) sırada"))
                        .adaFont(size: 10).monospacedDigit()
                        .accessibilityLabel(L10n.string("\(store.totalCount) dosyanın \(store.completedCount) tanesi tamamlandı; \(store.queuedCount) dosya sırada"))
                }
                Menu {
                    ForEach([0, 1, 2, 3, 7], id: \.self) { days in
                        Button {
                            store.retentionDays = days
                        } label: {
                            if store.retentionDays == days {
                                Label(days == 0 ? L10n.string("Ben kaldırana kadar") : L10n.string("\(days) gün"), systemImage: "checkmark")
                            } else { Text(days == 0 ? L10n.string("Ben kaldırana kadar") : L10n.string("\(days) gün")) }
                        }
                    }
                } label: {
                    Label(store.retentionDays == 0 ? L10n.string("Sakla") : L10n.string("\(store.retentionDays) gün sakla"), systemImage: "clock")
                        .adaFont(size: 10)
                }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Button(L10n.string("Dosya ekle…"), action: store.chooseFiles)
                    Button(L10n.string("Panodan ekle")) { store.pasteFiles() }
                } label: {
                    Label(L10n.string("Ekle"), systemImage: "plus")
                }.menuStyle(.borderlessButton).fixedSize()
                if !store.items.isEmpty {
                    Button(selecting ? L10n.string("Bitti") : L10n.string("Seç")) {
                        selecting.toggle()
                        if !selecting { selection.removeAll() }
                    }.buttonStyle(IslandButtonStyle())
                    Menu {
                        Button(L10n.string("Paylaş…")) { store.shareFiles(selection) }
                            .disabled(selection.isEmpty)
                        Button(L10n.string("Panoya kopyala")) { store.copyFiles(selection) }
                            .disabled(selection.isEmpty)
                        Divider()
                        Button(L10n.string("Tümünü kaldır"), role: .destructive, action: store.removeAll)
                            .disabled(store.isImporting)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }.menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(L10n.string("Raf işlemleri"))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 19)
                    .fill(targeted ? accent.opacity(0.2) : .white.opacity(0.035))
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(targeted ? accent : .white.opacity(0.16), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [6, 4] : []))
                if store.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .adaFont(size: 25, weight: .light).foregroundStyle(accent)
                        Text(targeted ? L10n.string("Dosyaları buraya bırak") : L10n.string("Dosyalarını buraya sürükle"))
                            .adaFont(size: 13, weight: .medium)
                        Text(L10n.string("Kopyaları rafta kalır. Orijinalleri yerinde durur."))
                            .adaFont(size: 10).foregroundStyle(Palette.tertiaryText)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(store.items) { item in
                                ShelfFileTile(item: item, store: store, accent: accent,
                                    selecting: selecting, selected: selection.contains(item.id)) {
                                    if selection.contains(item.id) { selection.remove(item.id) }
                                    else { selection.insert(item.id) }
                                }
                            }
                        }.padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 125, maxHeight: .infinity)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                store.receiveProviders(providers)
            }
            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(error).adaFont(size: 10).lineLimit(2)
                    Spacer(minLength: 0)
                    Button(L10n.string("Kapat")) { store.errorMessage = nil }
                        .adaFont(size: 10).buttonStyle(IslandButtonStyle()).foregroundStyle(Palette.tertiaryText)
                }
            } else if selecting {
                HStack {
                    Text(L10n.string("Seçili dosya: \(selection.count)"))
                        .adaFont(size: 10).foregroundStyle(Palette.tertiaryText)
                    if !selection.isEmpty {
                        ShelfBatchDragHandle(store: store, selection: selection, onInteraction: onInteraction)
                    }
                }
            } else {
                Text(L10n.string("Açmak için tıkla · Kullanmak için dışarı sürükle · Yalnızca raftaki kopya kaldırılır"))
                    .adaFont(size: 9).foregroundStyle(Palette.tertiaryText)
            }
        }
        .foregroundStyle(.white)
        .onChange(of: targeted) { _, _ in onInteraction(targeted || store.isImporting) }
        .onChange(of: store.isImporting) { _, _ in onInteraction(targeted || store.isImporting) }
        .onChange(of: store.items.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if ids.isEmpty { selecting = false }
        }
        .onDisappear { onInteraction(false); store.closeSharing() }
    }
}

private struct ShelfFileTile: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    let accent: Color
    let selecting: Bool
    let selected: Bool
    let toggleSelection: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 6) {
            Button {
                if selecting { toggleSelection() }
                else { store.open(item) }
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 15).fill(.white.opacity(hovering ? 0.13 : 0.07))
                    RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: store.fileURL(for: item).path))
                        .resizable().interpolation(.high).scaledToFit().frame(width: 45, height: 45)
                        .frame(width: 68, height: 68)
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? accent : Palette.secondaryText)
                            .padding(5)
                    }
                }.frame(width: 68, height: 68)
            }.buttonStyle(IslandButtonStyle(cornerRadius: 15, emphasis: true))
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(selecting ? L10n.string("Dosya seçimini değiştir") : L10n.string("\(item.name) dosyasını aç"))
            .onDrag { NSItemProvider(contentsOf: store.fileURL(for: item)) ?? NSItemProvider() }
            Text(item.name).adaFont(size: 10, weight: .medium).lineLimit(2)
                .multilineTextAlignment(.center).frame(width: 86, height: 26, alignment: .top)
            if !selecting {
                Button(L10n.string("Kaldır")) { store.remove(item) }
                    .adaFont(size: 10).buttonStyle(IslandButtonStyle()).foregroundStyle(Palette.tertiaryText)
            }
        }
        .frame(width: 86)
        .onHover { hovering = $0 }
        .task(id: item.id) {
            guard !item.isDirectory, thumbnail == nil else { return }
            let request = QLThumbnailGenerator.Request(fileAt: store.fileURL(for: item),
                size: CGSize(width: 90, height: 90), scale: displayScale, representationTypes: .thumbnail)
            if let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
               !Task.isCancelled {
                thumbnail = result.nsImage
            }
        }
        .contextMenu {
            Button(L10n.string("Aç")) { store.open(item) }
            Button(L10n.string("Finder’da göster")) { store.reveal(item) }
            Button(L10n.string("Paylaş…")) { store.shareFiles([item.id]) }
            Button(L10n.string("Panoya kopyala")) { store.copyFiles([item.id]) }
            Divider()
            Button(L10n.string("Raftan kaldır")) { store.remove(item) }
        }
    }
}
