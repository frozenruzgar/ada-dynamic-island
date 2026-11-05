import AdaCore
import Foundation

/// Date labels and grid alignment use the same user's calendar and week origin.
enum CalendarPresentation {
    static func weekdays(calendar: Calendar = .autoupdatingCurrent) -> [String] {
        let labels = calendar.veryShortWeekdaySymbols
        let start = min(labels.count - 1, max(0, calendar.firstWeekday - 1))
        return Array(labels[start...]) + Array(labels[..<start])
    }

    static func week(containing date: Date, calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [date] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func leadingDays(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }
}
