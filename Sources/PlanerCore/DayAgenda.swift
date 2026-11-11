import Foundation

/// Was an einem Tag ansteht, bereits sortiert und um Urlaubstage bereinigt.
public struct DayAgenda: Sendable {
    public let day: DateKey
    public let events: [EventItem]
    public let tasks: [TaskItem]
    public let habits: [HabitItem]
    /// Die Sitzungen des Stundenplans an diesem Tag.
    ///
    /// Sie stehen hier mit drin, weil sie zum Tag gehoeren - aber sie zaehlen in
    /// `DayStats` nicht mit. Ein Vorlesungstag ist kein zu 0 % erledigter Tag.
    public let courses: [CourseItem]
    public let isVacation: Bool

    public var isEmpty: Bool {
        events.isEmpty && tasks.isEmpty && habits.isEmpty && courses.isEmpty
    }

    /// Was an diesem Tag Zeit belegt - Kurse und Termine mit Uhrzeit.
    public var busyBlocks: [BusyBlock] {
        let fromCourses = courses.map { BusyBlock(course: $0) }
        let fromEvents = events.compactMap { BusyBlock(event: $0) }
        return (fromCourses + fromEvents).sorted { ($0.span, $0.title) < ($1.span, $1.title) }
    }
}

public extension DashboardState {

    // MARK: - Urlaub (Spezifikation 4.14)

    /// Faellt der Tag in einen laufenden oder abgeschlossenen Urlaub?
    func isVacationDay(_ day: DateKey, today: DateKey = .today) -> Bool {
        if vacation.isActive, let since = vacation.since, day >= since, day <= today {
            return true
        }
        return vacationRanges.contains { $0.contains(day) }
    }

    // MARK: - Tagesinhalt

    /// Ereignisse des Tages: unerledigte zuerst, dann nach Uhrzeit; Eintraege
    /// ohne Uhrzeit hinter den terminierten. (Spezifikation 4.5)
    func events(on day: DateKey, today: DateKey = .today) -> [EventItem] {
        let vacationDay = isVacationDay(day, today: today)
        return events
            .filter { $0.occurs(on: day) }
            // Im Urlaub pausieren nur wiederkehrende Eintraege; einmalige
            // Termine bleiben sichtbar.
            .filter { !vacationDay || $0.recurrence == .none }
            .sorted { lhs, rhs in
                let lhsDone = completions.isDone(lhs.id, on: day)
                let rhsDone = completions.isDone(rhs.id, on: day)
                if lhsDone != rhsDone { return !lhsDone }
                switch (lhs.minutesOfDay, rhs.minutesOfDay) {
                case let (l?, r?) where l != r: return l < r
                case (nil, .some): return false
                case (.some, nil): return true
                default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    /// Aufgaben des Tages: Erledigtes nach unten, sonst die selbst gewaehlte
    /// Reihenfolge.
    ///
    /// Frueher sortierte die Prioritaet mit. Seit sich Aufgaben von Hand ordnen
    /// lassen, darf sie das nicht mehr - eine Reihenfolge, die man selbst
    /// festgelegt hat und die dann doch umspringt, ist schlimmer als gar keine.
    /// Die Prioritaet zeigt sich weiterhin am roten Streifen und am Faehnchen.
    ///
    /// Bewusst kein `sorted`: Swift sichert dabei keine stabile Reihenfolge zu,
    /// gleichrangige Aufgaben koennten also die Plaetze tauschen. Aufteilen
    /// erhaelt sie.
    func tasks(on day: DateKey, today: DateKey = .today) -> [TaskItem] {
        let vacationDay = isVacationDay(day, today: today)
        let matching = tasks
            .filter { $0.occurs(on: day) }
            .filter { !vacationDay || $0.recurrence == .none }

        let open = matching.filter { !completions.isDone($0.id, on: day) }
        let done = matching.filter { completions.isDone($0.id, on: day) }
        return open + done
    }

    /// Gewohnheiten gelten taeglich, aber erst ab dem Tag, an dem sie angelegt
    /// wurden - im Urlaub pausieren sie vollstaendig.
    func habits(on day: DateKey, today: DateKey = .today) -> [HabitItem] {
        guard !isVacationDay(day, today: today) else { return [] }
        return habits.filter { day >= $0.startDate }
    }

    func agenda(for day: DateKey, today: DateKey = .today) -> DayAgenda {
        DayAgenda(
            day: day,
            events: events(on: day, today: today),
            tasks: tasks(on: day, today: today),
            habits: habits(on: day, today: today),
            courses: courses(on: day, today: today),
            isVacation: isVacationDay(day, today: today)
        )
    }
}
