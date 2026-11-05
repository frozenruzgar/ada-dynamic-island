import AdaCore
import AppKit
import Combine
import Darwin
import SwiftUI

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var diskTotal: Int64?
    @Published private(set) var diskAvailable: Int64?
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var updatedAt: Date?
    @Published private(set) var sampling = false
    @Published var actionError: String?

    let modelIdentifier: String
    let processorName: String
    let processorCount: Int
    let totalMemory: UInt64
    private var previousTicks: CPUTickSample?
    private var ticker: Timer?
    private var sampleIndex = 0

    init(startImmediately: Bool = true) {
        modelIdentifier = Self.sysctlString("hw.model") ?? L10n.string("Mac")
        processorName = Self.sysctlString("machdep.cpu.brand_string") ?? L10n.string("Apple işlemci")
        processorCount = ProcessInfo.processInfo.processorCount
        totalMemory = ProcessInfo.processInfo.physicalMemory
        if startImmediately { start() }
    }

    func start() {
        guard ticker == nil else { return }
        previousTicks = nil
        cpuUsage = nil
        sampling = true
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.35
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        previousTicks = nil
        sampling = false
    }

    /// CPU/RAM sample every two seconds; disk every 30 seconds or explicitly.
    func refresh(forceDisk: Bool = false) {
        if let ticks = Self.readCPUTicks() {
            if let previousTicks, let value = CPUTickSample.utilization(previous: previousTicks, current: ticks) {
                cpuUsage = value
            }
            previousTicks = ticks
        } else { cpuUsage = nil; previousTicks = nil }
        memory = Self.readMemory(total: totalMemory)
        thermalState = ProcessInfo.processInfo.thermalState
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if forceDisk || sampleIndex % 15 == 0 { readDisk() }
        sampleIndex += 1
        updatedAt = Date()
    }

    var cpuLabel: String { cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    var thermalTitle: String {
        switch thermalState {
        case .nominal: return L10n.string("Normal")
        case .fair: return L10n.string("Orta")
        case .serious: return L10n.string("Yüksek")
        case .critical: return L10n.string("Kritik")
        @unknown default: return L10n.string("Bilinmiyor")
        }
    }
    var thermalColor: Color {
        switch thermalState {
        case .nominal: return .mint
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
    var diskFraction: Double {
        guard let total = diskTotal, let available = diskAvailable, total > 0 else { return 0 }
        return min(1, max(0, Double(total - available) / Double(total)))
    }

    func openActivityMonitor() {
        actionError = nil
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        guard NSWorkspace.shared.open(url) else {
            actionError = L10n.string("Etkinlik Monitörü açılamadı. Uygulamalar > İzlenceler bölümünden açabilirsin.")
            return
        }
    }

    func openStorageSettings() {
        actionError = nil
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage"), NSWorkspace.shared.open(url) else {
            actionError = L10n.string("Saklama Alanı ayarları açılamadı. Sistem Ayarları > Genel > Saklama Alanı bölümünü açabilirsin.")
            return
        }
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
    static func formatDisk(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private func readDisk() {
        // Query the volume containing the user's home directory rather than a
        // read-only system snapshot. The URL is never stored or transmitted.
        do {
            let values = try FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
            ])
            guard let total = values.volumeTotalCapacity, total > 0 else {
                diskTotal = nil; diskAvailable = nil; return
            }
            diskTotal = Int64(total)
            let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
            diskAvailable = available.map { min(Int64(total), max(0, $0)) }
        } catch { diskTotal = nil; diskAvailable = nil }
    }

    private static func readCPUTicks() -> CPUTickSample? {
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTickSample(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                             idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private static func readMemory(total: UInt64) -> MemorySnapshot? {
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        return MemorySnapshot.calculate(total: total, pageSize: UInt64(pageSize),
            anonymousPages: UInt64(info.internal_page_count), purgeablePages: UInt64(info.purgeable_count),
            wiredPages: UInt64(info.wire_count), compressorPages: UInt64(info.compressor_page_count))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

struct SystemView: View {
    @ObservedObject var monitor: SystemMonitor
    var accent: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Label(monitor.processorName, systemImage: "desktopcomputer")
                    .adaFont(size: 13, weight: .semibold).lineLimit(1)
                    .help(monitor.modelIdentifier)
                Spacer(minLength: 8)
                Button(L10n.string("Etkinlik Monitörü"), action: monitor.openActivityMonitor)
                    .adaFont(size: 10, weight: .medium).buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.78))
                Button {
                    monitor.refresh(forceDisk: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .adaFont(size: 10, weight: .semibold)
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 24)
                        .background(.white.opacity(0.05), in: Capsule())
                }
                .buttonStyle(IslandButtonStyle()).help(L10n.string("Yenile")).accessibilityLabel(L10n.string("Donanım bilgilerini yenile"))
            }
            HStack(spacing: 10) {
                metricCard(title: "CPU", symbol: "cpu", value: monitor.cpuLabel,
                           detail: L10n.string("\(monitor.processorCount) çekirdek"), fraction: monitor.cpuUsage) {
                    EmptyView()
                }
                metricCard(title: L10n.string("Bellek"), symbol: "memorychip",
                           value: monitor.memory.map { SystemMonitor.formatBytes($0.used) } ?? "—",
                           detail: L10n.string("\(SystemMonitor.formatBytes(monitor.totalMemory)) toplam"), fraction: monitor.memory?.fraction) {
                    EmptyView()
                }
                metricCard(title: L10n.string("Disk"), symbol: "internaldrive", value: SystemMonitor.formatDisk(monitor.diskAvailable),
                           detail: L10n.string("Boş / \(SystemMonitor.formatDisk(monitor.diskTotal))"), fraction: monitor.diskAvailable != nil ? monitor.diskFraction : nil) {
                    Button(L10n.string("Ayarlar"), action: monitor.openStorageSettings)
                        .foregroundStyle(accent).buttonStyle(IslandButtonStyle())
                        .accessibilityLabel(L10n.string("Saklama alanı ayarlarını aç"))
                }
                thermalCard
            }.frame(maxHeight: .infinity)
            if let error = monitor.actionError {
                HStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .adaFont(size: 10).foregroundStyle(.orange).lineLimit(2)
                    Spacer(minLength: 6)
                    Button(L10n.string("Kapat")) { monitor.actionError = nil }.adaFont(size: 10).buttonStyle(IslandButtonStyle())
                }
            }
        }.foregroundStyle(.white)
    }

    private func metricCard<Footer: View>(title: String, symbol: String, value: String, detail: String,
                                          fraction: Double?, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).adaFont(size: 11, weight: .semibold).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
            Text(value).adaFont(size: title == "CPU" ? 29 : 24, weight: .medium, design: .rounded)
                .monospacedDigit().lineLimit(1)
            Text(detail).adaFont(size: 10).foregroundStyle(Palette.tertiaryText).lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    if let fraction {
                        Capsule().fill(accent.opacity(0.78))
                            .frame(width: proxy.size.width * fraction)
                    }
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            footer().adaFont(size: 10).lineLimit(1)
        }
        .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .islandCardSurface(fill: AnyShapeStyle(glassFill), lineWidth: 0.65)
        .help(metricHelp(title))
    }

    private var glassFill: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.055), .white.opacity(0.016)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func metricHelp(_ title: String) -> String {
        switch title {
        case L10n.string("Bellek"):
            let compressed = monitor.memory.map { SystemMonitor.formatBytes($0.compressed) } ?? "—"
            return L10n.string("Sıkıştırılmış bellek: \(compressed). Kullanım buna ek olarak uygulamaların ve sistemin ayırdığı belleği içerir.")
        case L10n.string("Disk"):
            return L10n.string("macOS’un kullanılabilir saydığı alan. Çubuk diskin doluluk oranını gösterir.")
        default:
            return L10n.string("Tüm çekirdeklerdeki toplam işlemci kullanımı. İki saniyede bir ölçülür.")
        }
    }

    private var thermalCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L10n.string("Isıl durum"), systemImage: "gauge.with.dots.needle.33percent")
                .adaFont(size: 11, weight: .semibold).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(monitor.thermalColor).frame(width: 6, height: 6)
                Text(monitor.thermalTitle).adaFont(size: 19, weight: .medium)
            }
            Spacer(minLength: 0)
            Label(monitor.lowPowerMode ? L10n.string("Düşük güç") : L10n.string("Standart güç"), systemImage: "leaf")
                .adaFont(size: 10).foregroundStyle(monitor.lowPowerMode ? .mint : Palette.tertiaryText)
        }
        .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .islandCardSurface(fill: AnyShapeStyle(glassFill), lineWidth: 0.65)
        .help(L10n.string("macOS’un bildirdiği ısıl durum."))
    }
}
