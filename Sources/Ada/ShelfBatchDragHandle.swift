import AppKit
import SwiftUI

struct ShelfBatchDragHandle: View {
    let store: ShelfStore
    let selection: Set<UUID>
    let onInteraction: (Bool) -> Void

    var body: some View {
        Label(L10n.string("Seçili dosyaları dışarı sürükle"), systemImage: "arrow.up.right.square")
            .adaFont(size: 10, weight: .medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .islandCardSurface(cornerRadius: 6)
            .overlay {
                DragSource(files: { store.availableFiles(for: selection) }, onInteraction: onInteraction)
                    .accessibilityHidden(true)
            }
    }

    private struct DragSource: NSViewRepresentable {
        let files: () -> [URL]
        let onInteraction: (Bool) -> Void

        func makeNSView(context: Context) -> DragView { DragView() }

        func updateNSView(_ view: DragView, context: Context) {
            view.files = files
            view.onInteraction = onInteraction
        }
    }

    private final class DragView: NSView, NSDraggingSource {
        var files: () -> [URL] = { [] }
        var onInteraction: (Bool) -> Void = { _ in }
        private var hasStarted = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { hasStarted = false }

        override func mouseDragged(with event: NSEvent) {
            guard !hasStarted else { return }
            let urls = files()
            guard !urls.isEmpty else { return }
            hasStarted = true
            let location = convert(event.locationInWindow, from: nil)
            let items = urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(index, 4) * 3)
                let frame = NSRect(x: location.x - 16 + offset, y: location.y - 16 + offset,
                                   width: 32, height: 32)
                item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            onInteraction(true)
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            hasStarted = false
            onInteraction(false)
        }
    }
}
