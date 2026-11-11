import Testing
@testable import PlanerCore

/// Bayerische Feiertage nach Spezifikation 4.18.
@Suite("Feiertage")
struct HolidayTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    /// Bekannte Ostersonntage - der Anker fuer alle beweglichen Feiertage.
    @Test("Ostersonntag", arguments: [
        (2024, "2024-03-31"), (2025, "2025-04-20"), (2026, "2026-04-05"),
        (2027, "2027-03-28"), (2028, "2028-04-16"), (2029, "2029-04-01"),
        (2030, "2030-04-21"),
    ])
    func easterSunday(year: Int, expected: String) {
        #expect(Holidays.easterSunday(year: year) == day(expected))
    }

    @Test func bavariaHasThirteenHolidays() {
        #expect(Holidays.inBavaria(year: 2026).count == 13)
    }

    /// Die vier beweglichen Feiertage 2026, gerechnet ab Ostersonntag 5. April.
    @Test func movableHolidays2026() {
        let names = Dictionary(
            uniqueKeysWithValues: Holidays.inBavaria(year: 2026).map { ($0.name, $0.day) }
        )
        #expect(names["Karfreitag"] == day("2026-04-03"))
        #expect(names["Ostermontag"] == day("2026-04-06"))
        #expect(names["Christi Himmelfahrt"] == day("2026-05-14"))
        #expect(names["Pfingstmontag"] == day("2026-05-25"))
        #expect(names["Fronleichnam"] == day("2026-06-04"))
    }

    @Test func fixedHolidays() {
        #expect(Holidays.name(on: day("2026-01-01")) == "Neujahr")
        #expect(Holidays.name(on: day("2026-01-06")) == "Heilige Drei Könige")
        #expect(Holidays.name(on: day("2026-05-01")) == "Tag der Arbeit")
        #expect(Holidays.name(on: day("2026-08-15")) == "Mariä Himmelfahrt")
        #expect(Holidays.name(on: day("2026-10-03")) == "Tag der Deutschen Einheit")
        #expect(Holidays.name(on: day("2026-11-01")) == "Allerheiligen")
        #expect(Holidays.name(on: day("2026-12-25")) == "1. Weihnachtstag")
        #expect(Holidays.name(on: day("2026-12-26")) == "2. Weihnachtstag")
    }

    /// Gegenprobe: Feiertage anderer Bundesländer gelten hier nicht.
    @Test func otherStatesHolidaysAreNotIncluded() {
        #expect(Holidays.name(on: day("2026-10-31")) == nil, "Reformationstag gilt nicht in Bayern")
        #expect(Holidays.name(on: day("2026-11-18")) == nil, "Buß- und Bettag gilt nur in Sachsen")
        #expect(Holidays.name(on: day("2026-03-08")) == nil, "Frauentag gilt nur in Berlin")
    }

    @Test func ordinaryDaysAreNotHolidays() {
        #expect(!Holidays.isHoliday(day("2026-09-04")))
        #expect(!Holidays.isHoliday(day("2026-04-04")), "Der Karsamstag ist kein Feiertag")
    }

    @Test func holidaysAreSortedByDate() {
        let days = Holidays.inBavaria(year: 2026).map(\.day)
        #expect(days == days.sorted())
    }

    /// Der Zwischenspeicher darf ueber Jahresgrenzen hinweg nicht durcheinander
    /// geraten.
    @Test func cacheKeepsYearsApart() {
        #expect(Holidays.name(on: day("2025-04-21")) == "Ostermontag")
        #expect(Holidays.name(on: day("2026-04-21")) == nil)
        #expect(Holidays.name(on: day("2026-04-06")) == "Ostermontag")
    }
}
