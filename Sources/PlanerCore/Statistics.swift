import Foundation

/// Kennzahlen eines einzelnen Tages. (Spezifikation 4.9)
public struct DayStats: Hashable, Sendable {
    /// Erledigte Aufgaben und Ereignisse.
    public let done: Int
    /// Aufgaben und Ereignisse insgesamt - die Grundlage des Fortschritts-Rings.
    public let total: Int
    /// Erledigte Gewohnheiten.
    public let habitsDone: Int
    public let habitsTotal: Int
    public let isVacation: Bool

    public init(done: Int, total: Int, habitsDone: Int, habitsTotal: Int, isVacation: Bool) {
        self.done = done
        self.total = total
        self.habitsDone = habitsDone
        self.habitsTotal = habitsTotal
        self.isVacation = isVacation
    }

    /// Ein Tag ohne jeden Eintrag. Zaehlt fuer die Streak als neutral.
    public var isEmpty: Bool { total == 0 && habitsTotal == 0 }

    /// Alles Abhakbare zusammen - Termine, Aufgaben und Gewohnheiten.
    ///
    /// Die urspruengliche Spezifikation liess Gewohnheiten aussen vor. Das
    /// fuehrt zu einem Ring, der sich nicht ruehrt, obwohl man gerade etwas
    /// erledigt hat - und damit zu der berechtigten Frage, ob die Anzeige kaputt
    /// ist. Was man abhaken kann, muss zaehlen.
    public var completedTotal: Int { done + habitsDone }
    public var itemTotal: Int { total + habitsTotal }

    public var isPerfect: Bool {
        !isEmpty && completedTotal == itemTotal
    }

    /// 0.0 bis 1.0 ueber alle Eintraege des Tages.
    public var fraction: Double {
        guard itemTotal > 0 else { return 0 }
        return Double(completedTotal) / Double(itemTotal)
    }

    public var percent: Int { Int((fraction * 100).rounded()) }
}

public extension DashboardState {

    // MARK: - Tageswerte

    func stats(for day: DateKey, today: DateKey = .today) -> DayStats {
        let agenda = agenda(for: day, today: today)
        let doneEvents = agenda.events.count { completions.isDone($0.id, on: day) }
        let doneTasks = agenda.tasks.count { completions.isDone($0.id, on: day) }
        let doneHabits = agenda.habits.count { completions.isDone($0.id, on: day) }

        return DayStats(
            done: doneEvents + doneTasks,
            total: agenda.events.count + agenda.tasks.count,
            habitsDone: doneHabits,
            habitsTotal: agenda.habits.count,
            isVacation: agenda.isVacation
        )
    }

    // MARK: - Streak (Spezifikation 4.10)

    /// Aufeinanderfolgende perfekte Tage, rueckwaerts gezaehlt.
    ///
    /// - Ist heute noch nicht perfekt, beginnt die Zaehlung bei gestern; der
    ///   laufende Tag soll eine Serie nicht kappen, nur weil er noch offen ist.
    /// - Leere Tage und Urlaubstage sind neutral: sie zaehlen nicht mit, brechen
    ///   die Serie aber auch nicht ab.
    /// - Ein nicht perfekter Tag mit Eintraegen ausserhalb des Urlaubs beendet sie.
    func currentStreak(today: DateKey = .today) -> Int {
        var streak = 0
        var day = stats(for: today, today: today).isPerfect ? today : today.adding(days: -1)
        let floor = earliestRelevantDay(today: today)

        while day >= floor {
            if isVacationDay(day, today: today) {
                day = day.adding(days: -1)
                continue
            }
            let dayStats = stats(for: day, today: today)
            if dayStats.isEmpty {
                day = day.adding(days: -1)
                continue
            }
            guard dayStats.isPerfect else { break }
            streak += 1
            day = day.adding(days: -1)
        }
        return streak
    }

    /// Anzahl perfekter Tage in den letzten `days` Tagen einschliesslich heute.
    func perfectDayCount(lastDays days: Int, today: DateKey = .today) -> Int {
        (0..<days).count { offset in
            stats(for: today.adding(days: -offset), today: today).isPerfect
        }
    }

    /// Gesamtzahl aller je gesetzten Erledigt-Markierungen.
    var totalCompletionCount: Int { completions.totalCount }

    // MARK: - Intern

    /// Frueheste Grenze fuer Rueckwaertslaeufe: vor dem ersten Eintrag gibt es
    /// nichts zu zaehlen. Verhindert, dass die Streak-Suche jahrelang durch
    /// leere Tage laeuft.
    ///
    /// Gewohnheiten haben kein Startdatum - ihre Historie steckt allein in den
    /// Markierungen, die deshalb mit einfliessen.
    private func earliestRelevantDay(today: DateKey) -> DateKey {
        let starts = tasks.map(\.startDate) + events.map(\.startDate)
        let earliest = (starts + [completions.earliestDay].compactMap { $0 }).min() ?? today
        // Sicherheitsgrenze, falls jemand ein Datum weit in der Vergangenheit anlegt.
        return Swift.max(earliest, today.adding(days: -366 * 5))
    }
}

private extension Sequence {
    /// Zaehlt Elemente, die das Praedikat erfuellen.
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
