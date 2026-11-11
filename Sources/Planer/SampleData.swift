import Foundation
import PlanerCore
import PlanerData

/// Beispieldaten fuer Bildaufnahmen und Leistungsmessungen - nie fuer die
/// ausgelieferte App, die startet leer.
enum SampleData {

    /// Ein glaubwuerdiger Alltag: einiges erledigt, einiges offen.
    @MainActor
    static func store(today: DateKey = .today) -> StateStore {
        var state = DashboardState()

        let dentist = EventItem(title: "Zahnarzt", startDate: today, time: "14:30",
                                durationMinutes: 45, colorKey: "mist",
                                notes: "Praxis Mitte, 2. Stock")
        let training = EventItem(title: "Training", startDate: today.adding(days: -21),
                                 time: "18:00", colorKey: "sand",
                                 recurrence: .weekly, weekdays: [1, 3, 5])
        let groceries = EventItem(title: "Einkaufen", startDate: today, colorKey: "moss")

        let taxes = TaskItem(title: "Steuererklärung abschicken", startDate: today, priority: .high)
        let reading = TaskItem(title: "30 Minuten lesen", startDate: today.adding(days: -30),
                               recurrence: .daily)
        let laundry = TaskItem(title: "Wäsche aufhängen", startDate: today)

        let start = today.adding(days: -60)
        let water = HabitItem(title: "Wasser trinken", startDate: start)
        let walk = HabitItem(title: "Spazieren", startDate: start)
        let journal = HabitItem(title: "Tagebuch", startDate: start)

        let birthday = EventItem(title: "Geburtstag Anna", startDate: today.adding(days: 5),
                                 colorKey: "clay")
        let checkup = EventItem(title: "Zahnarzt Kontrolle", startDate: today.adding(days: 23),
                                time: "10:00", colorKey: "mist")

        // Ein Stundenplan, wie er aussieht: Doppelbloecke, eine Uebung in
        // ungerader Woche, ein Nachmittag frei.
        let semester = Semester.current(on: today)
        func course(_ title: String, _ kind: CourseKind, _ weekday: Int,
                    _ from: (Int, Int), _ to: (Int, Int), _ room: String,
                    _ color: String, _ weeks: WeekPattern = .every) -> CourseItem {
            CourseItem(
                title: title, kind: kind, weekday: weekday,
                start: ClockTime(hour: from.0, minute: from.1),
                end: ClockTime(hour: to.0, minute: to.1),
                room: room, colorKey: color, weeks: weeks,
                firstDay: semester.firstDay, lastDay: semester.lastDay
            )
        }

        state.courses = [
            course("Analysis II", .lecture, 1, (8, 15), (9, 45), "H 12", "stone"),
            course("Lineare Algebra", .lecture, 1, (10, 15), (11, 45), "H 3", "mist"),
            course("Analysis Übung", .exercise, 1, (14, 0), (15, 30), "B 101", "stone"),
            course("Datenbanken", .lecture, 2, (10, 15), (11, 45), "H 7", "sand"),
            course("Statistik", .lecture, 3, (9, 0), (10, 30), "H 1", "moss"),
            course("Datenbanken Praktikum", .lab, 3, (13, 0), (16, 0), "CIP 2", "sand"),
            course("Seminar Datenschutz", .seminar, 4, (16, 15), (17, 45), "S 4", "clay", .odd),
            course("Statistik Tutorium", .tutorial, 5, (10, 15), (11, 45), "B 7", "moss"),
        ]

        state.events = [dentist, training, groceries, birthday, checkup]
        state.tasks = [taxes, reading, laundry]
        state.habits = [water, walk, journal]

        // Heute teilweise erledigt.
        state.completions.setDone(groceries.id, on: today, true)
        state.completions.setDone(laundry.id, on: today, true)
        state.completions.setDone(water.id, on: today, true)
        state.completions.setDone(walk.id, on: today, true)

        // Eine Serie perfekter Tage in der Vergangenheit, damit Ring, Streak und
        // Kalendermarkierungen etwas zu zeigen haben.
        for offset in 1...12 {
            let past = today.adding(days: -offset)
            state.completions.setDone(reading.id, on: past, true)
            state.completions.setDone(water.id, on: past, true)
            state.completions.setDone(walk.id, on: past, true)
            state.completions.setDone(journal.id, on: past, true)
            if training.occurs(on: past) {
                state.completions.setDone(training.id, on: past, true)
            }
        }

        return StateStore(inMemory: state, today: today)
    }

    /// Grosser Bestand fuer die Leistungsmessung: drei Jahre Historie.
    @MainActor
    static func largeStore(today: DateKey = .today) -> StateStore {
        var state = DashboardState()

        for index in 0..<25 {
            let task = TaskItem(
                title: "Aufgabe \(index + 1)",
                startDate: today.adding(days: -1_100),
                recurrence: index.isMultiple(of: 3) ? .daily : .weekly,
                weekdays: index.isMultiple(of: 3) ? [] : [index % 7]
            )
            state.tasks.append(task)
        }
        for index in 0..<10 {
            state.habits.append(HabitItem(title: "Gewohnheit \(index + 1)",
                                          startDate: today.adding(days: -1_100)))
        }

        for offset in 0..<1_100 {
            let past = today.adding(days: -offset)
            for task in state.tasks where task.occurs(on: past) && offset % 3 != 0 {
                state.completions.setDone(task.id, on: past, true)
            }
            for habit in state.habits where offset % 4 != 0 {
                state.completions.setDone(habit.id, on: past, true)
            }
        }

        return StateStore(inMemory: state, today: today)
    }
}
