import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var actions: QuickActionStore
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var prompter: PrompterStore
    @ObservedObject var assistant: AssistantStore
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var cloud: CloudWorkspaceStore
    @ObservedObject var awake: AwakeStore
    @ObservedObject var dashboard: DashboardLayoutStore
    @ObservedObject var media: NowPlayingStore
    var onExpand: (IslandPage?) -> Void
    var onSettings: () -> Void
    var onAddTile: () -> Void
    var onChangeTile: (DashboardTile) -> Void
    @State private var dropTargeted = false
    @State private var pageBeforeMenu: IslandPage = .home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if model.expanded {
                expandedContent.padding(.top, model.menuClearance).transition(.opacity)
            }
            else { compactContent.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if model.expanded || model.compactVisible {
                if !model.expanded && model.mediaIsPlaying {
                    outline.fill(.black)
                } else {
                    IslandSurface(palette: model.panelGradient, tintIntensity: model.preferences.panelOpacity,
                                  shape: outline, backdropRadius: model.flushToTop ? 0 : radius)
                }
            }
        }
        .clipShape(outline)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            onExpand(.files)
            shelf.receiveProviders(providers)
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            model.interactionHeld = targeted
            if targeted { onExpand(.files) }
        }
        .preferredColorScheme(.dark)
        .tint(model.accentColor)
        .accentColor(model.accentColor)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.expanded)
        .alert("Ada", isPresented: Binding(get: { actions.errorMessage != nil }, set: { if !$0 { actions.clearError() } })) {
            Button("Tamam", action: actions.clearError)
        } message: { Text(actions.errorMessage ?? "") }
    }

    private var radius: CGFloat { model.expanded ? 23 : 15 }

    private var outline: UnevenRoundedRectangle {
        let upperRadius = model.flushToTop ? 0 : radius
        return UnevenRoundedRectangle(topLeadingRadius: upperRadius, bottomLeadingRadius: radius,
                                     bottomTrailingRadius: radius, topTrailingRadius: upperRadius)
    }

    private var compactContent: some View {
        ZStack(alignment: .top) {
            if model.mediaIsPlaying, let track = media.track, track.isPlaying {
                CompactNowPlayingView(track: track, notchWidth: model.notchWidth, totalWidth: model.closedWidth,
                                      attached: model.attached, accent: model.accentColor)
            } else if model.compactHasContent {
                HStack(spacing: 8) {
                    Group {
                        if model.preferences.showCompactBattery {
                            HStack(spacing: 4) {
                                Image(systemName: model.batterySymbol)
                                Text(model.batteryPercent.map { "\($0)%" } ?? "—")
                            }.foregroundStyle(model.batteryColor)
                        } else {
                            Image(systemName: model.clock.completed ? "checkmark.circle.fill" : "timer")
                                .font(.system(size: 17, weight: .medium)).foregroundStyle(model.accentColor)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if model.clock.isRunning || model.clock.completed || model.remaining < model.clock.duration {
                            Text(model.timeLabel).foregroundStyle(model.accentColor).monospacedDigit()
                        } else {
                            Image(systemName: "bolt.fill").foregroundStyle(model.accentColor)
                        }
                    }.frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 15)
                .frame(height: model.closedHeight)
            } else if model.compactVisible {
                HStack(spacing: 7) {
                    Circle().fill(model.accentColor).frame(width: 5, height: 5)
                    Text("Ada").font(.system(size: 12, weight: .medium))
                }.frame(height: model.closedHeight)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onExpand(nil) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.mediaIsPlaying ? "\(media.track?.title ?? "Müzik") çalıyor. Ada’yı açmak için tıkla." : model.clock.isRunning ? "Ada, kalan süre \(model.timeLabel). Açmak için tıkla." : "Ada. Açmak için tıkla.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onExpand(nil) }
        .help("Ada’yı aç")
    }


    private var expandedContent: some View {
        VStack(spacing: 6) {
            header.padding(.horizontal, 20).frame(height: model.topReserve)
            ZStack {
                pageContent
                    .id(model.page)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86), value: model.page)
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page {
        case .home:
            DashboardView(model: model, workspace: workspace, actions: actions, layout: dashboard, media: media, onUseNote: {
                assistant.draft = workspace.note
                assistant.task = .summarize
                model.selectPage(.assistant)
            }, onOpenAssistant: { provider in
                assistant.provider = provider
                model.selectPage(.assistant)
            }, onAddTile: onAddTile, onChangeTile: onChangeTile)
        case .menu:
            WorkspaceHubView(model: model, onSettings: onSettings)
        case .files:
            FileShelfView(store: shelf, accent: model.accentColor)
        case .assistant:
            AssistantView(store: assistant, accent: model.accentColor, onSelectProvider: {
                model.selectPage(.assistant)
            })
        case .system:
            VStack(spacing: 10) {
                AwakeControlView(store: awake, accent: model.accentColor)
                if model.preferences.monitoringEnabled {
                    SystemView(monitor: monitor, accent: model.accentColor)
                } else {
                    VStack(spacing: 10) {
                        Text("Donanım izleme kapalı").font(.system(size: 13, weight: .medium))
                        Button("İzlemeyi aç") { model.preferences.monitoringEnabled = true }
                            .buttonStyle(IslandButtonStyle())
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .cloud:
            CloudWorkspaceView(store: cloud, accent: model.accentColor)
        case .tools:
            ToolsView(model: model, workspace: workspace)
        case .prompter:
            TeleprompterView(store: prompter, accent: model.accentColor)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.page == .assistant ? assistant.provider.title : model.page.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            if model.mediaIsPlaying, let track = media.track {
                Button { media.openSource(track.source) } label: {
                    HStack(spacing: 6) {
                        MediaArtworkView(image: track.artwork, size: 18)
                        Text(track.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            .frame(maxWidth: 120, alignment: .leading)
                        Image(systemName: "waveform").font(.system(size: 9)).foregroundStyle(model.accentColor)
                    }.padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.white.opacity(0.06), in: Capsule())
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
                    .help("\(track.title) · \(track.artist)")
                    .accessibilityLabel("Çalıyor: \(track.title), \(track.artist)")
            }
            if model.page == .home {
                Button(dashboard.isEditing ? "Bitti" : "Düzenle") { dashboard.isEditing.toggle() }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 3)
                    .buttonStyle(IslandButtonStyle())
                Button(action: onAddTile) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26).modifier(IslandGlassButtonSurface())
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
                    .disabled(dashboard.tiles.count >= DashboardLayoutStore.maxTiles)
                    .accessibilityLabel("Kutucuk ekle")
            }
            Button {
                if model.page == .menu {
                    model.page = pageBeforeMenu
                } else {
                    pageBeforeMenu = model.page
                    model.page = .menu
                }
            } label: {
                Label(model.page == .menu ? "Geri" : "Menü", systemImage: model.page == .menu ? "chevron.left" : "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .modifier(IslandGlassButtonSurface())
            }
            .buttonStyle(IslandButtonStyle(cornerRadius: 100))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
