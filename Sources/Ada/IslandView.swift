import SwiftUI
import UniformTypeIdentifiers
import AdaCore

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
    var onOpenCompact: () -> Void
    var onSettings: () -> Void
    var onAddTile: () -> Void
    var onChangeTile: (DashboardTile) -> Void
    var onRequestKeyboardFocus: () -> Void = {}
    var onDismiss: () -> Void = {}
    @State private var dropTargeted = false
    @State private var pageBeforeMenu: IslandPage = .home
    @State private var requestedTileID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if model.expanded {
                expandedContent.padding(.top, model.contentTopInset).transition(.opacity).zIndex(1)
            }
            else { compactContent.transition(.asymmetric(insertion: .opacity, removal: .identity)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                if model.expanded {
                    backgroundSurface.transition(.asymmetric(
                        insertion: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.88, anchor: .top)),
                        removal: .identity))
                } else if model.compactVisible {
                    backgroundSurface.transition(.identity)
                }
            }
            .allowsHitTesting(false)
        }
        .clipShape(outline)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            let accepted = shelf.receiveProviders(providers)
            if accepted { onExpand(.files) }
            return accepted
        }
        .onChange(of: dropTargeted) { _, targeted in
            model.interactionHeld = targeted
            if targeted && model.preferences.openShelfOnDrag { onExpand(.files) }
        }
        .onHover { model.pointerInside = $0 }
        .onExitCommand {
            if model.page.isUtility { closeUtility() }
            else if model.expanded { onDismiss() }
        }
        .onChange(of: model.expanded) { _, expanded in
            if !expanded { requestedTileID = nil }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .environment(\.adaTextScale, model.preferences.textScale)
        .adaFont()
        .tint(model.accentColor)
        .accentColor(model.accentColor)
        .animation(reduceMotion ? nil : expansionAnimation, value: model.expanded)
        .alert("Ada", isPresented: Binding(get: { actions.errorMessage != nil }, set: { if !$0 { actions.clearError() } })) {
            Button(L10n.string("Tamam"), action: actions.clearError)
        } message: { Text(actions.errorMessage ?? "") }
    }

    private var radius: CGFloat { model.expanded ? (model.page == .player ? 18 : 23) : 15 }

    private var expansionAnimation: Animation {
        model.expanded ? .easeOut(duration: 0.10) : .easeInOut(duration: 0.18)
    }

    private var outline: UnevenRoundedRectangle {
        let upperRadius = model.flushToTop ? 0 : radius
        return UnevenRoundedRectangle(topLeadingRadius: upperRadius, bottomLeadingRadius: radius,
                                     bottomTrailingRadius: radius, topTrailingRadius: upperRadius)
    }

    @ViewBuilder private var backgroundSurface: some View {
        if model.expanded && model.page == .player {
            outline.fill(Color(white: 0.025))
        } else if !model.expanded && model.mediaIsPlaying {
            outline.fill(.black)
        } else if model.preferences.usesNebulaPalette {
            IslandAuroraSurface(tintIntensity: model.preferences.panelOpacity,
                isAnimated: model.preferences.backgroundMotion != .off && BackgroundMotionPolicy.permitsAnimation(
                    expanded: model.expanded, keyWindow: model.panelIsKey, pointerInside: model.pointerInside,
                    lowPower: model.lowPowerMode, batteryPercent: model.batteryPercent, reduceMotion: reduceMotion),
                framesPerSecond: model.preferences.backgroundMotion.framesPerSecond)
        } else {
            IslandSurface(palette: model.panelGradient, tintIntensity: model.preferences.panelOpacity,
                          shape: outline, backdropRadius: model.flushToTop ? 0 : radius)
        }
    }

    private var compactContent: some View {
        CompactIslandContent(model: model, focus: model.focus, media: media, onOpenCompact: onOpenCompact)
    }


    private var expandedContent: some View {
        let isPlayer = model.page == .player
        return VStack(spacing: 4) {
            Group {
                if isPlayer { playerHeader } else { header }
            }.padding(.horizontal, isPlayer ? 14 : 20).frame(height: model.topReserve)
            ZStack {
                pageContent
                    .id(model.page)
                    .transition(.asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)),
                                            removal: .identity))
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, isPlayer ? 12 : 16)
                .padding(.bottom, isPlayer ? 8 : 16)
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
            }, onAddTile: onAddTile, onChangeTile: onChangeTile, requestedTileID: requestedTileID)
        case .menu:
            WorkspaceHubView(model: model, onSettings: onSettings)
        case .files:
            FileShelfView(store: shelf, accent: model.accentColor, onInteraction: { model.interactionHeld = $0 || dropTargeted })
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
                        Text(L10n.string("Donanım izleme kapalı")).adaFont(size: 13, weight: .medium)
                        Button(L10n.string("İzlemeyi aç")) { model.preferences.monitoringEnabled = true }
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
        case .player:
            IslandPlayerView(store: media, accent: model.accentColor, onFiles: { model.selectPage(.files) }, showCalendarEvents: $model.preferences.showCalendarEvents)
        case .search:
            IslandSearchView(tiles: dashboard.tiles, workspace: workspace, shelf: shelf, accent: model.accentColor, onPage: openSearchPage,
                             onTile: openSearchTile, onClose: closeUtility)
        }
    }

    private func openUtility(_ page: IslandPage) {
        if page == .search { onRequestKeyboardFocus() }
        model.openUtility(page)
    }

    private func closeUtility() { model.closeUtility() }

    private func openSearchPage(_ page: IslandPage) {
        if page.isUtility { openUtility(page) }
        else { model.selectPage(page) }
    }

    private func openSearchTile(_ tile: DashboardTile) {
        switch tile.kind {
        case .chatGPT, .claude:
            assistant.provider = tile.kind == .chatGPT ? .chatGPT : .claude
            model.selectPage(.assistant)
        case .appleMusic, .spotify:
            media.openSource(tile.kind == .spotify ? .spotify : .appleMusic)
            openUtility(.player)
        case .files, .cloud, .system, .tools, .prompter:
            tile.openShortcut(model: model, actions: actions)
        case .app, .website, .mirror, .airDrop:
            closeUtility()
            tile.openShortcut(model: model, actions: actions)
        default:
            requestedTileID = tile.id
            model.selectPage(.home)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.page == .assistant ? assistant.provider.title : model.page.title)
                .adaFont(size: 14, weight: .semibold, design: .rounded)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if model.page == .home {
                Button(dashboard.isEditing ? L10n.string("Bitti") : L10n.string("Düzenle")) { dashboard.isEditing.toggle() }
                    .adaFont(size: 10, weight: .medium)
                    .padding(.horizontal, 3)
                    .buttonStyle(IslandButtonStyle())
                Button(action: onAddTile) {
                    Image(systemName: "plus").adaFont(size: 12, weight: .semibold)
                        .frame(width: 26, height: 26).modifier(IslandGlassButtonSurface())
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
                    .disabled(dashboard.tiles.count >= DashboardLayoutStore.maxTiles)
                    .accessibilityLabel(L10n.string("Kutucuk ekle"))
            }
            if !model.page.isUtility {
                playerButton
                Button { openUtility(.search) } label: {
                    Image(systemName: IslandPage.search.symbol).adaFont(size: 12, weight: .semibold)
                        .frame(width: 26, height: 26).modifier(IslandGlassButtonSurface())
                }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
                    .help(IslandPage.search.title)
                    .accessibilityLabel(IslandPage.search.title)
            }
            Button {
                if model.page.isUtility {
                    closeUtility()
                } else if model.page == .menu {
                    model.page = pageBeforeMenu
                } else {
                    pageBeforeMenu = model.page
                    model.page = .menu
                }
            } label: {
                let goesBack = model.page == .menu || model.page.isUtility
                Label(goesBack ? L10n.string("Geri") : L10n.string("Menü"), systemImage: goesBack ? "chevron.left" : "square.grid.2x2")
                    .adaFont(size: 11, weight: .semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .modifier(IslandGlassButtonSurface())
            }
            .buttonStyle(IslandButtonStyle(cornerRadius: 100))
        }
    }

    private var playerButton: some View {
        Button { openUtility(.player) } label: {
            if model.mediaIsPlaying, let track = media.track {
                HStack(spacing: 6) {
                    MediaArtworkView(image: track.artwork, size: 18)
                    Text(track.title).adaFont(size: 10, weight: .medium).lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                    if track.source == .spotify {
                        SpotifyBrandIcon(size: 21, circularMark: true)
                    } else {
                        Image(systemName: IslandPage.player.symbol).adaFont(size: 9)
                            .foregroundStyle(model.accentColor)
                    }
                }.padding(.horizontal, 7).padding(.vertical, 4)
                    .modifier(IslandGlassButtonSurface())
            } else {
                Image(systemName: IslandPage.player.symbol).adaFont(size: 12, weight: .semibold)
                    .frame(width: 26, height: 26).modifier(IslandGlassButtonSurface())
            }
        }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
            .help(IslandPage.player.title)
            .accessibilityLabel(IslandPage.player.title)
    }

    private var playerHeader: some View {
        HStack(spacing: 7) {
            Button { model.selectPage(.home) } label: {
                Image(systemName: "house.fill")
                    .adaFont(size: 11, weight: .semibold)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle(cornerRadius: 8))
            .accessibilityLabel(L10n.string("Ana ekran"))
            .help(L10n.string("Ana ekran"))
            Text(L10n.string("Oynatıcı"))
                .adaFont(size: 11, weight: .medium)
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 0)
            if let percent = model.batteryPercent {
                Label("\(percent)%", systemImage: model.batterySymbol)
                    .adaFont(size: 10, weight: .semibold)
                    .foregroundStyle(model.batteryColor)
                    .monospacedDigit()
            }
        }
    }
}

private struct CompactIslandContent: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var focus: FocusClockModel
    @ObservedObject var media: NowPlayingStore
    var onOpenCompact: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            if model.activityVisible {
                CompactActivityView(activities: model.activities)
                    .adaFont(size: 12, weight: .semibold)
                    .frame(height: model.closedHeight)
            } else if model.mediaIsPlaying, let track = media.track, track.isPlaying {
                CompactNowPlayingView(track: track, notchWidth: model.notchWidth, totalWidth: model.closedWidth,
                                      attached: model.attached && !model.compactMusicBelowMenu, accent: model.accentColor)
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
                                .adaFont(size: 17, weight: .medium).foregroundStyle(model.accentColor)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if model.clock.isRunning || model.clock.completed || model.remaining < model.clock.duration {
                            Text(focus.timeLabel).foregroundStyle(model.accentColor).monospacedDigit()
                        } else {
                            Image(systemName: "bolt.fill").foregroundStyle(model.accentColor)
                        }
                    }.frame(maxWidth: .infinity, alignment: .trailing)
                }
                .adaFont(size: 11, weight: .semibold, design: .rounded)
                .padding(.horizontal, 15)
                .frame(height: model.closedHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenCompact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.mediaIsPlaying ? L10n.string("\(media.track?.title ?? L10n.string("Müzik")) çalıyor. Ada’yı açmak için tıkla.") : model.clock.isRunning ? L10n.string("Ada, kalan süre \(focus.timeLabel). Açmak için tıkla.") : L10n.string("Ada. Açmak için tıkla."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpenCompact() }
        .help(model.mediaIsPlaying ? L10n.string("Oynatıcıyı aç") : L10n.string("Ada’yı aç"))
    }
}
