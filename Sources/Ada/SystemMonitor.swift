import AppKit
import Combine
import Darwin
import SwiftUI

/// Successive aggregate kernel CPU tick counters, not the system load average.
struct CPUTickSample: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    /// UInt32 subtraction deliberately wraps when a kernel tick counter wraps.
    static func utilization(previous: Self, current: Self) -> Double? {
        let user = UInt64(current.user &- previous.user)
        let system = UInt64(current.system &- previous.system)
        let idle = UInt64(current.idle &- previous.idle)
        let nice = UInt64(current.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return min(1, max(0, Double(user + system + nice) / Double(total)))
    }
}

struct MemorySnapshot: Equatable {
    let total: UInt64
    let used: UInt64
    let compressed: UInt64
    let wired: UInt64
    var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }

    /// Anonymous resident pages minus purgeable pages, plus wired and physically
    /// occupied compressor pages. Uncompressed logical pages in the compressor
    /// are not added; compressed memory is already a subset of `used`.
    static func calculate(total: UInt64, pageSize: UInt64, anonymousPages: UInt64,
                          purgeablePages: UInt64, wiredPages: UInt64, compressorPages: UInt64) -> Self {
        let anonymous = anonymousPages > purgeablePages ? anonymousPages - purgeablePages : 0
        let compressed = compressorPages * pageSize
        let wired = wiredPages * pageSize
        let used = min(total, anonymous * pageSize + wired + compressed)
        return Self(total: total, used: used, compressed: min(total, compressed), wired: min(total, wired))
    }
}

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
        modelIdentifier = Self.sysctlString("hw.model") ?? "Mac"
        processorName = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple işlemci"
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
        case .nominal: return "Normal"
        case .fair: return "Orta"
        case .serious: return "Yüksek"
        case .critical: return "Kritik"
        @unknown default: return "Bilinmiyor"
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
            actionError = "Etkinlik Monitörü açılamadı. Uygulamalar > İzlenceler bölümünden açabilirsin."
            return
        }
    }

    func openStorageSettings() {
        actionError = nil
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage"), NSWorkspace.shared.open(url) else {
            actionError = "Saklama Alanı ayarları açılamadı. Sistem Ayarları > Genel > Saklama Alanı bölümünü açabilirsin."
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
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .help(monitor.modelIdentifier)
                Spacer(minLength: 8)
                Button("Etkinlik Monitörü", action: monitor.openActivityMonitor)
                    .font(.system(size: 10, weight: .medium)).buttonStyle(IslandButtonStyle()).foregroundStyle(.white.opacity(0.78))
                Button {
                    monitor.refresh(forceDisk: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 24)
                        .background(.white.opacity(0.05), in: Capsule())
                }
                .buttonStyle(IslandButtonStyle()).help("Yenile").accessibilityLabel("Donanım bilgilerini yenile")
            }
            HStack(spacing: 10) {
                metricCard(title: "CPU", symbol: "cpu", value: monitor.cpuLabel,
                           detail: "\(monitor.processorCount) çekirdek", fraction: monitor.cpuUsage) {
                    EmptyView()
                }
                metricCard(title: "Bellek", symbol: "memorychip",
                           value: monitor.memory.map { SystemMonitor.formatBytes($0.used) } ?? "—",
                           detail: "\(SystemMonitor.formatBytes(monitor.totalMemory)) toplam", fraction: monitor.memory?.fraction) {
                    EmptyView()
                }
                metricCard(title: "Disk", symbol: "internaldrive", value: SystemMonitor.formatDisk(monitor.diskAvailable),
                           detail: "Boş / \(SystemMonitor.formatDisk(monitor.diskTotal))", fraction: monitor.diskAvailable != nil ? monitor.diskFraction : nil) {
                    Button("Ayarlar", action: monitor.openStorageSettings)
                        .foregroundStyle(accent).buttonStyle(IslandButtonStyle())
                        .accessibilityLabel("Saklama alanı ayarlarını aç")
                }
                thermalCard
            }.frame(maxHeight: .infinity)
            if let error = monitor.actionError {
                HStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
                    Spacer(minLength: 6)
                    Button("Kapat") { monitor.actionError = nil }.font(.system(size: 10)).buttonStyle(IslandButtonStyle())
                }
            }
        }.foregroundStyle(.white)
    }

    private func metricCard<Footer: View>(title: String, symbol: String, value: String, detail: String,
                                          fraction: Double?, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
            Text(value).font(.system(size: title == "CPU" ? 29 : 24, weight: .medium, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
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
            footer().font(.system(size: 10)).lineLimit(1)
        }
        .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(glassFill, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.085), lineWidth: 0.65).allowsHitTesting(false))
        .help(metricHelp(title))
    }

    private var glassFill: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.055), .white.opacity(0.016)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func metricHelp(_ title: String) -> String {
        switch title {
        case "Bellek":
            let compressed = monitor.memory.map { SystemMonitor.formatBytes($0.compressed) } ?? "—"
            return "Sıkıştırılmış bellek: \(compressed). Kullanım buna ek olarak uygulamaların ve sistemin ayırdığı belleği içerir."
        case "Disk":
            return "macOS’un kullanılabilir saydığı alan. Çubuk diskin doluluk oranını gösterir."
        default:
            return "Tüm çekirdeklerdeki toplam işlemci kullanımı. İki saniyede bir ölçülür."
        }
    }

    private var thermalCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Isıl durum", systemImage: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(monitor.thermalColor).frame(width: 6, height: 6)
                Text(monitor.thermalTitle).font(.system(size: 19, weight: .medium))
            }
            Spacer(minLength: 0)
            Label(monitor.lowPowerMode ? "Düşük güç" : "Standart güç", systemImage: "leaf")
                .font(.system(size: 10)).foregroundStyle(monitor.lowPowerMode ? .mint : .white.opacity(0.55))
        }
        .padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(glassFill, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.085), lineWidth: 0.65).allowsHitTesting(false))
        .help("macOS’un bildirdiği ısıl durum.")
    }
}
