import Foundation
import Testing
@testable import PlanerCore

/// Gliederung der Gesamtliste aller anstehenden Termine.
@Suite("Terminliste")
struct UpcomingGroupingTests {

    /// Donnerstag, 29.10.2026.
    private let today = DateKey(year: 2026, month: 10, day: 29)

    private func item(_ offset: Int) -> UpcomingEvent {
        let day = today.adding(days: offset)
        return UpcomingEvent(event: EventItem(title: "T\(offset)", startDate: day),
                             day: day, daysAway: offset)
    }

    @Test func nearTermsComeFirstThenMonths() {
        let items = [0, 1, 3, 5, 18, 75].map(item)
        let titles = UpcomingGrouping.sections(for: items, today: today).map(\.title)
        #expect(titles == [
            "Heute",            // Do 29.10.
            "Morgen",           // Fr 30.10.
            "Diese Woche",      // So 1.11. - noch dieselbe Woche
            "Nächste Woche",    // Di 3.11.
            "November 2026",    // Mo 16.11.
            "Januar 2027",      // Mi 12.1.
        ])
    }

    @Test func itemsOfOneSectionStayTogether() {
        let items = [18, 19, 25].map(item)
        let sections = UpcomingGrouping.sections(for: items, today: today)
        #expect(sections.count == 1)
        #expect(sections[0].items.count == 3)
    }

    @Test func emptyListHasNoSections() {
        #expect(UpcomingGrouping.sections(for: [], today: today).isEmpty)
    }

    @Test func farEventsAreFoundWithinAYear() {
        let state = DashboardState(events: [
            EventItem(title: "Bald", startDate: today.adding(days: 3)),
            EventItem(title: "Klausur", startDate: today.adding(days: 200)),
            EventItem(title: "Training", startDate: today.adding(days: -14),
                      recurrence: .weekly, weekdays: [1]),
        ])
        let all = state.upcomingEvents(from: today, limit: .max, within: 366)
        #expect(all.map(\.event.title) == ["Bald", "Training", "Klausur"])
        // Das woechentliche Training steht genau einmal da.
        #expect(all.filter { $0.event.title == "Training" }.count == 1)
    }
}
