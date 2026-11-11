import Testing
@testable import PlanerCore

/// Tageswerte, perfekter Tag, Streak und Urlaub - Spezifikation 4.9, 4.10, 4.14.
@Suite("Auswertung")
struct StatisticsTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    // MARK: - Tageswerte

    @Test func emptyDayHasNoEntries() {
        let stats = DashboardState().stats(for: day("2026-09-04"), today: day("2026-09-04"))
        #expect(stats.isEmpty)
        #expect(!stats.isPerfect)
        #expect(stats.percent == 0)
    }

    @Test func percentCountsTasksAndEvents() {
        var state = DashboardState(
            tasks: [TaskItem(title: "A", startDate: day("2026-09-04")),
                    TaskItem(title: "B", startDate: day("2026-09-04"))],
            events: [EventItem(title: "C", startDate: day("2026-09-04"), time: "09:00")]
        )
        state.completions.setDone(state.tasks[0].id, on: day("2026-09-04"), true)

        let stats = state.stats(for: day("2026-09-04"), today: day("2026-09-04"))
        #expect(stats.done == 1)
        #expect(stats.total == 3)
        #expect(stats.percent == 33)
    }

    /// Alles Abhakbare zaehlt fuer den Ring - auch Gewohnheiten.
    ///
    /// Ein Ring, der sich beim Abhaken nicht ruehrt, wirkt kaputt. Wer eine von
    /// zwei Sachen erledigt hat, soll die Haelfte sehen.
    @Test func everyCheckableItemMovesTheRing() {
        let today = day("2026-09-04")
        let task = TaskItem(title: "Lesen", startDate: today, recurrence: .daily)
        let habit = HabitItem(title: "Wasser", startDate: day("2026-08-01"))
        var state = DashboardState(tasks: [task], habits: [habit])

        #expect(state.stats(for: today, today: today).percent == 0)

        state.completions.setDone(task.id, on: today, true)
        var stats = state.stats(for: today, today: today)
        #expect(stats.percent == 50, "Eine von zwei Sachen erledigt")
        #expect(!stats.isPerfect, "Die offene Gewohnheit fehlt noch")

        state.completions.setDone(habit.id, on: today, true)
        stats = state.stats(for: today, today: today)
        #expect(stats.percent == 100)
        #expect(stats.isPerfect)
    }

    /// Gegenprobe mit gemischtem Tag: ein Termin, zwei Aufgaben, zwei
    /// Gewohnheiten - jedes Abhaken bewegt die Anzeige.
    @Test func percentRisesWithEverySingleItem() {
        let today = day("2026-09-04")
        var state = DashboardState(
            tasks: [TaskItem(title: "A", startDate: today), TaskItem(title: "B", startDate: today)],
            events: [EventItem(title: "C", startDate: today)],
            habits: [HabitItem(title: "D", startDate: today),
                     HabitItem(title: "E", startDate: today)]
        )

        let ids = state.tasks.map(\.id) + state.events.map(\.id) + state.habits.map(\.id)
        let expected = [20, 40, 60, 80, 100]

        for (index, id) in ids.enumerated() {
            state.completions.setDone(id, on: today, true)
            #expect(state.stats(for: today, today: today).percent == expected[index],
                    "Nach \(index + 1) von 5 Eintraegen")
        }
    }

    /// Ein Tag, an dem nur Gewohnheiten anstehen und alle erledigt sind, ist voll.
    @Test func habitOnlyDayCountsAsFull() {
        let habit = HabitItem(title: "Wasser", startDate: day("2026-08-01"))
        var state = DashboardState(habits: [habit])
        let today = day("2026-09-04")
        state.completions.setDone(habit.id, on: today, true)

        let stats = state.stats(for: today, today: today)
        #expect(stats.isPerfect)
        #expect(stats.percent == 100)
    }

    /// Derselbe wiederkehrende Eintrag kann an einem Tag erledigt und am
    /// naechsten offen sein.
    @Test func completionIsPerDay() {
        let task = TaskItem(title: "Lesen", startDate: day("2026-09-01"), recurrence: .daily)
        var state = DashboardState(tasks: [task])
        state.completions.setDone(task.id, on: day("2026-09-04"), true)

        #expect(state.completions.isDone(task.id, on: day("2026-09-04")))
        #expect(!state.completions.isDone(task.id, on: day("2026-09-05")))
    }

    // MARK: - Streak

    /// Hilfsaufbau: eine taegliche Aufgabe, an den angegebenen Tagen abgehakt.
    private func streakState(doneOn days: [String], from start: String = "2026-08-01")
        -> DashboardState {
        let task = TaskItem(title: "Lesen", startDate: day(start), recurrence: .daily)
        var state = DashboardState(tasks: [task])
        for raw in days {
            state.completions.setDone(task.id, on: day(raw), true)
        }
        return state
    }

    @Test func streakCountsConsecutivePerfectDays() {
        let state = streakState(doneOn: ["2026-09-02", "2026-09-03", "2026-09-04"])
        #expect(state.currentStreak(today: day("2026-09-04")) == 3)
    }

    /// Ist heute noch nicht perfekt, beginnt die Zaehlung bei gestern.
    @Test func unfinishedTodayDoesNotBreakTheStreak() {
        let state = streakState(doneOn: ["2026-09-02", "2026-09-03"])
        #expect(state.currentStreak(today: day("2026-09-04")) == 2)
    }

    @Test func incompleteDayEndsTheStreak() {
        let state = streakState(doneOn: ["2026-09-01", "2026-09-03", "2026-09-04"])
        #expect(state.currentStreak(today: day("2026-09-04")) == 2,
                "Der offene 02.09. muss die Serie beenden")
    }

    /// Leere Tage sind neutral: Vor dem 03.09. gibt es nichts zu erledigen -
    /// das darf die Serie nicht abbrechen.
    @Test func emptyDaysAreNeutral() {
        let earlier = TaskItem(title: "Alt", startDate: day("2026-08-20"), recurrence: .none)
        let daily = TaskItem(title: "Lesen", startDate: day("2026-09-03"), recurrence: .daily)
        var state = DashboardState(tasks: [earlier, daily])
        state.completions.setDone(earlier.id, on: day("2026-08-20"), true)
        state.completions.setDone(daily.id, on: day("2026-09-03"), true)
        state.completions.setDone(daily.id, on: day("2026-09-04"), true)

        #expect(state.currentStreak(today: day("2026-09-04")) == 3,
                "Der 20.08. zaehlt mit, die leeren Tage dazwischen sind neutral")
    }

    // MARK: - Urlaub

    @Test func vacationDaysAreSkippedInStreak() {
        var state = streakState(doneOn: ["2026-09-01", "2026-09-04"])
        state.vacationRanges = [VacationRange(start: day("2026-09-02"), end: day("2026-09-03"))]

        #expect(state.currentStreak(today: day("2026-09-04")) == 2,
                "Urlaubstage frieren die Serie ein, statt sie zu brechen")
    }

    @Test func recurringItemsPauseDuringVacationButOneOffsRemain() {
        let recurring = TaskItem(title: "Lesen", startDate: day("2026-09-01"), recurrence: .daily)
        let oneOff = TaskItem(title: "Flug", startDate: day("2026-09-02"), recurrence: .none)
        var state = DashboardState(tasks: [recurring, oneOff])
        state.vacationRanges = [VacationRange(start: day("2026-09-02"), end: day("2026-09-03"))]

        let vacationDay = state.tasks(on: day("2026-09-02"), today: day("2026-09-04"))
        #expect(vacationDay.map(\.title) == ["Flug"])

        let normalDay = state.tasks(on: day("2026-09-04"), today: day("2026-09-04"))
        #expect(normalDay.map(\.title) == ["Lesen"])
    }

    @Test func habitsPauseCompletelyDuringVacation() {
        var state = DashboardState(habits: [HabitItem(title: "Wasser", startDate: day("2026-08-01"))])
        state.vacation = VacationState(isActive: true, since: day("2026-09-02"))

        #expect(state.habits(on: day("2026-09-03"), today: day("2026-09-04")).isEmpty)
        #expect(state.habits(on: day("2026-09-01"), today: day("2026-09-04")).count == 1)
    }

    @Test func activeVacationCoversOnlyUpToToday() {
        var state = DashboardState()
        state.vacation = VacationState(isActive: true, since: day("2026-09-02"))
        let today = day("2026-09-04")

        #expect(!state.isVacationDay(day("2026-09-01"), today: today))
        #expect(state.isVacationDay(day("2026-09-03"), today: today))
        #expect(state.isVacationDay(today, today: today))
        #expect(!state.isVacationDay(day("2026-09-05"), today: today),
                "Zukunft gehoert noch nicht zum laufenden Urlaub")
    }

    // MARK: - Kennzahlen

    @Test func perfectDayCountOverWindow() {
        let state = streakState(doneOn: ["2026-09-01", "2026-09-03", "2026-09-04"])
        #expect(state.perfectDayCount(lastDays: 7, today: day("2026-09-04")) == 3)
    }

    @Test func totalCompletionCount() {
        let state = streakState(doneOn: ["2026-09-01", "2026-09-02", "2026-09-03"])
        #expect(state.totalCompletionCount == 3)
    }

    // MARK: - Sortierung

    @Test func eventsSortOpenFirstThenByTime() {
        let late = EventItem(title: "Spaet", startDate: day("2026-09-04"), time: "18:00")
        let early = EventItem(title: "Frueh", startDate: day("2026-09-04"), time: "08:00")
        let untimed = EventItem(title: "Ohne Zeit", startDate: day("2026-09-04"))
        var state = DashboardState(events: [late, early, untimed])
        state.completions.setDone(early.id, on: day("2026-09-04"), true)

        let sorted = state.events(on: day("2026-09-04"), today: day("2026-09-04")).map(\.title)
        #expect(sorted == ["Spaet", "Ohne Zeit", "Frueh"],
                "Erledigtes nach unten, davor nach Uhrzeit, Termine ohne Zeit zuletzt")
    }

    @Test func tasksSortOpenFirstThenByPriority() {
        let normal = TaskItem(title: "Normal", startDate: day("2026-09-04"), priority: .normal)
        let high = TaskItem(title: "Wichtig", startDate: day("2026-09-04"), priority: .high)
        let low = TaskItem(title: "Klein", startDate: day("2026-09-04"), priority: .low)
        var state = DashboardState(tasks: [normal, high, low])
        state.completions.setDone(high.id, on: day("2026-09-04"), true)

        let sorted = state.tasks(on: day("2026-09-04"), today: day("2026-09-04")).map(\.title)
        #expect(sorted == ["Normal", "Klein", "Wichtig"],
                "Offenes zuerst nach Prioritaet, Erledigtes nach unten")
    }
}
