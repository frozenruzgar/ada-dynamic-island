import AppKit
import Carbon
import Combine

private let adaShortcutSignature: OSType = 0x41444148 // 'ADAH'
private let adaShortcutIdentifier: UInt32 = 1

/// Registers only Control + Option + A. It does not install a keyboard event tap,
/// read arbitrary keys, request Accessibility access, or record input.
@MainActor
final class AdaGlobalShortcut: ObservableObject {
    static let displayShortcut = "⌃⌥A"
    @Published private(set) var isRegistered = false
    @Published private(set) var errorMessage: String?
    private var action: (() -> Void)?
    private var activeContextID: UUID?
    private var registration: AdaHotKeyRegistration?

    var statusDescription: String {
        if let errorMessage { return errorMessage }
        return isRegistered ? "⌃⌥A ile Ada’yı aç / kapat" : "Genel kısayol kapalı"
    }

    /// Start again safely replaces this instance's previous registration.
    /// Capture the containing app delegate weakly in `handler` when it owns this object.
    @discardableResult
    func start(handler: @escaping () -> Void) -> Bool {
        stop()
        action = handler
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let context = AdaHotKeyContext(owner: self)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        var eventHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), adaHotKeyCallback,
                                                1, &event, contextPointer, &eventHandler)
        guard installStatus == noErr, let eventHandler else {
            Unmanaged<AdaHotKeyContext>.fromOpaque(contextPointer).release()
            action = nil
            errorMessage = "Kısayol dinleyicisi başlatılamadı (\(installStatus))."
            return false
        }

        let resource = AdaHotKeyRegistration(handler: eventHandler, contextPointer: contextPointer)
        let identifier = EventHotKeyID(signature: adaShortcutSignature, id: adaShortcutIdentifier)
        var hotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey),
                                                identifier, GetApplicationEventTarget(),
                                                OptionBits(kEventHotKeyExclusive), &hotKey)
        guard registerStatus == noErr, let hotKey else {
            resource.disposeOnMainThread()
            action = nil
            if registerStatus == OSStatus(eventHotKeyExistsErr) {
                errorMessage = "⌃⌥A başka bir uygulamada kullanılıyor. Ada’ya menü çubuğundan erişebilirsin."
            } else {
                errorMessage = "⌃⌥A kaydedilemedi (\(registerStatus)). Ada’ya menü çubuğundan erişebilirsin."
            }
            return false
        }
        resource.hotKey = hotKey
        registration = resource
        activeContextID = context.id
        isRegistered = true
        errorMessage = nil
        return true
    }

    func stop() {
        activeContextID = nil
        action = nil
        registration?.disposeOnMainThread()
        registration = nil
        isRegistered = false
        errorMessage = nil
    }

    fileprivate func handleShortcut(contextID: UUID) {
        guard isRegistered, activeContextID == contextID else { return }
        action?()
    }

    deinit {
        // Disposal retains only the registration/context, never the deinitializing owner.
        // Carbon cleanup always runs on the main thread even if the last reference is
        // released elsewhere. The context's weak owner avoids a dangling callback.
        registration?.disposeOnMainThread()
    }
}

private final class AdaHotKeyContext {
    let id = UUID()
    weak var owner: AdaGlobalShortcut?
    init(owner: AdaGlobalShortcut) { self.owner = owner }
}

/// C references remain owned until their main-thread cleanup has finished.
private final class AdaHotKeyRegistration: @unchecked Sendable {
    var hotKey: EventHotKeyRef?
    private let handler: EventHandlerRef
    private let contextPointer: UnsafeMutableRawPointer
    private var disposed = false // Accessed only by dispose(), on the main thread.

    init(handler: EventHandlerRef, contextPointer: UnsafeMutableRawPointer) {
        self.handler = handler
        self.contextPointer = contextPointer
    }

    func disposeOnMainThread() {
        if Thread.isMainThread { dispose() }
        else { DispatchQueue.main.async { self.dispose() } }
    }

    private func dispose() {
        guard !disposed else { return }
        disposed = true
        if let hotKey { UnregisterEventHotKey(hotKey) }
        // If Carbon unexpectedly refuses removal, keep its weak-owner context alive
        // rather than leave it pointing to freed storage. Process exit reclaims it.
        if RemoveEventHandler(handler) == noErr {
            Unmanaged<AdaHotKeyContext>.fromOpaque(contextPointer).release()
        }
        hotKey = nil
    }
}

private func adaHotKeyCallback(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?,
                               _ contextPointer: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let contextPointer,
          GetEventClass(event) == OSType(kEventClassKeyboard),
          GetEventKind(event) == UInt32(kEventHotKeyPressed) else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard status == noErr,
          identifier.signature == adaShortcutSignature,
          identifier.id == adaShortcutIdentifier else { return OSStatus(eventNotHandledErr) }
    let context = Unmanaged<AdaHotKeyContext>.fromOpaque(contextPointer).takeUnretainedValue()
    // App event-target callbacks normally arrive on the main thread. Scheduling the
    // action explicitly also keeps the actor contract correct if that ever changes.
    let contextID = context.id
    Task { @MainActor [weak owner = context.owner] in owner?.handleShortcut(contextID: contextID) }
    return noErr
}
