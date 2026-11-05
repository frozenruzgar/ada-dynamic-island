import Foundation

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public static let standard = ShortcutBinding(keyCode: 0, modifiers: control | option, key: "A")!

    public let keyCode: UInt32
    public let modifiers: UInt32
    public let key: String

    public init?(keyCode: UInt32, modifiers: UInt32, key: String) {
        let recognized = Self.command | Self.shift | Self.option | Self.control
        guard keyCode <= 127, modifiers & ~recognized == 0,
              modifiers & (Self.command | Self.control | Self.option) != 0,
              key.count == 1, key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = try Self(keyCode: values.decode(UInt32.self, forKey: .keyCode),
                                   modifiers: values.decode(UInt32.self, forKey: .modifiers),
                                   key: values.decode(String.self, forKey: .key)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid keyboard shortcut"))
        }
        self = value
    }

    public var title: String {
        let glyphs = [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
        return glyphs.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key.uppercased()
    }

    public func conflicts(with other: Self?) -> Bool {
        guard let other else { return false }
        return keyCode == other.keyCode && modifiers == other.modifiers
    }
}
