import AdaCore
import Foundation

/// Turkish catalog keys remain stable. Values retain arguments separately so user
/// text is never treated as a format string or translated as a catalog key.
enum L10n {
    struct Value: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        var key: String
        var arguments: [String]

        init(stringLiteral value: String) { key = value; arguments = [] }
        init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []
            init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }
            mutating func appendLiteral(_ literal: String) { key += literal }
            mutating func appendInterpolation<T>(_ value: T) {
                key += "{\(arguments.count)}"
                arguments.append(String(describing: value))
            }
        }
    }

    static let resources: Bundle = {
        #if SWIFT_PACKAGE
        // SwiftPM's generated accessor assumes a command-line executable layout.
        // The hand-built .app keeps its resource bundle under Contents/Resources.
        if let url = Bundle.main.url(forResource: "Ada_Ada", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()

    static func string(_ value: Value, language: String? = nil, bundle: Bundle = resources) -> String {
        let requested = language ?? Locale.preferredLanguages.first ?? "tr"
        let code = requested.lowercased().hasPrefix("tr") ? "tr" : "en"
        let localized = bundle.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        let text = localized.localizedString(forKey: value.key, value: value.key, table: "Localizable")
        guard !value.arguments.isEmpty else { return text }
        // Replace matches backwards once; a user's argument containing "{1}" is
        // rendered literally and never interpreted as another placeholder.
        let pattern = try! NSRegularExpression(pattern: "\\{(\\d+)\\}")
        let result = NSMutableString(string: text)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let index = Int((text as NSString).substring(with: match.range(at: 1)))!
            if value.arguments.indices.contains(index) {
                result.replaceCharacters(in: match.range, with: value.arguments[index])
            }
        }
        return result as String
    }
}
