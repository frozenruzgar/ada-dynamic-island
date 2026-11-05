@testable import Ada
@testable import AdaCore
import Foundation

enum LocalizationChecks {
    static func main() throws {
        let resources = URL(fileURLWithPath: "Sources/Ada/Resources", isDirectory: true)
        let bundle = Bundle(url: resources)!
        precondition(L10n.string("Ana ekran", language: "tr", bundle: bundle) == "Ana ekran")
        precondition(L10n.string("Ana ekran", language: "en", bundle: bundle) == "Home")
        let count = 7
        precondition(L10n.string("\(count) dakika", language: "en", bundle: bundle) == "7 minutes")
        precondition(L10n.string("\(count) dakika", language: "tr", bundle: bundle) == "7 dakika")
        let literal = "{1} %@ 100%"
        precondition(L10n.string("\(literal) · \(count)", language: "en", bundle: bundle) == literal + " · 7")
        precondition(L10n.string("Ana ekran", language: "de", bundle: bundle) == "Home")
        let data = try Data(contentsOf: resources.appendingPathComponent("Localizable.xcstrings"))
        let catalog = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let entries = catalog["strings"] as! [String: [String: Any]]
        let placeholders = try NSRegularExpression(pattern: "\\{\\d+\\}")
        for (key, entry) in entries {
            let localized = entry["localizations"] as! [String: [String: [String: String]]]
            let english = localized["en"]!["stringUnit"]!["value"]!
            let turkish = localized["tr"]!["stringUnit"]!["value"]!
            precondition(turkish == key && !english.isEmpty)
            func tokens(_ string: String) -> [String] {
                placeholders.matches(in: string, range: NSRange(string.startIndex..., in: string))
                    .map { (string as NSString).substring(with: $0.range) }.sorted()
            }
            precondition(tokens(english) == tokens(key), key)
        }
        print("PASS: TR/EN catalog coverage, argument preservation, literal user text, unsupported-language fallback and \(entries.count) translations")
    }
}
