import Foundation
import Testing
@testable import PlanerCore

/// Ab wann eine Gewohnheit gilt.
@Suite("Gewohnheiten")
struct HabitTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }
    private let today = DateKey(year: 2026, month: 9, day: 4)

    @Test func appliesFromTheDayItWasCreated() {
        let habit = HabitItem(title: "Wasser", startDate: today)
        let state = DashboardState(habits: [habit])

        #expect(state.habits(on: today, today: today).count == 1, "Ab heute gilt sie")
        #expect(state.habits(on: today.adding(days: 1), today: today).count == 1, "Und weiterhin")
    }

    /// Der Kern: Vergangenes darf sich nicht dadurch aendern, dass man sich
    /// heute etwas vornimmt.
    @Test func doesNotApplyRetroactively() {
        let habit = HabitItem(title: "Wasser", startDate: today)
        let state = DashboardState(habits: [habit])

        #expect(state.habits(on: today.adding(days: -1), today: today).isEmpty)
        #expect(state.habits(on: today.adding(days: -30), today: today).isEmpty)
    }

    /// Eine neue Gewohnheit darf eine laufende Serie nicht zerstoeren.
    @Test func newHabitKeepsTheStreakIntact() {
        let task = TaskItem(title: "Lesen", startDate: day("2026-09-01"), recurrence: .daily)
        var state = DashboardState(tasks: [task])
        for offset in 0...3 {
            state.completions.setDone(task.id, on: today.adding(days: -offset), true)
        }
        #expect(state.currentStreak(today: today) == 4)

        state.habits = [HabitItem(title: "Wasser", startDate: today)]

        #expect(state.currentStreak(today: today) == 3,
                "Die drei vergangenen Tage bleiben perfekt; heute ist die neue Gewohnheit offen")

        state.completions.setDone(state.habits[0].id, on: today, true)
        #expect(state.currentStreak(today: today) == 4, "Abgehakt zaehlt heute wieder mit")
    }

    @Test func countsTowardsTodayImmediately() {
        var state = DashboardState(habits: [HabitItem(title: "Wasser", startDate: today)])

        var stats = state.stats(for: today, today: today)
        #expect(stats.habitsTotal == 1)
        #expect(!stats.isPerfect)

        state.completions.setDone(state.habits[0].id, on: today, true)
        stats = state.stats(for: today, today: today)
        #expect(stats.habitsDone == 1)
        #expect(stats.isPerfect, "Ab dem ersten Tag zaehlt sie voll mit")
    }

    /// Dateien aus einer Fassung ohne Startdatum behalten ihr bisheriges
    /// Verhalten: Die Gewohnheit galt schon immer.
    @Test func olderFilesWithoutStartDateKeepApplyingToEveryDay() throws {
        let json = Data("""
        {"habits":[{"id":"\(UUID().uuidString)","title":"Alt"}]}
        """.utf8)
        let state = try JSONDecoder().decode(DashboardState.self, from: json)

        #expect(state.habits(on: today.adding(days: -365), today: today).count == 1)
    }

    @Test func vacationStillPausesHabits() {
        var state = DashboardState(habits: [HabitItem(title: "Wasser", startDate: day("2026-09-01"))])
        state.vacation = VacationState(isActive: true, since: day("2026-09-03"))

        #expect(state.habits(on: today, today: today).isEmpty)
        #expect(state.habits(on: day("2026-09-02"), today: today).count == 1)
    }
}
