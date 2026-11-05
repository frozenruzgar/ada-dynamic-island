@testable import Ada
@testable import AdaCore
import Foundation

enum CalendarChecks {
    static func main() {
        var us = Calendar(identifier: .gregorian)
        us.locale = Locale(identifier: "en_US")
        us.timeZone = TimeZone(secondsFromGMT: 0)!
        us.firstWeekday = 1
        var tr = us
        tr.locale = Locale(identifier: "tr_TR")
        tr.firstWeekday = 2
        let sunday = us.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let monday = us.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let thursday = us.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        precondition(CalendarPresentation.leadingDays(for: sunday, calendar: us) == 0)
        precondition(CalendarPresentation.leadingDays(for: sunday, calendar: tr) == 6)
        precondition(CalendarPresentation.leadingDays(for: monday, calendar: us) == 1)
        precondition(CalendarPresentation.leadingDays(for: monday, calendar: tr) == 0)
        precondition(CalendarPresentation.weekdays(calendar: us).first == "S")
        precondition(CalendarPresentation.weekdays(calendar: tr).first == "P")
        precondition(CalendarPresentation.weekdays(calendar: us).count == 7)
        let usWeek = CalendarPresentation.week(containing: thursday, calendar: us)
        let trWeek = CalendarPresentation.week(containing: thursday, calendar: tr)
        precondition(usWeek.count == 7 && trWeek.count == 7)
        precondition(us.isDate(usWeek[0], inSameDayAs: sunday))
        precondition(tr.isDate(trWeek[0], inSameDayAs: monday))
        precondition(us.dateComponents([.day], from: usWeek[0], to: usWeek[6]).day == 6)
        var nonGregorian = Calendar(identifier: .islamicUmmAlQura)
        nonGregorian.timeZone = us.timeZone
        nonGregorian.firstWeekday = nonGregorian.component(.weekday, from: thursday)
        precondition(CalendarPresentation.leadingDays(for: thursday, calendar: nonGregorian) == 0)
        precondition(CalendarMeetingLink.allowed(URL(string: "https://us04web.zoom.us/j/123")!))
        precondition(!CalendarMeetingLink.allowed(URL(string: "https://zoom.us.invalid/j/123")!))
        precondition(!CalendarMeetingLink.allowed(URL(string: "https://person@meet.google.com/abc")!))
        precondition(CalendarMeetingLink.first(url: nil, text: ["Meet at https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
        print("PASS: Turkish Monday and English Sunday labels, month padding, player week boundaries and a non-Gregorian calendar")
    }
}
