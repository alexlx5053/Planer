import Testing
@testable import PlanerCore

/// Anstehende Termine nach Spezifikation 4.12.
@Suite("Anstehend")
struct UpcomingTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }
    private let today = DateKey(year: 2026, month: 9, day: 4)

    @Test func emptyStateHasNothingUpcoming() {
        #expect(DashboardState().upcomingEvents(from: today).isEmpty)
    }

    @Test func sortsByProximity() {
        let far = EventItem(title: "Fern", startDate: day("2026-09-20"))
        let near = EventItem(title: "Nah", startDate: day("2026-09-06"))
        let today_ = EventItem(title: "Heute", startDate: day("2026-09-04"))
        let state = DashboardState(events: [far, near, today_])

        let upcoming = state.upcomingEvents(from: today)
        #expect(upcoming.map(\.event.title) == ["Heute", "Nah", "Fern"])
        #expect(upcoming.map(\.daysAway) == [0, 2, 16])
    }

    /// Ein wiederkehrender Termin steht einmal in der Liste - mit seinem
    /// naechsten Vorkommen.
    @Test func recurringEventAppearsOnceWithItsNextOccurrence() {
        let training = EventItem(title: "Training", startDate: day("2026-08-01"),
                                 recurrence: .weekly, weekdays: [1])  // montags
        let state = DashboardState(events: [training])

        let upcoming = state.upcomingEvents(from: today)
        #expect(upcoming.count == 1)
        #expect(upcoming[0].day == day("2026-09-07"))
        #expect(upcoming[0].daysAway == 3)
    }

    /// Was heute schon abgehakt ist, steht nicht mehr an.
    @Test func skipsCompletedOccurrences() {
        let daily = EventItem(title: "Lüften", startDate: day("2026-09-01"), recurrence: .daily)
        var state = DashboardState(events: [daily])
        state.completions.setDone(daily.id, on: today, true)

        let upcoming = state.upcomingEvents(from: today)
        #expect(upcoming.count == 1)
        #expect(upcoming[0].daysAway == 1, "Das heutige Vorkommen ist erledigt, also zaehlt morgen")
    }

    @Test func respectsTheLimit() {
        let events = (1...9).map {
            EventItem(title: "Termin \($0)", startDate: today.adding(days: $0))
        }
        let state = DashboardState(events: events)

        #expect(state.upcomingEvents(from: today, limit: 4).count == 4)
    }

    /// Ausserhalb des Zeitfensters taucht nichts auf.
    @Test func ignoresEventsBeyondTheHorizon() {
        let state = DashboardState(events: [
            EventItem(title: "Weit weg", startDate: today.adding(days: 120))
        ])

        #expect(state.upcomingEvents(from: today, within: 90).isEmpty)
        #expect(state.upcomingEvents(from: today, within: 150).count == 1)
    }

    /// Im Urlaub pausieren wiederkehrende Termine - dann darf auch nichts
    /// davon anstehen.
    @Test func recurringEventsPauseDuringVacation() {
        let daily = EventItem(title: "Lüften", startDate: day("2026-09-01"), recurrence: .daily)
        var state = DashboardState(events: [daily])
        state.vacationRanges = [VacationRange(start: today, end: today.adding(days: 3))]

        let upcoming = state.upcomingEvents(from: today)
        #expect(upcoming.count == 1)
        #expect(upcoming[0].daysAway == 4, "Erst nach dem Urlaub geht es weiter")
    }

    @Test("Beschriftung", arguments: [(0, "heute"), (1, "morgen"), (2, "in 2 T"), (17, "in 17 T")])
    func shortLabel(days: Int, expected: String) {
        let item = UpcomingEvent(event: EventItem(title: "X"), day: today, daysAway: days)
        #expect(item.shortLabel == expected)
    }
}
