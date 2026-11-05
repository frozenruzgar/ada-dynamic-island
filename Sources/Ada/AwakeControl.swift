import AdaCore
import AppKit
import IOKit.pwr_mgt
import SwiftUI

@MainActor
final class AwakeStore: ObservableObject {
    @Published private(set) var until: Date?
    @Published private(set) var now = Date()
    @Published private(set) var error: String?
    @Published var minutes = 30
    private var assertion: IOPMAssertionID = 0
    private var ticker: Timer?
    var active: Bool { until != nil }
    var label: String {
        guard let until else { return L10n.string("Kapalı") }
        let remaining = max(0, Int(ceil(until.timeIntervalSince(now))))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
    func start() {
        guard !active else { return }
        error = nil
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), L10n.string("Ada: süreli ekran uykusunu önleme") as CFString, &identifier)
        guard result == kIOReturnSuccess else { error = L10n.string("Uyku önleme başlatılamadı."); return }
        assertion = identifier
        now = Date()
        until = now.addingTimeInterval(TimeInterval(min(120, max(1, minutes)) * 60))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                if let until = self.until, self.now >= until { self.stop() }
            }
        }
        timer.tolerance = 0.2
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        ticker?.invalidate(); ticker = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        until = nil
    }
}

struct AwakeControlView: View {
    @ObservedObject var store: AwakeStore
    let accent: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.active ? "cup.and.saucer.fill" : "cup.and.saucer")
                .adaFont(size: 19).foregroundStyle(store.active ? accent : .white.opacity(0.6))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("Uyanık tut")).adaFont(size: 12, weight: .semibold)
                Text(store.error ?? (store.active ? L10n.string("Etkin · \(store.label)") : L10n.string("Ekran uykusunu ertele")))
                    .adaFont(size: 10).foregroundStyle(Palette.tertiaryText)
            }
            Spacer(minLength: 6)
            Picker(L10n.string("Süre"), selection: $store.minutes) {
                ForEach([15, 30, 60, 120], id: \.self) { minutes in Text(L10n.string("\(minutes) dk")).tag(minutes) }
            }.labelsHidden().frame(width: 90).disabled(store.active)
            Button { store.active ? store.stop() : store.start() } label: {
                Text(store.active ? L10n.string("Durdur") : L10n.string("Başlat"))
                    .adaFont(size: 11, weight: .semibold)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .foregroundStyle(store.active ? .white : .black)
                    .background(store.active ? .white.opacity(0.12) : accent, in: Capsule())
            }.buttonStyle(IslandButtonStyle(cornerRadius: 100))
            .animation(.easeInOut(duration: 0.18), value: store.active)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .help(L10n.string("Süre sonunda ve Ada kapandığında bırakılır. Elle Uyut ve kapağı kapatma normal çalışır."))
    }
}
