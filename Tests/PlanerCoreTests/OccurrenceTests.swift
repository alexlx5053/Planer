import Testing
@testable import PlanerCore

/// Wiederholungslogik nach Spezifikation 4.8.
@Suite("Wiederholung")
struct OccurrenceTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    private func task(
        _ recurrence: Recurrence,
        from start: String,
        weekdays: Set<Int> = [],
        months: Set<Int> = []
    ) -> TaskItem {
        TaskItem(title: "Test", startDate: day(start), recurrence: recurrence,
                 weekdays: weekdays, months: months)
    }

    // MARK: - none

    @Test func singleOccurrenceOnlyOnItsDate() {
        let item = task(.none, from: "2026-09-04")
        #expect(item.occurs(on: day("2026-09-04")))
        #expect(!item.occurs(on: day("2026-09-05")))
        #expect(!item.occurs(on: day("2026-09-03")))
    }

    // MARK: - daily

    @Test func dailyStartsAtItsDateAndNeverBefore() {
        let item = task(.daily, from: "2026-09-04")
        #expect(!item.occurs(on: day("2026-09-03")))
        #expect(item.occurs(on: day("2026-09-04")))
        #expect(item.occurs(on: day("2026-09-05")))
        #expect(item.occurs(on: day("2027-03-01")))
    }

    // MARK: - weekly

    @Test func weeklyOnSelectedWeekdays() {
        // Montag (1) und Mittwoch (3)
        let item = task(.weekly, from: "2026-09-01", weekdays: [1, 3])
        #expect(item.occurs(on: day("2026-09-07")))  // Montag
        #expect(item.occurs(on: day("2026-09-09")))  // Mittwoch
        #expect(!item.occurs(on: day("2026-09-08"))) // Dienstag
        #expect(!item.occurs(on: day("2026-09-06"))) // Sonntag
    }

    @Test func weeklyWithoutWeekdaysMeansEveryDay() {
        let item = task(.weekly, from: "2026-09-01")
        for offset in 0..<7 {
            #expect(item.occurs(on: day("2026-09-07").adding(days: offset)))
        }
    }

    @Test func weeklyNeverBeforeStart() {
        let item = task(.weekly, from: "2026-09-07", weekdays: [1])
        #expect(!item.occurs(on: day("2026-08-31"))) // Montag davor
        #expect(item.occurs(on: day("2026-09-07")))
    }

    // MARK: - monthly

    @Test func monthlyMatchesSameDayOfMonth() {
        let item = task(.monthly, from: "2026-09-15")
        #expect(item.occurs(on: day("2026-10-15")))
        #expect(item.occurs(on: day("2027-01-15")))
        #expect(!item.occurs(on: day("2026-10-16")))
    }

    /// Ein am 31. angelegter Eintrag hat in kuerzeren Monaten kein Vorkommen.
    /// So ist es spezifiziert - der Test haelt das Verhalten bewusst fest.
    @Test func monthlyOnThe31stSkipsShortMonths() {
        let item = task(.monthly, from: "2026-01-31")
        #expect(item.occurs(on: day("2026-03-31")))
        #expect(item.occurs(on: day("2026-05-31")))
        #expect(!item.occurs(on: day("2026-02-28")))
        #expect(!item.occurs(on: day("2026-04-30")))
        #expect(!item.occurs(on: day("2026-06-30")))
    }

    @Test func monthlyRestrictedToSelectedMonths() {
        let item = task(.monthly, from: "2026-01-10", months: [1, 6, 12])
        #expect(item.occurs(on: day("2026-06-10")))
        #expect(item.occurs(on: day("2026-12-10")))
        #expect(!item.occurs(on: day("2026-07-10")))
    }

    // MARK: - quarterly

    @Test func quarterlyDefaultsToJanuaryAprilJulyOctober() {
        let item = task(.quarterly, from: "2026-01-05")
        #expect(item.occurs(on: day("2026-01-05")))
        #expect(item.occurs(on: day("2026-04-05")))
        #expect(item.occurs(on: day("2026-07-05")))
        #expect(item.occurs(on: day("2026-10-05")))
        #expect(!item.occurs(on: day("2026-02-05")))
        #expect(!item.occurs(on: day("2026-05-05")))
    }

    @Test func quarterlyWithExplicitMonths() {
        let item = task(.quarterly, from: "2026-02-20", months: [2, 5, 8, 11])
        #expect(item.occurs(on: day("2026-05-20")))
        #expect(item.occurs(on: day("2026-11-20")))
        #expect(!item.occurs(on: day("2026-04-20")))
    }

    // MARK: - yearly

    @Test func yearlyMatchesDayAndMonth() {
        let item = task(.yearly, from: "2026-05-17")
        #expect(item.occurs(on: day("2027-05-17")))
        #expect(item.occurs(on: day("2030-05-17")))
        #expect(!item.occurs(on: day("2027-05-18")))
        #expect(!item.occurs(on: day("2027-06-17")))
        #expect(!item.occurs(on: day("2025-05-17"))) // vor dem Start
    }

    // MARK: - naechstes Vorkommen

    @Test func nextOccurrenceFindsUpcomingDay() {
        let item = task(.weekly, from: "2026-09-01", weekdays: [1]) // montags
        #expect(item.nextOccurrence(from: day("2026-09-04")) == day("2026-09-07"))
    }

    @Test func nextOccurrenceIncludesTheStartingDayItself() {
        let item = task(.daily, from: "2026-09-01")
        #expect(item.nextOccurrence(from: day("2026-09-04")) == day("2026-09-04"))
    }

    @Test func nextOccurrenceReturnsNilBeyondLimit() {
        let item = task(.yearly, from: "2026-12-24")
        #expect(item.nextOccurrence(from: day("2026-01-01"), within: 30) == nil)
    }

    // MARK: - Ereignisse teilen sich dieselbe Logik

    @Test func eventsUseTheSameRecurrenceRules() {
        let event = EventItem(title: "Sport", startDate: day("2026-09-01"),
                              recurrence: .weekly, weekdays: [2, 4])
        #expect(event.occurs(on: day("2026-09-08")))  // Dienstag
        #expect(event.occurs(on: day("2026-09-10")))  // Donnerstag
        #expect(!event.occurs(on: day("2026-09-09"))) // Mittwoch
    }

    // MARK: - Speichern aus dem Editor

    /// "Woechentlich" ohne angehakten Tag darf nicht als "taeglich" enden: Dann
    /// gilt der Wochentag des Startdatums.
    @Test func weeklyWithoutWeekdaysTakesTheStartDay() {
        let start = day("2026-09-04") // Freitag
        let saved = Recurrence.weekly.weekdaysToSave([], startingOn: start)
        #expect(saved == [5])

        let item = task(.weekly, from: "2026-09-04", weekdays: saved)
        #expect(item.occurs(on: day("2026-09-11")))
        #expect(!item.occurs(on: day("2026-09-05")))
    }

    @Test func chosenWeekdaysAreKept() {
        #expect(Recurrence.weekly.weekdaysToSave([1, 3], startingOn: day("2026-09-04")) == [1, 3])
    }

    @Test func otherRecurrencesSaveNoWeekdays() {
        #expect(Recurrence.daily.weekdaysToSave([1, 3], startingOn: day("2026-09-04")).isEmpty)
        #expect(Recurrence.none.weekdaysToSave([], startingOn: day("2026-09-04")).isEmpty)
    }
}
