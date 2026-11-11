import Foundation
import Testing
@testable import PlanerCore
@testable import PlanerData

/// Verschieben auf einen anderen Tag und Umsortieren von Hand.
@Suite("Verschieben")
@MainActor
struct MoveTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }
    private let today = DateKey(year: 2026, month: 9, day: 15)

    private func store() -> StateStore {
        StateStore(inMemory: DashboardState(), today: today)
    }

    // MARK: - Einmalige Aufgabe

    @Test func singleTaskSimplyChangesItsDay() {
        let store = store()
        store.add(task: TaskItem(title: "Koffer", startDate: today, priority: .high))
        let task = store.state.tasks[0]

        store.move(task: task, from: today, to: today.adding(days: 1))

        #expect(store.agenda(for: today).tasks.isEmpty, "Heute ist sie weg")
        let tomorrow = store.agenda(for: today.adding(days: 1)).tasks
        #expect(tomorrow.map(\.title) == ["Koffer"])
        #expect(tomorrow[0].priority == .high, "Die Prioritaet wandert mit")
        #expect(store.state.tasks.count == 1, "Es entsteht keine Kopie")
    }

    // MARK: - Wiederkehrende Aufgabe

    /// Der Kern: Nur dieses eine Vorkommen wandert, die Serie bleibt.
    @Test func recurringTaskMovesOnlyThisOccurrence() {
        let store = store()
        store.add(task: TaskItem(title: "Lesen", startDate: day("2026-09-01"),
                                 recurrence: .daily, priority: .high))
        let task = store.state.tasks[0]

        store.move(task: task, from: today, to: today.adding(days: 1))

        #expect(store.agenda(for: today).tasks.isEmpty, "Heute faellt sie aus")
        #expect(store.agenda(for: today.adding(days: -1)).tasks.map(\.title) == ["Lesen"],
                "Gestern steht die Serie unveraendert")
        #expect(store.agenda(for: today.adding(days: 2)).tasks.map(\.title) == ["Lesen"],
                "Uebermorgen laeuft die Serie weiter")

        let tomorrow = store.agenda(for: today.adding(days: 1)).tasks
        #expect(tomorrow.count == 2, "Morgen: die Serie und die verschobene Aufgabe")
        #expect(tomorrow.allSatisfy { $0.title == "Lesen" })
        #expect(tomorrow.contains { $0.recurrence == .none && $0.priority == .high },
                "Die Kopie ist einmalig und behaelt alles Eingetragene")
    }

    @Test func movingDoesNotCarryTheCompletion() {
        let store = store()
        store.add(task: TaskItem(title: "Lesen", startDate: today))
        let task = store.state.tasks[0]
        store.toggleCompletion(task.id, on: today)

        store.move(task: task, from: today, to: today.adding(days: 1))

        #expect(!store.isDone(task.id, on: today.adding(days: 1)),
                "Was verschoben wird, ist offen - sonst waere es geblieben")
    }

    @Test func movingToTheSameDayChangesNothing() {
        let store = store()
        store.add(task: TaskItem(title: "Lesen", startDate: today))
        store.move(task: store.state.tasks[0], from: today, to: today)

        #expect(store.state.tasks.count == 1)
        #expect(store.agenda(for: today).tasks.count == 1)
    }

    // MARK: - Umsortieren

    @Test func draggingDownPlacesItBehindTheTarget() {
        let store = store()
        for title in ["A", "B", "C"] {
            store.add(task: TaskItem(title: title, startDate: today))
        }
        let ids = store.state.tasks.map(\.id)

        store.placeTask(ids[0], at: ids[2])

        #expect(store.agenda(for: today).tasks.map(\.title) == ["B", "C", "A"])
    }

    @Test func draggingUpPlacesItBeforeTheTarget() {
        let store = store()
        for title in ["A", "B", "C"] {
            store.add(task: TaskItem(title: title, startDate: today))
        }
        let ids = store.state.tasks.map(\.id)

        store.placeTask(ids[2], at: ids[0])

        #expect(store.agenda(for: today).tasks.map(\.title) == ["C", "A", "B"])
    }

    /// Erledigtes rutscht ans Ende, unabhaengig von der selbst gewaehlten Folge.
    @Test func completedTasksStayAtTheBottom() {
        let store = store()
        for title in ["A", "B", "C"] {
            store.add(task: TaskItem(title: title, startDate: today))
        }
        store.toggleCompletion(store.state.tasks[0].id, on: today)

        #expect(store.agenda(for: today).tasks.map(\.title) == ["B", "C", "A"])
    }

    @Test func orderSurvivesReloading() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LD-Reihenfolge-\(UUID().uuidString)", isDirectory: true)
        let location = StoreLocation(directory: directory)
        try location.ensureDirectories()

        let store = StateStore(location: location, today: today)
        for title in ["A", "B", "C"] {
            store.add(task: TaskItem(title: title, startDate: today))
        }
        let ids = store.state.tasks.map(\.id)
        store.placeTask(ids[2], at: ids[0])
        store.flush()

        let reopened = StateStore(location: location, today: today)
        #expect(reopened.agenda(for: today).tasks.map(\.title) == ["C", "A", "B"])
    }
}

/// Gewohnheiten, die heute entstehen.
@Suite("Gewohnheit anlegen")
@MainActor
struct HabitCreationTests {

    /// Mit der Vorgabe des Anlegen-Blatts, nicht mit einem ausgedachten Datum:
    /// Genau dieser Weg wird benutzt.
    @Test func habitAddedTodayAppearsToday() {
        let realToday = DateKey.today
        let store = StateStore(inMemory: DashboardState(), today: realToday)

        store.add(habit: HabitItem(title: "Neu"))

        #expect(store.state.habits[0].startDate == realToday)
        #expect(store.agenda(for: realToday).habits.map(\.title) == ["Neu"],
                "Sie muss am Tag des Anlegens dastehen")
        #expect(store.stats(for: realToday).habitsTotal == 1)
    }

    /// Und der Zwischenspeicher darf nicht dazwischenfunken: Erst den Tag
    /// abfragen, dann anlegen, dann erneut abfragen.
    @Test func cacheDoesNotHideANewHabit() {
        let realToday = DateKey.today
        let store = StateStore(inMemory: DashboardState(), today: realToday)

        #expect(store.agenda(for: realToday).habits.isEmpty)

        store.add(habit: HabitItem(title: "Neu"))

        #expect(store.agenda(for: realToday).habits.count == 1)
    }
}
