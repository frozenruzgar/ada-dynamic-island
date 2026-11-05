import AdaCore
import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @ObservedObject var model: IslandModel
    @State private var destination: Destination?
    @State private var errorMessage: String?

    private enum Destination: String, Identifiable {
        case panel, files
        var id: String { rawValue }
    }

    var body: some View {
        Toggle(L10n.string("Genel klavye kısayolu"), isOn: $model.preferences.globalShortcutEnabled)
            .sheet(item: $destination, onDismiss: { model.recordingShortcut = false }) { target in
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.string("Yeni kısayola bas")).font(.headline)
                    Text(L10n.string("⌃, ⌥ veya ⌘ ile birlikte bir harf ya da rakam kullan."))
                    if let errorMessage { Text(errorMessage).foregroundStyle(.orange) }
                    Button(L10n.string("Vazgeç")) { destination = nil }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(24).frame(minWidth: 390, alignment: .leading)
                .background {
                    ShortcutKeyCapture { binding in save(binding, for: target) }
                }
            }
        HStack {
            Text(L10n.string("Adayı aç / kapat"))
            Spacer()
            Button(model.preferences.panelShortcut.title) { record(.panel) }
                .accessibilityLabel(L10n.string("Panel kısayolu: \(model.preferences.panelShortcut.title)"))
            Button(L10n.string("Sıfırla")) {
                if ShortcutBinding.standard.conflicts(with: model.preferences.filesShortcut) {
                    model.preferences.filesShortcut = nil
                }
                model.preferences.panelShortcut = .standard
            }
        }
        HStack {
            Text(L10n.string("Dosyaları aç"))
            Spacer()
            Button(model.preferences.filesShortcut?.title ?? L10n.string("Kaydet…")) { record(.files) }
                .accessibilityLabel(L10n.string("Dosyalar kısayolu: \(model.preferences.filesShortcut?.title ?? L10n.string("Kaydet…"))"))
            if model.preferences.filesShortcut != nil {
                Button(L10n.string("Kaldır")) { model.preferences.filesShortcut = nil }
                    .accessibilityLabel(L10n.string("Dosyalar kısayolunu kaldır"))
            }
        }
        if !model.shortcutStatus.isEmpty {
            Text(model.shortcutStatus).adaFont(size: Typography.caption).foregroundStyle(.orange)
        }
    }

    private func record(_ target: Destination) {
        errorMessage = nil
        model.recordingShortcut = true
        destination = target
    }

    private func save(_ binding: ShortcutBinding?, for target: Destination) {
        guard let binding else {
            errorMessage = L10n.string("Bu tuş birleşimi kullanılamıyor.")
            return
        }
        let other = target == .panel ? model.preferences.filesShortcut : model.preferences.panelShortcut
        guard !binding.conflicts(with: other) else {
            errorMessage = L10n.string("Bu kısayol Ada’da zaten kullanılıyor.")
            return
        }
        if target == .panel { model.preferences.panelShortcut = binding }
        else { model.preferences.filesShortcut = binding }
        destination = nil
    }
}

private struct ShortcutKeyCapture: NSViewRepresentable {
    var onInput: (ShortcutBinding?) -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) { view.onInput = onInput }

    final class CaptureView: NSView {
        var onInput: ((ShortcutBinding?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown, window?.firstResponder === self, event.keyCode != 53 else { return false }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { super.keyDown(with: event); return }
            guard !event.isARepeat else { return }
            let choices: [(NSEvent.ModifierFlags, UInt32)] = [
                (.command, ShortcutBinding.command), (.shift, ShortcutBinding.shift),
                (.option, ShortcutBinding.option), (.control, ShortcutBinding.control)
            ]
            let modifiers = choices.reduce(UInt32(0)) { mask, choice in
                event.modifierFlags.contains(choice.0) ? mask | choice.1 : mask
            }
            onInput?(ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                                     key: event.charactersIgnoringModifiers ?? ""))
        }
    }
}
