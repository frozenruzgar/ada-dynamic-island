import AdaCore
import Foundation
import IOKit.ps

@MainActor
protocol BatteryEventClient: AnyObject {
    func start(onChange: @escaping @MainActor @Sendable () -> Void) -> Bool
    func stop()
}

@MainActor
final class SystemBatteryEventClient: BatteryEventClient {
    private var source: CFRunLoopSource?
    private var onChange: (@MainActor @Sendable () -> Void)?
    func start(onChange: @escaping @MainActor @Sendable () -> Void) -> Bool {
        stop()
        self.onChange = onChange
        // IOKit does not retain the context. The owner holds this client until
        // stop invalidates/removes its main-run-loop source, before releasing it.
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<SystemBatteryEventClient>.fromOpaque(context).takeUnretainedValue().onChange?()
            }
        }, context)?.takeRetainedValue()
        guard let source else { self.onChange = nil; return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }
    func stop() {
        if let source {
            CFRunLoopSourceInvalidate(source)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        source = nil; onChange = nil
    }
    #if compiler(>=6.2)
    isolated deinit { stop() }
    #else
    deinit { MainActor.assumeIsolated { stop() } }
    #endif
}

@MainActor
final class BatteryEventMonitor {
    private let client: BatteryEventClient
    private var fallback: Timer?
    private(set) var usingFallback = false
    init(client: BatteryEventClient? = nil) { self.client = client ?? SystemBatteryEventClient() }
    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        onChange() // Initial snapshot is available before the first system event.
        if !client.start(onChange: onChange) {
            usingFallback = true
            let timer = Timer(timeInterval: 30, repeats: true) { _ in
                MainActor.assumeIsolated { onChange() }
            }
            timer.tolerance = 5
            fallback = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    func stop() { client.stop(); fallback?.invalidate(); fallback = nil; usingFallback = false }
    #if compiler(>=6.2)
    isolated deinit { stop() }
    #else
    deinit { MainActor.assumeIsolated { stop() } }
    #endif
}
