import Foundation
import Testing
@testable import PlanerCore

/// Wann ein Kurs stattfindet.
@Suite("Kurse")
struct CourseTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    /// 2026-10-05 ist ein Montag, KW 41 (ungerade).
    private let monday = DateKey(year: 2026, month: 10, day: 5)

    private func course(
        weekday: Int = 1,
        weeks: WeekPattern = .every,
        from: String = "2026-10-01",
        to: String = "2027-03-31"
    ) -> CourseItem {
        CourseItem(
            title: "Analysis II", kind: .lecture, weekday: weekday,
            start: ClockTime(hour: 8, minute: 15), end: ClockTime(hour: 9, minute: 45),
            room: "H 12", weeks: weeks,
            firstDay: DateKey(from)!, lastDay: DateKey(to)!
        )
    }

    // MARK: - Wochentag

    @Test func happensOnItsWeekdayOnly() {
        let item = course(weekday: 1)
        #expect(item.occurs(on: monday))
        #expect(!item.occurs(on: monday.adding(days: 1)))
        #expect(item.occurs(on: monday.adding(days: 7)))
        #expect(item.occurs(on: monday.adding(days: 70)))
    }

    @Test func sundayIsWeekdayZero() {
        let item = course(weekday: 0)
        #expect(item.occurs(on: day("2026-10-11")))
        #expect(!item.occurs(on: day("2026-10-12")))
    }

    // MARK: - Semester

    @Test func staysInsideTheSemester() {
        let item = course(from: "2026-10-12", to: "2027-02-01")
        #expect(!item.occurs(on: day("2026-10-05")))
        #expect(item.occurs(on: day("2026-10-12")))
        #expect(item.occurs(on: day("2027-02-01")))
        // Nach dem Semester verschwindet er von selbst - niemand muss zehn
        // Eintraege loeschen.
        #expect(!item.occurs(on: day("2027-02-08")))
    }

    // MARK: - Zweiwoechentlich

    @Test func everyOtherWeekFollowsTheCalendarWeek() {
        #expect(monday.weekOfYear == 41)

        let odd = course(weeks: .odd)
        let even = course(weeks: .even)

        #expect(odd.occurs(on: monday))
        #expect(!even.occurs(on: monday))

        #expect(!odd.occurs(on: monday.adding(days: 7)))
        #expect(even.occurs(on: monday.adding(days: 7)))
    }

    // MARK: - Ausfall

    @Test func cancelledSessionDoesNotHappen() {
        var item = course()
        item.skippedDates.insert(monday)
        #expect(!item.occurs(on: monday))
        // Nur diese eine Sitzung, nicht die Reihe.
        #expect(item.occurs(on: monday.adding(days: 7)))
    }

    @Test func findsItsNextSession() {
        let item = course(weekday: 3)
        #expect(item.nextSession(from: monday) == monday.adding(days: 2))
        #expect(item.nextSession(from: monday.adding(days: 2)) == monday.adding(days: 2))
        // Nach dem Semester gibt es keine mehr.
        #expect(course(to: "2026-10-06").nextSession(from: day("2026-11-01")) == nil)
    }

    // MARK: - Zeit

    @Test func spanCoversTheSession() {
        #expect(course().span.text == "08:15–09:45")
        #expect(course().span.minutes == 90)
    }

    @Test func endBeforeStartIsImpossible() {
        let item = CourseItem(
            title: "Kaputt",
            start: ClockTime(hour: 12),
            end: ClockTime(hour: 8)
        )
        #expect(item.end == item.start)
    }

    // MARK: - Datei

    @Test func survivesTheFile() throws {
        var original = course(weeks: .even)
        original.skippedDates = [monday]
        original.lecturer = "Prof. Weber"

        let raw = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(CourseItem.self, from: raw)

        #expect(restored == original)
        // Lesbar bleiben soll die Datei auch.
        let text = String(data: raw, encoding: .utf8) ?? ""
        #expect(text.contains("\"08:15\""))
        #expect(text.contains("\"2026-10-05\""))
    }

    @Test func oldFileWithoutFieldsStillLoads() throws {
        let raw = Data(#"{"title":"Nur ein Titel"}"#.utf8)
        let item = try JSONDecoder().decode(CourseItem.self, from: raw)
        #expect(item.title == "Nur ein Titel")
        #expect(item.kind == .lecture)
        #expect(item.weeks == .every)
    }

    // MARK: - Semestervorgabe

    @Test func semesterFollowsTheMonth() {
        let summer = Semester.current(on: day("2026-05-20"))
        #expect(summer.firstDay == day("2026-04-01"))
        #expect(summer.lastDay == day("2026-09-30"))
        #expect(summer.label == "Sommersemester 2026")

        let winter = Semester.current(on: day("2026-11-20"))
        #expect(winter.firstDay == day("2026-10-01"))
        #expect(winter.lastDay == day("2027-03-31"))
        #expect(winter.label == "Wintersemester 2026/27")

        // Januar gehoert zum Wintersemester, das im Vorjahr begonnen hat.
        let january = Semester.current(on: day("2027-01-15"))
        #expect(january.firstDay == day("2026-10-01"))
    }
}
