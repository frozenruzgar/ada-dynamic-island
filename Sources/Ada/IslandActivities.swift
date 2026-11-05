import AppKit
import Combine
import IOBluetooth
import SwiftUI

struct IslandActivityOptions: Codable, Equatable, Sendable {
    var power = false
    var lowBattery = false
    var bluetooth = false
    var countdown = false
}

struct BatteryActivitySnapshot: Equatable {
    var percent: Int
    var pluggedIn: Bool

    enum Event: Equatable { case connected, disconnected, low }
    func events(after previous: Self?) -> [Event] {
        guard let previous else { return [] }
        var result: [Event] = []
        if previous.pluggedIn != pluggedIn { result.append(pluggedIn ? .connected : .disconnected) }
        if !pluggedIn && percent <= 20 && previous.percent > 20 { result.append(.low) }
        return result
    }
}

@MainActor
final class IslandActivityStore: NSObject, ObservableObject {
    struct Notice {
        let title: String
        let symbol: String
    }

    @Published private(set) var notice: Notice?
    @Published private(set) var deadline: Date?
    private var options = IslandActivityOptions()
    private var battery: BatteryActivitySnapshot?
    private var bluetoothObserver: IOBluetoothUserNotification?
    private var hide: Task<Void, Never>?
    private var finish: Task<Void, Never>?
    var visibilityChanged: (() -> Void)?

    func configure(_ options: IslandActivityOptions) {
        if options.bluetooth != self.options.bluetooth {
            bluetoothObserver?.unregister()
            bluetoothObserver = options.bluetooth
                ? IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
                : nil
        }
        self.options = options
        if !options.countdown, deadline != nil { cancelCountdown() }
    }

    func updateBattery(percent: Int?, pluggedIn: Bool) {
        guard let percent else { battery = nil; return }
        let new = BatteryActivitySnapshot(percent: percent, pluggedIn: pluggedIn)
        let changes = new.events(after: battery)
        battery = new
        for change in changes {
            switch change {
            case .connected where options.power:
                present(L10n.string("Güç adaptörü bağlandı"), symbol: "powerplug.fill")
            case .disconnected where options.power:
                present(L10n.string("Güç adaptörü çıkarıldı"), symbol: "powerplug")
            case .low where options.lowBattery:
                present(L10n.string("Pil düşük · %\(percent)"), symbol: "battery.25percent")
            default: break
            }
        }
    }

    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? L10n.string("Bluetooth aygıtı")
        Task { @MainActor [weak self] in
            guard let self, self.options.bluetooth else { return }
            self.present(L10n.string("\(name) bağlandı"), symbol: "headphones")
        }
    }

    func startCountdown(minutes: Int) {
        guard options.countdown, (1...60).contains(minutes) else { return }
        finish?.cancel()
        let interval = TimeInterval(minutes * 60)
        deadline = Date().addingTimeInterval(interval)
        visibilityChanged?()
        finish = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            catch { return }
            self?.completeIfNeeded()
        }
    }

    func completeIfNeeded(now: Date = .now) {
        guard let deadline, now >= deadline else { return }
        cancelCountdown()
        present(L10n.string("Geri sayım bitti"), symbol: "timer")
    }

    func cancelCountdown() {
        finish?.cancel()
        finish = nil
        deadline = nil
        visibilityChanged?()
    }

    func stop() {
        bluetoothObserver?.unregister()
        bluetoothObserver = nil
        hide?.cancel()
        cancelCountdown()
    }

    private func present(_ title: String, symbol: String) {
        hide?.cancel()
        notice = Notice(title: title, symbol: symbol)
        visibilityChanged?()
        hide = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) }
            catch { return }
            self?.notice = nil
            self?.visibilityChanged?()
        }
    }
}

struct CompactActivityView: View {
    @ObservedObject var activities: IslandActivityStore

    var body: some View {
        if let notice = activities.notice {
            Label(notice.title, systemImage: notice.symbol)
                .lineLimit(1).padding(.horizontal, 8)
        } else if let deadline = activities.deadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                Label(String(format: "%02d:%02d", seconds / 60, seconds % 60), systemImage: "timer")
                    .monospacedDigit()
            }
        }
    }
}
