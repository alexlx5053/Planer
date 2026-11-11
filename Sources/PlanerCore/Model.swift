import Foundation

// MARK: - Aufzaehlungen

/// Wiederholungsrhythmus. Rohwerte bleiben stabil, weil sie in der Datei landen.
public enum Recurrence: String, Codable, CaseIterable, Sendable {
    case none, daily, weekly, monthly, quarterly, yearly

    public var label: String {
        switch self {
        case .none: "Einmalig"
        case .daily: "Täglich"
        case .weekly: "Wöchentlich"
        case .monthly: "Monatlich"
        case .quarterly: "Vierteljährlich"
        case .yearly: "Jährlich"
        }
    }

    /// Kurzform fuer die Kennzeichnung in Listenzeilen.
    public var shortLabel: String? {
        switch self {
        case .none: nil
        case .daily: "täglich"
        case .weekly: "wöchentlich"
        case .monthly: "monatlich"
        case .quarterly: "quartal"
        case .yearly: "jährlich"
        }
    }
}

public enum Priority: String, Codable, CaseIterable, Sendable {
    case low, normal, high

    public var label: String {
        switch self {
        case .low: "Niedrig"
        case .normal: "Normal"
        case .high: "Hoch"
        }
    }
}

// MARK: - Wiederholbare Eintraege

/// Gemeinsame Grundlage von Aufgabe und Ereignis, damit `occursOn` nur einmal
/// existiert (siehe `Recurrence+Occurrence.swift`).
public protocol Recurring {
    var startDate: DateKey { get }
    var recurrence: Recurrence { get }
    /// Wochentage fuer `weekly`, 0 = Sonntag ... 6 = Samstag. Leer = jeder Tag.
    var weekdays: Set<Int> { get }
    /// Monate fuer `monthly`/`quarterly`, 1-12. Leer = keine Einschraenkung.
    var months: Set<Int> { get }
    /// Einzelne Tage, an denen der Eintrag ausfaellt.
    ///
    /// Noetig, um ein einzelnes Vorkommen zu verschieben, ohne die ganze Serie
    /// mitzunehmen: Der alte Tag faellt aus, der neue bekommt einen eigenen
    /// Eintrag.
    var skippedDates: Set<DateKey> { get }
}

// MARK: - Aufgabe

public struct TaskItem: Identifiable, Codable, Hashable, Sendable, Recurring {
    public var id: UUID
    public var title: String
    public var startDate: DateKey
    public var recurrence: Recurrence
    public var priority: Priority
    public var weekdays: Set<Int>
    public var months: Set<Int>
    /// Verknuepfung zu einem Ziel bzw. Meilenstein (bleibt in v1 leer).
    public var goalID: UUID?
    public var milestoneID: UUID?
    public var skippedDates: Set<DateKey>

    public init(
        id: UUID = UUID(),
        title: String,
        startDate: DateKey = .today,
        recurrence: Recurrence = .none,
        priority: Priority = .normal,
        weekdays: Set<Int> = [],
        months: Set<Int> = [],
        goalID: UUID? = nil,
        milestoneID: UUID? = nil,
        skippedDates: Set<DateKey> = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.recurrence = recurrence
        self.priority = priority
        self.weekdays = weekdays
        self.months = months
        self.goalID = goalID
        self.milestoneID = milestoneID
        self.skippedDates = skippedDates
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, recurrence, priority, weekdays, months, goalID, milestoneID,
             skippedDates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startDate = try c.decodeIfPresent(DateKey.self, forKey: .startDate) ?? .today
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
        months = try c.decodeIfPresent(Set<Int>.self, forKey: .months) ?? []
        goalID = try c.decodeIfPresent(UUID.self, forKey: .goalID)
        milestoneID = try c.decodeIfPresent(UUID.self, forKey: .milestoneID)
        skippedDates = try c.decodeIfPresent(Set<DateKey>.self, forKey: .skippedDates) ?? []
    }
}

// MARK: - Ereignis

public struct EventItem: Identifiable, Codable, Hashable, Sendable, Recurring {
    public var id: UUID
    public var title: String
    public var startDate: DateKey
    /// `"HH:MM"` oder `nil`, wenn das Ereignis keine Uhrzeit hat.
    public var time: String?
    /// Wie lange der Termin dauert, in Minuten. `nil`, wenn nichts angegeben ist.
    ///
    /// Erst damit laesst sich sagen, ob ein Termin in eine Luecke zwischen zwei
    /// Vorlesungen passt. Ohne Angabe rechnet die App mit einer Stunde - eine
    /// Annahme, die haeufiger stimmt als jede andere und die man im Blatt mit
    /// einem Griff aendert.
    public var durationMinutes: Int?
    /// Kennung der Farbe aus der Palette, z. B. `"stone"`.
    public var colorKey: String
    public var recurrence: Recurrence
    public var weekdays: Set<Int>
    public var months: Set<Int>
    public var notes: String
    public var skippedDates: Set<DateKey>

    public init(
        id: UUID = UUID(),
        title: String,
        startDate: DateKey = .today,
        time: String? = nil,
        durationMinutes: Int? = nil,
        colorKey: String = "stone",
        recurrence: Recurrence = .none,
        weekdays: Set<Int> = [],
        months: Set<Int> = [],
        notes: String = "",
        skippedDates: Set<DateKey> = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.time = time
        self.durationMinutes = durationMinutes
        self.colorKey = colorKey
        self.recurrence = recurrence
        self.weekdays = weekdays
        self.months = months
        self.notes = notes
        self.skippedDates = skippedDates
    }

    /// Die Uhrzeit als Wert; `nil` bei einem ganztaegigen Termin.
    public var clock: ClockTime? {
        time.flatMap { ClockTime($0) }
    }

    /// Minuten seit Mitternacht; `nil` ohne Uhrzeit. Fuer die Sortierung.
    public var minutesOfDay: Int? { clock?.minutes }

    /// Die belegte Zeitspanne; `nil` bei einem ganztaegigen Termin.
    ///
    /// Ohne angegebene Dauer eine Stunde: Ein Block ohne Ausdehnung waere in
    /// jeder Darstellung unsichtbar und in jeder Konfliktpruefung blind.
    public var span: TimeSpan? {
        guard let clock else { return nil }
        return TimeSpan(start: clock, minutes: durationMinutes ?? Self.assumedDuration)
    }

    /// Angenommene Dauer, wenn keine angegeben ist.
    public static let assumedDuration = 60

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, time, durationMinutes, colorKey, recurrence, weekdays, months,
             notes, skippedDates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startDate = try c.decodeIfPresent(DateKey.self, forKey: .startDate) ?? .today
        time = try c.decodeIfPresent(String.self, forKey: .time)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        colorKey = try c.decodeIfPresent(String.self, forKey: .colorKey) ?? "stone"
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
        months = try c.decodeIfPresent(Set<Int>.self, forKey: .months) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        skippedDates = try c.decodeIfPresent(Set<DateKey>.self, forKey: .skippedDates) ?? []
    }
}

// MARK: - Gewohnheit

public struct HabitItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String

    /// Ab wann die Gewohnheit gilt.
    ///
    /// Ohne dieses Datum wuerde eine heute angelegte Gewohnheit rueckwirkend
    /// fuer jeden vergangenen Tag gelten - gestern waere dann unvollstaendig,
    /// weil etwas offen ist, das es gestern noch gar nicht gab, und die Serie
    /// bräche zusammen. Vergangenes soll sich nicht dadurch aendern, dass man
    /// sich heute etwas vornimmt.
    public var startDate: DateKey

    public init(id: UUID = UUID(), title: String, startDate: DateKey = .today) {
        self.id = id
        self.title = title
        self.startDate = startDate
    }

    private enum CodingKeys: String, CodingKey { case id, title, startDate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        // Aeltere Dateien kennen das Feld nicht. Fuer sie bleibt es beim
        // bisherigen Verhalten: Die Gewohnheit galt schon immer.
        startDate = try c.decodeIfPresent(DateKey.self, forKey: .startDate)
            ?? DateKey(year: 2000, month: 1, day: 1)
    }
}

// MARK: - Ziele (Datenmodell steht, Oberflaeche folgt spaeter)

public struct Milestone: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var targetDate: DateKey?
    public var isDone: Bool
    public var taskIDs: [UUID]

    public init(id: UUID = UUID(), title: String, targetDate: DateKey? = nil,
                isDone: Bool = false, taskIDs: [UUID] = []) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.isDone = isDone
        self.taskIDs = taskIDs
    }
}

public struct Goal: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var targetDate: DateKey?
    public var createdDate: DateKey
    public var milestones: [Milestone]

    public init(id: UUID = UUID(), title: String, targetDate: DateKey? = nil,
                createdDate: DateKey = .today, milestones: [Milestone] = []) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.createdDate = createdDate
        self.milestones = milestones
    }
}

// MARK: - Journal (Datenmodell steht, Oberflaeche folgt spaeter)

public struct JournalEntry: Codable, Hashable, Sendable {
    public var text: String
    /// 1 bis 5, `nil` wenn nicht erfasst.
    public var mood: Int?

    public init(text: String = "", mood: Int? = nil) {
        self.text = text
        self.mood = mood
    }

    public var isEmpty: Bool { text.isEmpty && mood == nil }
}

// MARK: - Urlaub

public struct VacationState: Codable, Hashable, Sendable {
    public var isActive: Bool
    public var since: DateKey?

    public init(isActive: Bool = false, since: DateKey? = nil) {
        self.isActive = isActive
        self.since = since
    }
}

public struct VacationRange: Codable, Hashable, Sendable {
    public var start: DateKey
    public var end: DateKey

    public init(start: DateKey, end: DateKey) {
        self.start = start
        self.end = end
    }

    public func contains(_ day: DateKey) -> Bool {
        day >= start && day <= end
    }
}

public extension Array where Element == VacationRange {

    /// Fasst Zeitraeume zusammen und wirft Doppelungen weg.
    ///
    /// Jedes Beenden eines Urlaubs haengt einen Eintrag an. Ohne Aufraeumen
    /// sammeln sich bei mehrfachem Umschalten identische Zeitraeume an, die
    /// niemand mehr auseinanderhalten kann.
    func normalized() -> [VacationRange] {
        let sorted = self.sorted { $0.start < $1.start }
        var result: [VacationRange] = []

        for range in sorted {
            if let last = result.last, range.start <= last.end.adding(days: 1) {
                result[result.count - 1] = VacationRange(
                    start: last.start,
                    end: Swift.max(last.end, range.end)
                )
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Nimmt einen einzelnen Tag aus allen Zeitraeumen heraus.
    ///
    /// Ein Zeitraum, der den Tag umschliesst, zerfaellt dabei in die beiden
    /// Stuecke davor und danach.
    func removing(_ day: DateKey) -> [VacationRange] {
        flatMap { range -> [VacationRange] in
            guard range.contains(day) else { return [range] }
            var pieces: [VacationRange] = []
            if range.start < day {
                pieces.append(VacationRange(start: range.start, end: day.adding(days: -1)))
            }
            if range.end > day {
                pieces.append(VacationRange(start: day.adding(days: 1), end: range.end))
            }
            return pieces
        }
    }
}

// MARK: - Erledigt-Status

/// Erledigt-Markierungen aller Eintragsarten, nach Eintrags-ID und Tag.
///
/// Abweichung von der urspruenglichen Spezifikation: Dort gab es drei getrennte
/// Mechanismen (`taskDone`, `habitDone`, `events[].completions`) fuer denselben
/// Sachverhalt. Hier ist es einer - ein Umschaltweg, eine Auswertung, eine
/// Fehlerquelle statt drei.
public struct CompletionStore: Codable, Hashable, Sendable {
    private var storage: [String: Set<DateKey>]

    public init() { storage = [:] }

    public subscript(id: UUID) -> Set<DateKey> {
        get { storage[id.uuidString] ?? [] }
        set {
            if newValue.isEmpty { storage.removeValue(forKey: id.uuidString) }
            else { storage[id.uuidString] = newValue }
        }
    }

    public func isDone(_ id: UUID, on day: DateKey) -> Bool {
        storage[id.uuidString]?.contains(day) ?? false
    }

    public mutating func setDone(_ id: UUID, on day: DateKey, _ done: Bool) {
        var days = self[id]
        if done { days.insert(day) } else { days.remove(day) }
        self[id] = days
    }

    @discardableResult
    public mutating func toggle(_ id: UUID, on day: DateKey) -> Bool {
        let next = !isDone(id, on: day)
        setDone(id, on: day, next)
        return next
    }

    public mutating func remove(_ id: UUID) {
        storage.removeValue(forKey: id.uuidString)
    }

    /// Gesamtzahl aller je gesetzten Markierungen (Kennzahl "Gesamt-Erledigt").
    public var totalCount: Int {
        storage.values.reduce(0) { $0 + $1.count }
    }

    /// Aeltester markierter Tag - Untergrenze fuer Rueckwaertslaeufe.
    public var earliestDay: DateKey? {
        storage.values.compactMap { $0.min() }.min()
    }

    // MARK: Codable
    //
    // Geschrieben wird `{"<uuid>": ["2026-09-04", ...]}`. Gelesen wird zusaetzlich
    // die alte Artefakt-Form `{"<uuid>": {"2026-09-04": true}}`, damit Daten aus
    // dem HTML-Prototyp uebernommen werden koennen.

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let modern = try? container.decode([String: Set<DateKey>].self) {
            storage = modern
            return
        }
        let legacy = try container.decode([String: [String: Bool]].self)
        storage = legacy.reduce(into: [:]) { result, entry in
            let days = entry.value.compactMap { $0.value ? DateKey($0.key) : nil }
            if !days.isEmpty { result[entry.key] = Set(days) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage.mapValues { $0.sorted() })
    }
}

// MARK: - Gesamtzustand

/// Der vollstaendige App-Zustand - genau das, was in der JSON-Datei liegt.
///
/// Jedes Feld wird beim Dekodieren mit `decodeIfPresent` gelesen: Eine aeltere
/// Datei ohne neu hinzugekommene Felder laedt dadurch sauber, statt den Start
/// scheitern zu lassen.
public struct DashboardState: Codable, Hashable, Sendable {
    public var tasks: [TaskItem]
    public var events: [EventItem]
    public var habits: [HabitItem]

    /// Der Stundenplan: Veranstaltungen, die jede Woche zur selben Zeit laufen.
    ///
    /// Eine eigene Liste neben den Terminen, nicht darin. Kurse werden nicht
    /// abgehakt und zaehlen in keine Kennzahl - sie sind der feste Rahmen der
    /// Woche, in den man seine Termine legt.
    public var courses: [CourseItem]
    public var goals: [Goal]
    public var completions: CompletionStore
    public var journal: [DateKey: JournalEntry]
    public var vacation: VacationState
    public var vacationRanges: [VacationRange]

    /// Freie Notizen, die zu keinem Tag gehoeren.
    ///
    /// Bewusst nicht datumsgebunden: Es ist der Zettel neben dem Kalender, nicht
    /// ein Eintrag darin. Was man sich notiert, soll morgen noch da sein, ohne
    /// dass man den richtigen Tag wiederfinden muss.
    public var notes: String

    public init(
        tasks: [TaskItem] = [],
        events: [EventItem] = [],
        habits: [HabitItem] = [],
        courses: [CourseItem] = [],
        goals: [Goal] = [],
        completions: CompletionStore = CompletionStore(),
        journal: [DateKey: JournalEntry] = [:],
        vacation: VacationState = VacationState(),
        vacationRanges: [VacationRange] = [],
        notes: String = ""
    ) {
        self.tasks = tasks
        self.events = events
        self.habits = habits
        self.courses = courses
        self.goals = goals
        self.completions = completions
        self.journal = journal
        self.vacation = vacation
        self.vacationRanges = vacationRanges
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case tasks, events, habits, courses, goals, completions, journal, vacation, vacationRanges,
             notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        events = try c.decodeIfPresent([EventItem].self, forKey: .events) ?? []
        habits = try c.decodeIfPresent([HabitItem].self, forKey: .habits) ?? []
        courses = try c.decodeIfPresent([CourseItem].self, forKey: .courses) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        completions = try c.decodeIfPresent(CompletionStore.self, forKey: .completions) ?? CompletionStore()
        journal = try c.decodeIfPresent([DateKey: JournalEntry].self, forKey: .journal) ?? [:]
        vacation = try c.decodeIfPresent(VacationState.self, forKey: .vacation) ?? VacationState()
        vacationRanges = try c.decodeIfPresent([VacationRange].self, forKey: .vacationRanges) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}
