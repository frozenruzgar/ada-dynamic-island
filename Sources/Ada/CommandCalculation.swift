import Foundation

enum CommandCalculation {
    static func evaluate(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 100 else { return nil }
        let text = trimmed.replacingOccurrences(of: ",", with: ".")
        if let converted = convert(text.lowercased()) { return converted }

        let expression = text.hasPrefix("=") ? String(text.dropFirst()) : text
        guard text.hasPrefix("=") || expression.contains(where: { "+-*/×÷".contains($0) }) else { return nil }
        var parser = ArithmeticParser(expression)
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return formatted(value)
    }

    private static func convert(_ text: String) -> String? {
        let parts = text.replacingOccurrences(of: "→", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .filter { $0 != "to" && $0 != "inches" }
        guard parts.count == 3, let value = Double(parts[0]), value.isFinite else { return nil }
        let converted: Double
        switch (parts[1], parts[2]) {
        case ("cm", "in"): converted = value / 2.54
        case ("in", "cm"): converted = value * 2.54
        case ("kg", "lb"): converted = value * 2.2046226218
        case ("lb", "kg"): converted = value / 2.2046226218
        case ("c", "f"), ("°c", "°f"): converted = value * 1.8 + 32
        case ("f", "c"), ("°f", "°c"): converted = (value - 32) / 1.8
        case ("km", "mi"): converted = value / 1.609344
        case ("mi", "km"): converted = value * 1.609344
        default: return nil
        }
        guard converted.isFinite else { return nil }
        return formatted(converted) + " " + parts[2]
    }

    private static func formatted(_ number: Double) -> String {
        number.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    }
}

private struct ArithmeticParser {
    private let characters: [Character]
    private var index = 0
    init(_ input: String) { characters = input.filter { !$0.isWhitespace }.map { $0 } }
    var atEnd: Bool { index == characters.count }
    private var next: Character? { atEnd ? nil : characters[index] }

    mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while let sign = next, sign == "+" || sign == "-" {
            index += 1
            guard let right = term() else { return nil }
            value = sign == "+" ? value + right : value - right
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while let sign = next, "*/×÷".contains(sign) {
            index += 1
            guard let right = factor() else { return nil }
            value = sign == "*" || sign == "×" ? value * right : value / right
        }
        return value
    }

    private mutating func factor() -> Double? {
        if next == "-" || next == "+" {
            let negative = next == "-"
            index += 1
            return factor().map { negative ? -$0 : $0 }
        }
        if next == "(" {
            index += 1
            guard let value = expression(), next == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        while let digit = next, digit.isASCII && (digit.isNumber || digit == ".") { index += 1 }
        guard index > start else { return nil }
        return Double(String(characters[start..<index]))
    }
}
