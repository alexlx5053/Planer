import Foundation

public extension Recurring {

    /// Faellt dieser Eintrag auf den angegebenen Tag? (Spezifikation 4.8)
    ///
    /// Urlaub wird hier bewusst **nicht** beruecksichtigt - das ist eine Frage der
    /// Sichtbarkeit, nicht der Wiederholung, und steckt in `DashboardState`.
    func occurs(on day: DateKey) -> Bool {
        // Ein verschobenes Vorkommen faellt an seinem alten Tag aus.
        guard !skippedDates.contains(day) else { return false }
        guard recurrence != .none else { return day == startDate }
        guard day >= startDate else { return false }

        switch recurrence {
        case .none:
            return false // oben bereits behandelt

        case .daily:
            return true

        case .weekly:
            return weekdays.isEmpty || weekdays.contains(day.weekdayIndex)

        case .monthly:
            // Gleicher Tag des Monats. Ein am 31. angelegter Eintrag hat in
            // kuerzeren Monaten also kein Vorkommen - so ist es spezifiziert.
            guard day.day == startDate.day else { return false }
            return months.isEmpty || months.contains(day.month)

        case .quarterly:
            guard day.day == startDate.day else { return false }
            let activeMonths = months.isEmpty ? Self.defaultQuarterMonths : months
            return activeMonths.contains(day.month)

        case .yearly:
            return day.day == startDate.day && day.month == startDate.month
        }
    }

    /// Vorgabe fuer `quarterly`, wenn keine Monate gewaehlt sind: Januar, April,
    /// Juli, Oktober.
    static var defaultQuarterMonths: Set<Int> { [1, 4, 7, 10] }

    /// Naechstes Vorkommen ab einschliesslich `day`, hoechstens `limit` Tage voraus.
    func nextOccurrence(from day: DateKey, within limit: Int = 90) -> DateKey? {
        var candidate = day
        for _ in 0...limit {
            if occurs(on: candidate) { return candidate }
            candidate = candidate.adding(days: 1)
        }
        return nil
    }
}
