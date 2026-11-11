import Foundation

// MARK: - Belegter Block

/// Eine belegte Zeitspanne an einem Tag - gleich, ob sie von einem Kurs oder
/// von einem Termin stammt.
///
/// Beide zusammen beantworten die Frage, um die es geht: Wann habe ich Zeit?
/// Sie getrennt zu behandeln hiesse, die Antwort zweimal zu geben und beim
/// Zusammenrechnen die Luecken falsch zu bekommen.
public struct BusyBlock: Identifiable, Hashable, Sendable {

    public enum Source: Hashable, Sendable {
        case course(CourseItem)
        case event(EventItem)
    }

    public let span: TimeSpan
    public let source: Source

    public init(span: TimeSpan, source: Source) {
        self.span = span
        self.source = source
    }

    public init(course: CourseItem) {
        self.init(span: course.span, source: .course(course))
    }

    /// `nil`, wenn der Termin keine Uhrzeit hat - dann belegt er keine Spanne.
    public init?(event: EventItem) {
        guard let span = event.span else { return nil }
        self.init(span: span, source: .event(event))
    }

    public var id: UUID {
        switch source {
        case .course(let item): item.id
        case .event(let item): item.id
        }
    }

    public var title: String {
        switch source {
        case .course(let item): item.title
        case .event(let item): item.title
        }
    }

    public var colorKey: String {
        switch source {
        case .course(let item): item.colorKey
        case .event(let item): item.colorKey
        }
    }

    public var isCourse: Bool {
        if case .course = source { return true }
        return false
    }

    /// Raum beim Kurs, sonst leer.
    public var room: String {
        if case .course(let item) = source { return item.room }
        return ""
    }

    public var course: CourseItem? {
        if case .course(let item) = source { return item }
        return nil
    }

    public var event: EventItem? {
        if case .event(let item) = source { return item }
        return nil
    }

    /// Fuer Sprachausgabe und Konflikthinweise: „Vorlesung Analysis II,
    /// 10:00–11:30".
    public var label: String {
        switch source {
        case .course(let item): "\(item.kind.label) \(item.title)"
        case .event(let item): item.title
        }
    }
}

// MARK: - Stundenplan

public extension DashboardState {

    /// Das Zeitfenster, in dem die App nach freier Zeit sucht.
    ///
    /// Acht bis acht. Nachts ist streng genommen auch frei, aber ein Vorschlag
    /// „03:00 – 07:00" waere kein Vorschlag, sondern Hohn.
    static let plannableDay = TimeSpan(start: ClockTime(hour: 8), end: ClockTime(hour: 20))

    /// Die Sitzungen des Tages, nach Uhrzeit sortiert.
    ///
    /// Zwei Gruende, warum hier etwas wegfallen kann:
    ///
    /// - **Feiertag.** An Allerheiligen findet keine Vorlesung statt. Die
    ///   Feiertage stehen der App bereits zur Verfuegung, also nutzt sie sie -
    ///   und zeigt in der Spalte den Namen des Feiertags, damit die Luecke
    ///   erklaert ist.
    /// - **Urlaub.** Wer verreist ist, sitzt nicht in der Uebung. Das ist
    ///   dieselbe Regel, nach der auch Gewohnheiten und Wiederkehrendes
    ///   pausieren.
    func courses(on day: DateKey, today: DateKey = .today) -> [CourseItem] {
        guard !isVacationDay(day, today: today) else { return [] }
        guard !Holidays.isHoliday(day) else { return [] }
        return courses
            .filter { $0.occurs(on: day) }
            .sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
    }

    /// Alles, was an diesem Tag Zeit belegt: Kurse und Termine mit Uhrzeit.
    func busyBlocks(on day: DateKey, today: DateKey = .today) -> [BusyBlock] {
        let fromCourses = courses(on: day, today: today).map { BusyBlock(course: $0) }
        let fromEvents = events(on: day, today: today).compactMap { BusyBlock(event: $0) }
        return (fromCourses + fromEvents).sorted { ($0.span, $0.title) < ($1.span, $1.title) }
    }

    /// Die freien Luecken des Tages.
    ///
    /// - Parameters:
    ///   - window: Der betrachtete Tagesabschnitt. Er wird nach Bedarf
    ///     erweitert: Beginnt um sieben eine Vorlesung, faengt der Tag eben um
    ///     sieben an.
    ///   - minimumMinutes: Kuerzere Luecken werden verschwiegen. Zwischen zwei
    ///     Vorlesungen bleiben gern zehn Minuten - das ist der Weg zum
    ///     Hoersaal, kein Zeitfenster.
    func freeSlots(
        on day: DateKey,
        today: DateKey = .today,
        window: TimeSpan = DashboardState.plannableDay,
        minimumMinutes: Int = 30
    ) -> [TimeSpan] {
        let blocks = busyBlocks(on: day, today: today).map(\.span).merged()
        let bounds = Self.expanded(window, toCover: blocks)

        var free: [TimeSpan] = []
        var cursor = bounds.start

        for block in blocks {
            guard block.end > bounds.start, block.start < bounds.end else { continue }
            if block.start > cursor {
                free.append(TimeSpan(start: cursor, end: min(block.start, bounds.end)))
            }
            cursor = max(cursor, block.end)
        }
        if cursor < bounds.end {
            free.append(TimeSpan(start: cursor, end: bounds.end))
        }

        return free.filter { $0.minutes >= minimumMinutes }
    }

    /// Womit sich eine geplante Zeitspanne an diesem Tag ueberschneidet.
    ///
    /// - Parameter ignoring: Der Eintrag, der gerade bearbeitet wird. Ohne das
    ///   meldete jeder Termin beim Oeffnen einen Konflikt mit sich selbst.
    func conflicts(
        with span: TimeSpan,
        on day: DateKey,
        today: DateKey = .today,
        ignoring id: UUID? = nil
    ) -> [BusyBlock] {
        busyBlocks(on: day, today: today)
            .filter { $0.id != id }
            .filter { $0.span.overlaps(span) }
    }

    /// Die naechste Sitzung an diesem Tag ab der angegebenen Uhrzeit.
    func nextCourse(on day: DateKey, after time: ClockTime, today: DateKey = .today) -> CourseItem? {
        courses(on: day, today: today).first { $0.end > time }
    }

    /// Der Semesterzeitraum, den ein neuer Kurs erbt.
    ///
    /// Vorbelegt wird der Zeitraum des zuletzt angelegten Kurses. Wer zehn
    /// Module eintraegt, tippt das Semester damit einmal und nicht zehnmal.
    var semesterForNewCourse: Semester {
        guard let last = courses.last else { return Semester.current() }
        return Semester(firstDay: last.firstDay, lastDay: last.lastDay)
    }

    // MARK: - Intern

    /// Erweitert das Fenster so, dass alle Bloecke hineinpassen.
    private static func expanded(_ window: TimeSpan, toCover blocks: [TimeSpan]) -> TimeSpan {
        guard let first = blocks.first, let last = blocks.max(by: { $0.end < $1.end }) else {
            return window
        }
        return TimeSpan(
            start: min(window.start, first.start),
            end: max(window.end, last.end)
        )
    }
}

// MARK: - Anordnung nebeneinander

/// Ein Block samt der Spur, in der er gezeichnet wird.
public struct LaidOutBlock: Identifiable, Sendable {
    public let block: BusyBlock
    /// Nullbasierte Spur von links.
    public let lane: Int
    /// Wie viele Spuren die Gruppe breit ist, zu der er gehoert.
    public let laneCount: Int
    /// Ueberschneidet er sich mit einem anderen Block?
    public let isConflicting: Bool

    public var id: UUID { block.id }

    public init(block: BusyBlock, lane: Int, laneCount: Int, isConflicting: Bool) {
        self.block = block
        self.lane = lane
        self.laneCount = laneCount
        self.isConflicting = isConflicting
    }
}

/// Verteilt sich ueberschneidende Bloecke nebeneinander.
///
/// Ohne das legte ein Termin die Vorlesung zu, mit der er sich beisst - und
/// genau die wollte man sehen.
///
/// Das Verfahren: Jeder Block kommt in die erste Spur, die zu seiner Anfangszeit
/// frei ist. Wie breit eine Stelle wird, entscheidet nicht der ganze Tag,
/// sondern die Gruppe zusammenhaengend belegter Zeit - sonst wuerde ein
/// Doppeltermin am Morgen den ganzen Nachmittag schmal machen.
public enum TimetableLayout {

    public static func lanes(for blocks: [BusyBlock]) -> [LaidOutBlock] {
        let sorted = blocks.sorted { ($0.span, $0.title) < ($1.span, $1.title) }
        guard !sorted.isEmpty else { return [] }

        /// Bis wann die jeweilige Spur belegt ist.
        var laneEnds: [ClockTime] = []
        var lanes: [Int] = []
        var groups: [Int] = []
        var groupIndex = 0
        var groupEnd: ClockTime?

        for block in sorted {
            // Beginnt der Block nach allem Bisherigen, faengt eine neue Gruppe
            // an und alle Spuren sind wieder frei.
            if let end = groupEnd, block.span.start >= end {
                groupIndex += 1
                laneEnds.removeAll()
                groupEnd = nil
            }

            if let free = laneEnds.firstIndex(where: { $0 <= block.span.start }) {
                laneEnds[free] = block.span.end
                lanes.append(free)
            } else {
                laneEnds.append(block.span.end)
                lanes.append(laneEnds.count - 1)
            }

            groups.append(groupIndex)
            groupEnd = max(groupEnd ?? block.span.end, block.span.end)
        }

        var laneCounts: [Int: Int] = [:]
        for (group, lane) in zip(groups, lanes) {
            laneCounts[group] = max(laneCounts[group] ?? 0, lane + 1)
        }

        return sorted.enumerated().map { index, block in
            LaidOutBlock(
                block: block,
                lane: lanes[index],
                laneCount: laneCounts[groups[index]] ?? 1,
                isConflicting: sorted.contains {
                    $0.id != block.id && $0.span.overlaps(block.span)
                }
            )
        }
    }
}
