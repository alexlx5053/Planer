import Foundation
import Testing
@testable import PlanerCore
@testable import PlanerData

/// Der Zwischenspeicher fuer anstehende Termine.
@Suite("Anstehende Termine im Bestand")
@MainActor
struct UpcomingCacheTests {

    private let today = DateKey(year: 2026, month: 10, day: 29)

    private func store(events count: Int) -> StateStore {
        let events = (1...count).map {
            EventItem(title: "Termin \($0)", startDate: today.adding(days: $0))
        }
        return StateStore(inMemory: DashboardState(events: events), today: today)
    }

    /// Der Fehler, der hier steckte: Seitenspalte und Menueleiste fragen nach
    /// unterschiedlich vielen - wer zuerst fragte, bestimmte die Laenge fuer
    /// beide.
    @Test func differentLimitsGetDifferentLengths() {
        let store = store(events: 10)
        #expect(store.upcomingEvents(limit: 5).count == 5)
        #expect(store.upcomingEvents(limit: 8).count == 8)
        #expect(store.upcomingEvents(limit: 5).count == 5)
    }

    @Test func fullListReachesBeyondNinetyDays() {
        let store = StateStore(inMemory: DashboardState(events: [
            EventItem(title: "Bald", startDate: today.adding(days: 2)),
            EventItem(title: "Weit weg", startDate: today.adding(days: 150)),
        ]), today: today)

        #expect(store.upcomingEvents(limit: 10).map(\.event.title) == ["Bald"])
        #expect(store.allUpcomingEvents().map(\.event.title) == ["Bald", "Weit weg"])
    }

    @Test func fullListFollowsChanges() {
        let store = store(events: 3)
        #expect(store.allUpcomingEvents().count == 3)

        store.add(event: EventItem(title: "Neu", startDate: today.adding(days: 40)))
        #expect(store.allUpcomingEvents().count == 4)

        let first = store.allUpcomingEvents()[0]
        store.toggleCompletion(first.event.id, on: first.day)
        // Abgehakt verschwindet er aus der Liste.
        #expect(store.allUpcomingEvents().count == 3)
    }

    @Test func habitsCanBeCheckedOnAnyDayOfTheWeek() {
        let habit = HabitItem(title: "Lesen", startDate: today.adding(days: -10))
        let store = StateStore(inMemory: DashboardState(habits: [habit]), today: today)
        let monday = today.startOfWeek

        store.toggleCompletion(habit.id, on: monday)

        #expect(store.isDone(habit.id, on: monday))
        #expect(store.stats(for: monday).habitsDone == 1)
        #expect(!store.isDone(habit.id, on: today))
    }
}
