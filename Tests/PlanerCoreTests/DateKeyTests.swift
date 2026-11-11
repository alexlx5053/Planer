import Testing
@testable import PlanerCore

@Suite("DateKey")
struct DateKeyTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    @Test func parsingAndFormatting() {
        let key = DateKey("2026-09-04")
        #expect(key?.year == 2026)
        #expect(key?.month == 9)
        #expect(key?.day == 4)
        #expect(key?.rawValue == "2026-09-04")
    }

    @Test func formattingPadsSingleDigits() {
        #expect(DateKey(year: 2026, month: 1, day: 5).rawValue == "2026-01-05")
    }

    @Test("Unbrauchbare Eingaben werden abgewiesen",
          arguments: ["2026-09", "heute", "2026-13-01", "2026-09-00", ""])
    func rejectsMalformedInput(raw: String) {
        #expect(DateKey(raw) == nil)
    }

    @Test func ordering() {
        #expect(day("2026-09-04") < day("2026-09-05"))
        #expect(day("2025-12-31") < day("2026-01-01"))
        #expect(day("2026-01-31") < day("2026-02-01"))
    }

    @Test func addingDaysCrossesMonthAndYearBoundaries() {
        #expect(day("2026-01-31").adding(days: 1) == day("2026-02-01"))
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
        #expect(day("2026-03-01").adding(days: -1) == day("2026-02-28"))
    }

    /// 2024 ist ein Schaltjahr, 2026 nicht.
    @Test func leapYear() {
        #expect(day("2024-02-28").adding(days: 1) == day("2024-02-29"))
        #expect(day("2026-02-28").adding(days: 1) == day("2026-03-01"))
        #expect(day("2024-02-01").daysInMonth == 29)
        #expect(day("2026-02-01").daysInMonth == 28)
    }

    /// Zaehlung der Spezifikation: 0 = Sonntag ... 6 = Samstag.
    @Test func weekdayIndex() {
        #expect(day("2026-09-04").weekdayIndex == 5) // Freitag
        #expect(day("2026-09-06").weekdayIndex == 0) // Sonntag
        #expect(day("2026-09-07").weekdayIndex == 1) // Montag
        #expect(day("2026-01-01").weekdayIndex == 4) // Donnerstag
    }

    @Test func weekendDetection() {
        #expect(day("2026-09-05").isWeekend)  // Samstag
        #expect(day("2026-09-06").isWeekend)  // Sonntag
        #expect(!day("2026-09-07").isWeekend) // Montag
    }

    /// Die Woche beginnt montags - ein Sonntag gehoert zur *vorherigen* Woche.
    @Test func startOfWeekIsMonday() {
        #expect(day("2026-09-04").startOfWeek == day("2026-08-31"))
        #expect(day("2026-09-06").startOfWeek == day("2026-08-31"))
        #expect(day("2026-09-07").startOfWeek == day("2026-09-07"))
    }

    @Test func daysUntil() {
        #expect(day("2026-09-04").days(until: day("2026-09-11")) == 7)
        #expect(day("2026-09-11").days(until: day("2026-09-04")) == -7)
        #expect(day("2026-09-04").days(until: day("2026-09-04")) == 0)
    }

    /// An der Sommerzeitgrenze darf sich ein Tag nicht auf den Nachbartag
    /// verschieben - der Grund, weshalb `date` mittags statt mitternachts liegt.
    /// 2026 wird in Deutschland am 29.03. und am 25.10. umgestellt.
    @Test func daylightSavingBoundary() {
        #expect(day("2026-03-28").adding(days: 1) == day("2026-03-29"))
        #expect(day("2026-03-29").adding(days: 1) == day("2026-03-30"))
        #expect(day("2026-10-24").adding(days: 1) == day("2026-10-25"))
        #expect(day("2026-10-25").adding(days: 1) == day("2026-10-26"))
        #expect(DateKey(day("2026-03-29").date) == day("2026-03-29"))
    }

    @Test func roundTripThroughDateOverAFullYear() {
        for offset in 0..<400 {
            let key = day("2026-01-01").adding(days: offset)
            #expect(DateKey(key.date) == key, "Rundlauf fehlgeschlagen bei \(key)")
        }
    }
}
