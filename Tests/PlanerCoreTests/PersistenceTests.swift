import Foundation
import Testing
@testable import PlanerCore

/// Serialisierung: Rundlauf, fehlende Felder, altes Artefakt-Format.
@Suite("Serialisierung")
struct PersistenceTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    @Test func fullRoundTrip() throws {
        var state = DashboardState(
            tasks: [TaskItem(title: "Lesen", startDate: day("2026-09-04"),
                             recurrence: .weekly, priority: .high, weekdays: [1, 3])],
            events: [EventItem(title: "Zahnarzt", startDate: day("2026-09-10"),
                               time: "14:30", colorKey: "mist", notes: "Praxis Mitte")],
            habits: [HabitItem(title: "Wasser", startDate: day("2026-08-01"))],
            goals: [Goal(title: "Marathon", targetDate: day("2027-04-01"),
                         createdDate: day("2026-09-01"),
                         milestones: [Milestone(title: "10 km am Stueck")])]
        )
        state.completions.setDone(state.tasks[0].id, on: day("2026-09-04"), true)
        state.journal[day("2026-09-04")] = JournalEntry(text: "Guter Tag", mood: 4)
        state.vacationRanges = [VacationRange(start: day("2026-07-01"), end: day("2026-07-14"))]

        let data = try encoder.encode(state)
        let restored = try JSONDecoder().decode(DashboardState.self, from: data)

        #expect(restored == state)
    }

    /// Das Journal muss als lesbares JSON-Objekt landen, nicht als Liste
    /// abwechselnder Schluessel und Werte.
    @Test func journalEncodesAsKeyedObject() throws {
        var state = DashboardState()
        state.journal[day("2026-09-04")] = JournalEntry(text: "Notiz")

        let json = String(decoding: try encoder.encode(state), as: UTF8.self)
        #expect(json.contains("\"journal\":{\"2026-09-04\""), "Unerwartet: \(json)")
    }

    /// Eine Datei aus einer aelteren Version kennt neue Felder nicht - sie muss
    /// sich trotzdem laden lassen.
    @Test func missingFieldsFallBackToDefaults() throws {
        let json = Data("""
        {"tasks":[{"title":"Alt","startDate":"2026-09-04"}]}
        """.utf8)

        let state = try JSONDecoder().decode(DashboardState.self, from: json)

        #expect(state.tasks.count == 1)
        #expect(state.tasks[0].title == "Alt")
        #expect(state.tasks[0].recurrence == .none)
        #expect(state.tasks[0].priority == .normal)
        #expect(state.events.isEmpty)
        #expect(state.habits.isEmpty)
    }

    @Test func emptyObjectDecodesToEmptyState() throws {
        let state = try JSONDecoder().decode(DashboardState.self, from: Data("{}".utf8))
        #expect(state == DashboardState())
    }

    /// Das HTML-Artefakt speicherte den Erledigt-Status als `{ datum: true }`.
    @Test func legacyCompletionFormatIsReadable() throws {
        let id = UUID()
        let json = Data("""
        {"\(id.uuidString)":{"2026-09-04":true,"2026-09-05":false,"2026-09-06":true}}
        """.utf8)

        let store = try JSONDecoder().decode(CompletionStore.self, from: json)

        #expect(store.isDone(id, on: day("2026-09-04")))
        #expect(!store.isDone(id, on: day("2026-09-05")), "false darf nicht als erledigt gelten")
        #expect(store.isDone(id, on: day("2026-09-06")))
        #expect(store.totalCount == 2)
    }

    @Test func completionToggleAndCleanup() {
        var store = CompletionStore()
        let id = UUID()

        let turnedOn = store.toggle(id, on: day("2026-09-04"))
        #expect(turnedOn)
        #expect(store.totalCount == 1)

        let turnedOff = store.toggle(id, on: day("2026-09-04"))
        #expect(!turnedOff)
        #expect(store.totalCount == 0, "Leere Eintraege duerfen nicht in der Datei zurueckbleiben")
    }

    @Test func removingAnItemDropsItsCompletions() {
        var store = CompletionStore()
        let id = UUID()
        store.setDone(id, on: day("2026-09-04"), true)
        store.setDone(id, on: day("2026-09-05"), true)

        store.remove(id)
        #expect(store.totalCount == 0)
    }

    @Test func earliestDay() {
        var store = CompletionStore()
        let first = UUID(), second = UUID()
        store.setDone(first, on: day("2026-09-04"), true)
        store.setDone(second, on: day("2026-03-11"), true)

        #expect(store.earliestDay == day("2026-03-11"))
    }

    @Test("Uhrzeiten werden robust gelesen",
          arguments: [("14:30", 870), ("00:00", 0), ("23:59", 1439)])
    func eventTimeParsing(time: String, minutes: Int) {
        #expect(EventItem(title: "A", time: time).minutesOfDay == minutes)
    }

    @Test func invalidTimesYieldNoSortKey() {
        #expect(EventItem(title: "A", time: nil).minutesOfDay == nil)
        #expect(EventItem(title: "A", time: "kaputt").minutesOfDay == nil)
    }
}
