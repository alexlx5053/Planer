import Foundation

// MARK: - Art der Veranstaltung

public enum CourseKind: String, Codable, CaseIterable, Sendable {
    case lecture, exercise, seminar, lab, tutorial, other

    public var label: String {
        switch self {
        case .lecture: "Vorlesung"
        case .exercise: "Übung"
        case .seminar: "Seminar"
        case .lab: "Praktikum"
        case .tutorial: "Tutorium"
        case .other: "Sonstiges"
        }
    }

    /// Kurzform fuer die Kachel im Raster, wo der Platz knapp ist.
    public var shortLabel: String {
        switch self {
        case .lecture: "VL"
        case .exercise: "Ü"
        case .seminar: "SE"
        case .lab: "PR"
        case .tutorial: "TU"
        case .other: "—"
        }
    }
}

// MARK: - Wochenrhythmus

/// Jede Woche, oder nur in geraden bzw. ungeraden Kalenderwochen.
///
/// Zweiwoechentliche Veranstaltungen sind an der Uni die Regel, und im
/// Vorlesungsverzeichnis stehen sie genau so: „gerade KW". Ein Startdatum, von
/// dem aus jede zweite Woche gezaehlt wird, waere dasselbe in schwerer -
/// niemand weiss auswendig, ob seine erste Sitzung in einer geraden Woche lag.
public enum WeekPattern: String, Codable, CaseIterable, Sendable {
    case every, even, odd

    public var label: String {
        switch self {
        case .every: "Jede Woche"
        case .even: "Gerade KW"
        case .odd: "Ungerade KW"
        }
    }

    public var shortLabel: String? {
        switch self {
        case .every: nil
        case .even: "gerade KW"
        case .odd: "ungerade KW"
        }
    }

    public func matches(_ day: DateKey) -> Bool {
        switch self {
        case .every: true
        case .even: day.weekOfYear % 2 == 0
        case .odd: day.weekOfYear % 2 == 1
        }
    }
}

// MARK: - Kurs

/// Eine Veranstaltung im Stundenplan: ein Modul, das jede Woche zur selben Zeit
/// am selben Ort stattfindet.
///
/// **Kein Termin.** Ein Kurs steht bewusst neben Terminen, Aufgaben und
/// Gewohnheiten und nicht unter ihnen:
///
/// - Er wird nicht abgehakt. Eine Vorlesung ist kein Vorhaben, das man erledigt,
///   sondern eine Zeit, die belegt ist. Haekte man sie ab, waeren der
///   Fortschritts-Ring und die Serie an jedem Vorlesungstag von zwanzig
///   Pflichtterminen bestimmt und saegten die eigene Tagesplanung entzwei.
/// - Er hat einen Anfang **und** ein Ende. Nur deshalb laesst sich sagen, wann
///   noch Zeit frei ist.
/// - Er gilt nur im Semester. Danach verschwindet er von selbst, ohne dass man
///   zwanzig Eintraege loeschen muss.
public struct CourseItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: CourseKind
    /// Wochentag in der Zaehlung der App: 0 = Sonntag ... 6 = Samstag.
    public var weekday: Int
    public var start: ClockTime
    public var end: ClockTime
    public var room: String
    public var lecturer: String
    /// Kennung der Farbe aus der Palette.
    public var colorKey: String
    public var weeks: WeekPattern
    /// Erster und letzter Tag des Semesters, in dem der Kurs laeuft.
    public var firstDay: DateKey
    public var lastDay: DateKey
    /// Einzelne Sitzungen, die ausfallen.
    public var skippedDates: Set<DateKey>

    public init(
        id: UUID = UUID(),
        title: String,
        kind: CourseKind = .lecture,
        weekday: Int = 1,
        start: ClockTime = ClockTime(hour: 10),
        end: ClockTime = ClockTime(hour: 12),
        room: String = "",
        lecturer: String = "",
        colorKey: String = "stone",
        weeks: WeekPattern = .every,
        firstDay: DateKey? = nil,
        lastDay: DateKey? = nil,
        skippedDates: Set<DateKey> = []
    ) {
        let semester = Semester.current()
        self.id = id
        self.title = title
        self.kind = kind
        self.weekday = weekday
        self.start = start
        self.end = Swift.max(start, end)
        self.room = room
        self.lecturer = lecturer
        self.colorKey = colorKey
        self.weeks = weeks
        self.firstDay = firstDay ?? semester.firstDay
        self.lastDay = lastDay ?? semester.lastDay
        self.skippedDates = skippedDates
    }

    public var span: TimeSpan { TimeSpan(start: start, end: end) }

    /// `"Analysis II"` mit Art und Raum, wie man es jemandem am Telefon sagen
    /// wuerde. Fuer Sprachausgabe und Kurzhinweise.
    public var spokenDescription: String {
        var parts = ["\(kind.label) \(title)", span.text]
        if !room.isEmpty { parts.append("Raum \(room)") }
        return parts.joined(separator: ", ")
    }

    /// Faellt eine Sitzung dieses Kurses auf den angegebenen Tag?
    ///
    /// Feiertage bleiben hier aussen vor - das entscheidet `DashboardState`,
    /// weil es eine Frage der Sichtbarkeit ist und nicht des Rhythmus.
    public func occurs(on day: DateKey) -> Bool {
        guard !skippedDates.contains(day) else { return false }
        guard day >= firstDay, day <= lastDay else { return false }
        guard day.weekdayIndex == weekday else { return false }
        return weeks.matches(day)
    }

    /// Naechste Sitzung ab einschliesslich `day`.
    public func nextSession(from day: DateKey, within limit: Int = 90) -> DateKey? {
        var candidate = day
        for _ in 0...limit {
            if occurs(on: candidate) { return candidate }
            candidate = candidate.adding(days: 1)
        }
        return nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, weekday, start, end, room, lecturer, colorKey, weeks,
             firstDay, lastDay, skippedDates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let semester = Semester.current()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = try c.decodeIfPresent(CourseKind.self, forKey: .kind) ?? .lecture
        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 1
        start = try c.decodeIfPresent(ClockTime.self, forKey: .start) ?? ClockTime(hour: 10)
        end = try c.decodeIfPresent(ClockTime.self, forKey: .end) ?? ClockTime(hour: 12)
        room = try c.decodeIfPresent(String.self, forKey: .room) ?? ""
        lecturer = try c.decodeIfPresent(String.self, forKey: .lecturer) ?? ""
        colorKey = try c.decodeIfPresent(String.self, forKey: .colorKey) ?? "stone"
        weeks = try c.decodeIfPresent(WeekPattern.self, forKey: .weeks) ?? .every
        firstDay = try c.decodeIfPresent(DateKey.self, forKey: .firstDay) ?? semester.firstDay
        lastDay = try c.decodeIfPresent(DateKey.self, forKey: .lastDay) ?? semester.lastDay
        skippedDates = try c.decodeIfPresent(Set<DateKey>.self, forKey: .skippedDates) ?? []
    }
}

// MARK: - Semester

/// Der Zeitraum, in dem ein Kurs laeuft.
///
/// Vorbelegung fuer neue Kurse: Sommersemester von April bis September,
/// Wintersemester von Oktober bis Maerz. Das trifft nicht jede Hochschule auf
/// den Tag genau, aber es trifft das Semester - und ein Datum zu korrigieren ist
/// weniger Arbeit, als zwei von Hand einzutippen.
public struct Semester: Hashable, Sendable {
    public let firstDay: DateKey
    public let lastDay: DateKey

    public init(firstDay: DateKey, lastDay: DateKey) {
        self.firstDay = firstDay
        self.lastDay = lastDay
    }

    public static func current(on day: DateKey = .today) -> Semester {
        if (4...9).contains(day.month) {
            return Semester(
                firstDay: DateKey(year: day.year, month: 4, day: 1),
                lastDay: DateKey(year: day.year, month: 9, day: 30)
            )
        }
        // Das Wintersemester laeuft ueber den Jahreswechsel: Im Januar bis Maerz
        // hat es im Oktober des Vorjahres begonnen.
        let startYear = day.month >= 10 ? day.year : day.year - 1
        return Semester(
            firstDay: DateKey(year: startYear, month: 10, day: 1),
            lastDay: DateKey(year: startYear + 1, month: 3, day: 31)
        )
    }

    public var label: String {
        (4...9).contains(firstDay.month)
            ? "Sommersemester \(firstDay.year)"
            : "Wintersemester \(firstDay.year)/\(String(format: "%02d", (firstDay.year + 1) % 100))"
    }
}
