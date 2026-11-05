import AppKit
import EventKit
import SwiftUI

enum CalendarMeetingLink {
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return host == "zoom.us" || host.hasSuffix(".zoom.us") ||
            host == "meet.google.com" || host == "teams.microsoft.com" || host == "teams.live.com"
    }

    static func first(url: URL?, text: [String]) -> URL? {
        if let url, allowed(url) { return url }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for value in text {
            let range = NSRange(value.startIndex..., in: value)
            if let link = detector.matches(in: value, range: range).compactMap(\.url).first(where: allowed) {
                return link
            }
        }
        return nil
    }
}

struct UpcomingEventsView: View {
    @Binding var enabled: Bool
    var showControls = true
    @State private var store: EKEventStore?
    @State private var events: [Entry] = []
    @State private var requesting = false
    @State private var denied = false

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let start: Date
        let link: URL?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showControls {
                HStack {
                    Label(L10n.string("Yaklaşan etkinlikler"), systemImage: "calendar")
                        .fontWeight(.semibold)
                    Spacer()
                    if enabled {
                        Button(L10n.string("Kapat")) { enabled = false }
                    } else {
                        Button(L10n.string("Takvimi bağla")) { Task { await request() } }
                            .disabled(requesting)
                    }
                }
            }
            if requesting {
                ProgressView().controlSize(.small)
            } else if denied {
                Text(L10n.string("Takvim iznini macOS Gizlilik ve Güvenlik ayarlarından verebilirsin."))
                    .foregroundStyle(Palette.tertiaryText)
            } else if enabled && events.isEmpty {
                Text(L10n.string("Yaklaşan etkinlik yok")).foregroundStyle(Palette.tertiaryText)
            }
            ForEach(events) { event in
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).lineLimit(1)
                        Text(event.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .foregroundStyle(Palette.tertiaryText).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let link = event.link {
                        Button(L10n.string("Katıl")) { NSWorkspace.shared.open(link) }
                    }
                }
            }
        }
        .adaFont(size: 10)
        .buttonStyle(IslandButtonStyle())
        .task(id: enabled) {
            if enabled { refresh() }
            else { events = []; store = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main)) { _ in
            if enabled { refresh() }
        }
    }

    private func request() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        let source = store ?? EKEventStore()
        store = source
        let granted = (try? await source.requestFullAccessToEvents()) == true
        denied = !granted
        enabled = granted
        if granted { refresh() }
    }

    private func refresh() {
        guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            denied = enabled
            events = []
            return
        }
        denied = false
        let source = store ?? EKEventStore()
        store = source
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = source.predicateForEvents(withStart: now, end: end, calendars: nil)
        let upcoming = source.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(showControls ? 3 : 2)
        events = upcoming.enumerated().map { index, event in
            Entry(id: "\(index)-\(event.eventIdentifier ?? "")",
                  title: event.title ?? L10n.string("Takvim etkinliği"), start: event.startDate,
                  link: CalendarMeetingLink.first(url: event.url, text: [event.location, event.notes].compactMap { $0 }))
        }
    }
}
