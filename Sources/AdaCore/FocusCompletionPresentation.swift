public struct FocusCompletionPresentation: Equatable, Sendable {
    public let shouldNotify: Bool
    public let shouldOpenPanel: Bool
    public init(islandVisible: Bool, openPanel: Bool, notifications: Bool) {
        shouldNotify = notifications
        shouldOpenPanel = islandVisible && openPanel
    }
}
