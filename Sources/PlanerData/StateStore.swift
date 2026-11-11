import Foundation
import PlanerCore
import Observation

/// Ein geloeschter Eintrag samt allem, was zum Wiederherstellen noetig ist.
///
/// Die Erledigt-Markierungen gehoeren dazu: Wer eine Gewohnheit versehentlich
/// loescht und zurueckholt, will nicht die Historie von drei Monaten verloren
/// haben.
public struct DeletedItem: Sendable {
    public enum Kind: Sendable {
        case task(TaskItem)
        case event(EventItem)
        case habit(HabitItem)
        case course(CourseItem)
    }

    public let kind: Kind
    public let index: Int
    public let completions: Set<DateKey>

    public var title: String {
        switch kind {
        case .task(let item): item.title
        case .event(let item): item.title
        case .habit(let item): item.title
        case .course(let item): item.title
        }
    }

    public var descriptionOfKind: String {
        switch kind {
        case .task: "Aufgabe"
        case .event: "Ereignis"
        case .habit: "Gewohnheit"
        case .course: "Kurs"
        }
    }
}

/// Wie das Laden ausgegangen ist - fuer den Hinweis in der Oberflaeche.
public enum LoadOutcome: Sendable, Equatable {
    /// Datei geladen oder erstmalig angelegt.
    case ok
    /// Datei war unlesbar; der Inhalt stammt aus einer Sicherung.
    case recoveredFromBackup(backup: String, quarantined: String?)
    /// Datei war unlesbar und es gab keine brauchbare Sicherung.
    case startedEmpty(quarantined: String?)
}

/// Haelt den App-Zustand, speichert ihn entprellt und beantwortet Auswertungen.
@MainActor
@Observable
public final class StateStore {

    public private(set) var state: DashboardState
    public private(set) var loadOutcome: LoadOutcome = .ok

    /// Der laufende Tag. Bewusst veraenderbar, damit die App ihn um Mitternacht
    /// weiterstellen kann, ohne dass etwas neu geladen werden muss.
    public var today: DateKey {
        didSet { if today != oldValue { cache.invalidateAll() } }
    }

    private let location: StoreLocation
    private let backups: BackupService
    @ObservationIgnored private let cache = StatsCache()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hasUnsavedChanges = false

    /// Wartezeit vor dem Schreiben. Die Oberflaeche zeigt Aenderungen sofort,
    /// die Platte sieht sie gesammelt.
    static let saveDelay = Duration.milliseconds(250)

    // MARK: - Aufbau

    public init(location: StoreLocation = .applicationSupport, today: DateKey = .today) {
        self.location = location
        self.backups = BackupService(location: location)
        self.today = today
        self.state = DashboardState()
        load()
    }

    /// Fuer Tests und Vorschauen: Zustand im Speicher, ohne Datei.
    public init(inMemory state: DashboardState, today: DateKey = .today) {
        self.location = StoreLocation(directory: URL(fileURLWithPath: "/dev/null"))
        self.backups = BackupService(location: location)
        self.today = today
        self.state = state
    }

    // MARK: - Laden

    private func load() {
        try? location.ensureDirectories()
        location.restrictExistingFiles()

        guard FileManager.default.fileExists(atPath: location.file.path) else {
            loadOutcome = .ok
            return
        }

        if let document = decodeDocument(at: location.file) {
            state = document.state
            loadOutcome = .ok
            try? backups.makeDailyBackup()
            return
        }

        // Ab hier ist die Hauptdatei unbrauchbar. Erst beiseitelegen, dann die
        // juengste lesbare Sicherung suchen.
        let quarantined = backups.quarantineCorruptFile()?.lastPathComponent

        for backup in backups.availableBackups() {
            if let document = decodeDocument(at: backup) {
                state = document.state
                loadOutcome = .recoveredFromBackup(
                    backup: backup.lastPathComponent,
                    quarantined: quarantined
                )
                // Sofort zurueckschreiben, damit der naechste Start wieder
                // regulaer laedt.
                persistNow()
                return
            }
        }

        state = DashboardState()
        loadOutcome = .startedEmpty(quarantined: quarantined)
    }

    private func decodeDocument(at url: URL) -> StoredDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? StoredDocument.decoder.decode(StoredDocument.self, from: data)
    }

    // MARK: - Speichern

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: StateStore.saveDelay)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// Schreibt sofort. Wird beim Beenden und Fenster-Schliessen aufgerufen.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        persistNow()
    }

    private func persistNow() {
        guard location.directory.path != "/dev/null" else {
            hasUnsavedChanges = false
            return
        }
        let document = StoredDocument(state: state)
        guard let data = try? StoredDocument.encoder.encode(document) else { return }

        do {
            try location.ensureDirectories()
            try data.write(to: location.file, options: [.atomic])
            // Atomar schreiben heisst: neue Datei, dann umbenennen. Die neue
            // Datei hat wieder die Standardrechte - also jedes Mal setzen.
            StoreLocation.restrictToOwner(location.file)
            hasUnsavedChanges = false
        } catch {
            // Beim naechsten Versuch erneut - der Zustand bleibt im Speicher
            // erhalten, nichts geht verloren.
            hasUnsavedChanges = true
        }
    }

    // MARK: - Auswertung
    //
    // Jeder dieser Zugriffe liest `state` ausdruecklich, bevor er den
    // Zwischenspeicher befragt.
    //
    // Der Grund ist die Beobachtung von SwiftUI: Sie merkt sich bei jedem
    // Aufbau einer Ansicht genau die Eigenschaften, die dabei gelesen wurden.
    // Antwortet der Zwischenspeicher, wird `state` nicht angefasst - die
    // Ansicht meldet sich damit still von Aenderungen ab und bemerkt einen neuen
    // Eintrag erst, wenn sie aus einem anderen Grund neu gezeichnet wird. Genau
    // das liess neue Gewohnheiten erst verspaetet erscheinen.
    private func observeState() { _ = state }

    public func stats(for day: DateKey) -> DayStats {
        observeState()
        return cache.stats(for: day, state: state, today: today)
    }

    public var streak: Int {
        observeState()
        return cache.currentStreak(state: state, today: today)
    }

    public func agenda(for day: DateKey) -> DayAgenda {
        observeState()
        return cache.agenda(for: day, state: state, today: today)
    }

    /// Die naechsten offenen Termine. (Spezifikation 4.12)
    public func upcomingEvents(limit: Int = 5) -> [UpcomingEvent] {
        observeState()
        return cache.upcomingEvents(state: state, today: today, limit: limit)
    }

    /// Alle anstehenden Termine eines Jahres - fuer die Gesamtliste.
    ///
    /// Je Termin das naechste Vorkommen, wie in der Seitenspalte: Ein
    /// woechentliches Training soll einmal dastehen und nicht zweiundfuenfzigmal.
    public func allUpcomingEvents() -> [UpcomingEvent] {
        observeState()
        return cache.upcomingEvents(state: state, today: today, limit: .max, horizon: 366)
    }

    public func isDone(_ id: UUID, on day: DateKey) -> Bool {
        state.completions.isDone(id, on: day)
    }

    // MARK: - Stundenplan

    /// Die Sitzungen eines Tages. Ueber die Tagesliste, damit beide denselben
    /// Zwischenspeicher benutzen.
    public func courses(on day: DateKey) -> [CourseItem] {
        agenda(for: day).courses
    }

    /// Was an diesem Tag Zeit belegt - Kurse und Termine mit Uhrzeit.
    public func busyBlocks(on day: DateKey) -> [BusyBlock] {
        agenda(for: day).busyBlocks
    }

    /// Die freien Luecken des Tages.
    public func freeSlots(on day: DateKey, minimumMinutes: Int = 30) -> [TimeSpan] {
        observeState()
        return state.freeSlots(on: day, today: today, minimumMinutes: minimumMinutes)
    }

    /// Womit sich eine geplante Zeitspanne ueberschneidet.
    public func conflicts(
        with span: TimeSpan,
        on day: DateKey,
        ignoring id: UUID? = nil
    ) -> [BusyBlock] {
        observeState()
        return state.conflicts(with: span, on: day, today: today, ignoring: id)
    }

    /// Hat der Stundenplan ueberhaupt einen Eintrag?
    ///
    /// Solange nicht, bleibt alles Uni-bezogene in der Oberflaeche unsichtbar.
    public var hasCourses: Bool { !state.courses.isEmpty }

    public var semesterForNewCourse: Semester { state.semesterForNewCourse }

    public func add(course: CourseItem) {
        state.courses.append(course)
        structuralChange()
    }

    public func update(course: CourseItem) {
        guard let index = state.courses.firstIndex(where: { $0.id == course.id }) else { return }
        state.courses[index] = course
        structuralChange()
    }

    /// Laesst eine einzelne Sitzung ausfallen, ohne den Kurs anzutasten.
    public func cancelSession(courseID: UUID, on day: DateKey) {
        guard let index = state.courses.firstIndex(where: { $0.id == courseID }) else { return }
        state.courses[index].skippedDates.insert(day)
        structuralChange()
    }

    /// Nimmt einen Ausfall zurueck.
    public func restoreSession(courseID: UUID, on day: DateKey) {
        guard let index = state.courses.firstIndex(where: { $0.id == courseID }) else { return }
        state.courses[index].skippedDates.remove(day)
        structuralChange()
    }

    // MARK: - Abhaken

    @discardableResult
    public func toggleCompletion(_ id: UUID, on day: DateKey) -> Bool {
        let now = state.completions.toggle(id, on: day)
        cache.invalidate(day)
        scheduleSave()
        return now
    }

    // MARK: - Aufgaben

    public func add(task: TaskItem) {
        state.tasks.append(task)
        structuralChange()
    }

    public func update(task: TaskItem) {
        guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[index] = task
        structuralChange()
    }

    // MARK: - Verschieben

    /// Schiebt ein Vorkommen auf einen anderen Tag.
    ///
    /// Bei einer einmaligen Aufgabe wandert schlicht ihr Datum. Bei einer
    /// wiederkehrenden darf die Serie nicht mitwandern - dann faellt der alte
    /// Tag aus, und der neue bekommt eine eigene, einmalige Aufgabe mit allem,
    /// was eingetragen war. Sonst verschoebe man aus Versehen jeden Montag,
    /// obwohl man nur diesen einen meinte.
    public func move(task: TaskItem, from day: DateKey, to target: DateKey) {
        guard target != day else { return }

        // Eine verschobene Aufgabe ist nicht erledigt - sonst waere sie geblieben.
        state.completions.setDone(task.id, on: day, false)

        if task.recurrence == .none {
            var moved = task
            moved.startDate = target
            update(task: moved)
            return
        }

        var series = task
        series.skippedDates.insert(day)
        update(task: series)

        var copy = task
        copy.id = UUID()
        copy.startDate = target
        copy.recurrence = .none
        copy.weekdays = []
        copy.months = []
        copy.skippedDates = []
        add(task: copy)
    }

    /// Setzt eine Aufgabe an die Stelle einer anderen.
    ///
    /// Nach unten gezogen landet sie hinter dem Ziel, nach oben davor - so, wie
    /// man es beim Ziehen erwartet.
    public func placeTask(_ dragged: UUID, at target: UUID) {
        guard dragged != target,
              let from = state.tasks.firstIndex(where: { $0.id == dragged }),
              let to = state.tasks.firstIndex(where: { $0.id == target })
        else { return }

        let item = state.tasks.remove(at: from)
        state.tasks.insert(item, at: min(to, state.tasks.count))
        structuralChange()
    }

    // MARK: - Ereignisse

    public func add(event: EventItem) {
        state.events.append(event)
        structuralChange()
    }

    public func update(event: EventItem) {
        guard let index = state.events.firstIndex(where: { $0.id == event.id }) else { return }
        state.events[index] = event
        structuralChange()
    }

    // MARK: - Gewohnheiten

    public func add(habit: HabitItem) {
        state.habits.append(habit)
        structuralChange()
    }

    public func update(habit: HabitItem) {
        guard let index = state.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        state.habits[index] = habit
        structuralChange()
    }

    // MARK: - Loeschen und Wiederherstellen

    public func delete(taskID: UUID) -> DeletedItem? {
        guard let index = state.tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        let item = state.tasks.remove(at: index)
        let completions = state.completions[taskID]
        state.completions.remove(taskID)
        structuralChange()
        return DeletedItem(kind: .task(item), index: index, completions: completions)
    }

    public func delete(eventID: UUID) -> DeletedItem? {
        guard let index = state.events.firstIndex(where: { $0.id == eventID }) else { return nil }
        let item = state.events.remove(at: index)
        let completions = state.completions[eventID]
        state.completions.remove(eventID)
        structuralChange()
        return DeletedItem(kind: .event(item), index: index, completions: completions)
    }

    public func delete(habitID: UUID) -> DeletedItem? {
        guard let index = state.habits.firstIndex(where: { $0.id == habitID }) else { return nil }
        let item = state.habits.remove(at: index)
        let completions = state.completions[habitID]
        state.completions.remove(habitID)
        structuralChange()
        return DeletedItem(kind: .habit(item), index: index, completions: completions)
    }

    public func delete(courseID: UUID) -> DeletedItem? {
        guard let index = state.courses.firstIndex(where: { $0.id == courseID }) else { return nil }
        let item = state.courses.remove(at: index)
        structuralChange()
        // Kurse werden nicht abgehakt, es gibt also keine Markierungen zu retten.
        return DeletedItem(kind: .course(item), index: index, completions: [])
    }

    /// Stellt einen geloeschten Eintrag an seiner alten Stelle wieder her.
    public func restore(_ deleted: DeletedItem) {
        switch deleted.kind {
        case .task(let item):
            state.tasks.insert(item, at: min(deleted.index, state.tasks.count))
            state.completions[item.id] = deleted.completions
        case .event(let item):
            state.events.insert(item, at: min(deleted.index, state.events.count))
            state.completions[item.id] = deleted.completions
        case .habit(let item):
            state.habits.insert(item, at: min(deleted.index, state.habits.count))
            state.completions[item.id] = deleted.completions
        case .course(let item):
            state.courses.insert(item, at: min(deleted.index, state.courses.count))
        }
        structuralChange()
    }

    // MARK: - Notizen

    /// Notizen aendern sich beim Tippen staendig - deshalb nur entprellt
    /// speichern und den Zwischenspeicher gar nicht erst anfassen: Sie fliessen
    /// in keine Auswertung ein.
    public func setNotes(_ text: String) {
        guard state.notes != text else { return }
        state.notes = text
        scheduleSave()
    }

    // MARK: - Urlaub (Spezifikation 4.14)

    public var isOnVacation: Bool { state.vacation.isActive }

    public func startVacation() {
        guard !state.vacation.isActive else { return }
        state.vacation = VacationState(isActive: true, since: today)
        structuralChange()
    }

    /// Beendet den Urlaub und haelt den Zeitraum fest, damit die Streak ihn auch
    /// spaeter noch ueberspringt.
    public func endVacation() {
        guard state.vacation.isActive, let since = state.vacation.since else { return }
        state.vacationRanges = (state.vacationRanges + [VacationRange(start: since, end: today)])
            .normalized()
        state.vacation = VacationState()
        structuralChange()
    }

    /// Nimmt einen einzelnen Tag aus dem Urlaub heraus.
    ///
    /// Ein versehentlich eingeschalteter Urlaub laesst sonst einen Tag
    /// zurueck, an dem alles Wiederkehrende fehlt - ohne sichtbaren Grund.
    public func clearVacation(on day: DateKey) {
        if state.vacation.isActive, let since = state.vacation.since, day >= since {
            // Laufender Urlaub: Er endet am Tag davor.
            if day == since {
                state.vacation = VacationState()
            } else {
                state.vacationRanges = (state.vacationRanges
                    + [VacationRange(start: since, end: day.adding(days: -1))]).normalized()
                state.vacation = VacationState()
            }
        }
        state.vacationRanges = state.vacationRanges.removing(day).normalized()
        structuralChange()
    }

    // MARK: - Sichern und Zurueckspielen

    /// 20 MB - weit ueber allem, was ein jahrelang gefuehrter Planer erreicht.
    static let importSizeLimit = 20 * 1024 * 1024

    public enum ImportError: LocalizedError, Equatable {
        case fileTooLarge
        case notABackup
        case newerVersion

        public var errorDescription: String? {
            switch self {
            case .fileTooLarge: "Die Datei ist zu groß, um eine Planer-Sicherung zu sein."
            case .notABackup: "Das ist keine Planer-Sicherung."
            case .newerVersion: "Die Sicherung stammt aus einer neueren Fassung des Planers."
            }
        }
    }

    /// Nur die Kopfdaten einer Datei - um vor dem Import festzustellen, ob sie
    /// ueberhaupt eine Planer-Sicherung ist.
    ///
    /// `StoredDocument` selbst ist bewusst nachsichtig und macht aus jedem
    /// JSON-Objekt einen leeren Planer. Beim Laden der eigenen Datei ist das
    /// richtig, beim Import wuerde es den Bestand durch nichts ersetzen.
    private struct ImportHeader: Decodable {
        let hasState: Bool
        let schemaVersion: Int

        private enum CodingKeys: String, CodingKey { case schemaVersion, state }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hasState = c.contains(.state)
            schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        }
    }

    /// Der Ordner mit Datendatei und Sicherungen.
    public var storageDirectory: URL { location.directory }

    /// Schreibt den aktuellen Stand als lesbares JSON an einen frei gewaehlten
    /// Ort - unabhaengig von der laufenden Datei.
    public func export(to url: URL) throws {
        let data = try StoredDocument.encoder.encode(StoredDocument(state: state))
        try data.write(to: url, options: [.atomic])
        // Auch die Kopie enthaelt alles - sie soll nicht offener sein als das
        // Original, egal wohin sie gelegt wird.
        StoreLocation.restrictToOwner(url)
    }

    /// Ersetzt den gesamten Bestand durch eine gesicherte Datei.
    ///
    /// Vorher wird der bisherige Stand als Sicherung weggeschrieben - ein Import
    /// aus Versehen soll nicht das Ende von allem sein.
    public func importFrom(_ url: URL) throws {
        // Eine Planerdatei ist ein paar hundert Kilobyte gross. Was um
        // Groessenordnungen darueber liegt, ist keine - und soll nicht erst in
        // den Speicher geladen werden, um das festzustellen.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= Self.importSizeLimit else { throw ImportError.fileTooLarge }

        let data = try Data(contentsOf: url)

        guard let header = try? StoredDocument.decoder.decode(ImportHeader.self, from: data),
              header.hasState
        else { throw ImportError.notABackup }
        guard header.schemaVersion <= StoredDocument.currentSchemaVersion else {
            throw ImportError.newerVersion
        }

        let document = try StoredDocument.decoder.decode(StoredDocument.self, from: data)

        flush()
        try? backups.makeDailyBackup()

        state = document.state
        cache.invalidateAll()
        persistNow()
    }

    // MARK: - Intern

    /// Aenderung am Bestand: Ein wiederkehrender Eintrag beruehrt beliebig viele
    /// Tage, deshalb wird der gesamte Zwischenspeicher verworfen.
    private func structuralChange() {
        cache.invalidateAll()
        scheduleSave()
    }
}
