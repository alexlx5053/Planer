import Foundation
import PlanerCore
import PlanerData
import Observation

/// Was gerade im Bearbeiten-Blatt steht.
enum EditorTarget: Identifiable, Hashable {
    case newTask(DateKey)
    case newEvent(DateKey)
    /// Ein neuer Termin mit vorgegebener Uhrzeit - aus dem Stundenplan heraus
    /// in eine freie Luecke geklickt.
    case newEventAt(DateKey, ClockTime)
    case newHabit
    /// Ein neuer Kurs, vorbelegt mit Tag und Uhrzeit der angeklickten Stelle.
    case newCourse(weekday: Int, start: ClockTime)
    case task(TaskItem)
    case event(EventItem)
    case habit(HabitItem)
    case course(CourseItem)

    var id: String {
        switch self {
        case .newTask(let day): "neu-aufgabe-\(day.rawValue)"
        case .newEvent(let day): "neu-ereignis-\(day.rawValue)"
        case .newEventAt(let day, let time): "neu-ereignis-\(day.rawValue)-\(time.text)"
        case .newHabit: "neu-gewohnheit"
        case .newCourse(let weekday, let start): "neu-kurs-\(weekday)-\(start.text)"
        case .task(let item): "aufgabe-\(item.id.uuidString)"
        case .event(let item): "ereignis-\(item.id.uuidString)"
        case .habit(let item): "gewohnheit-\(item.id.uuidString)"
        case .course(let item): "kurs-\(item.id.uuidString)"
        }
    }

    /// Gehoert dieses Ziel ins Kursblatt statt ins allgemeine Bearbeiten-Blatt?
    var isCourse: Bool {
        switch self {
        case .newCourse, .course: true
        default: false
        }
    }
}

/// Welche Art Eintrag zuletzt angelegt wurde.
///
/// Das „＋" oeffnet beim naechsten Mal dieselbe Art. Wer eine Woche lang Termine
/// eintraegt, will beim naechsten Klick wieder einen Termin - und nicht jedes
/// Mal umschalten.
enum NewEntryKind: String, CaseIterable {
    case event, task, habit, course

    var label: String {
        switch self {
        case .event: "Termin"
        case .task: "Aufgabe"
        case .habit: "Gewohnheit"
        case .course: "Kurs"
        }
    }

    var symbol: String {
        switch self {
        case .event: "calendar"
        case .task: "checklist"
        case .habit: "repeat"
        case .course: "graduationcap"
        }
    }

    /// Die Arten, die das allgemeine Bearbeiten-Blatt umschalten kann.
    static let sheetKinds: [NewEntryKind] = [.event, .task, .habit]
}

/// Tag oder Woche.
enum ViewMode: String, CaseIterable {
    case day, week, timetable

    var label: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .timetable: "Stundenplan"
        }
    }

    /// Ansichten, die eine ganze Woche zeigen - die Pfeile springen dort
    /// wochenweise.
    var showsWholeWeek: Bool { self != .day }
}

/// Ein geloeschter Eintrag, der noch zurueckgeholt werden kann.
struct PendingUndo: Identifiable {
    let id = UUID()
    let deleted: DeletedItem
}

/// Eben aus Text angelegte Eintraege - solange der Hinweis steht, lassen sie
/// sich in einem Zug zuruecknehmen.
struct CreatedNotice: Identifiable {
    let id = UUID()
    let eventIDs: [UUID]
    let taskIDs: [UUID]

    var count: Int { eventIDs.count + taskIDs.count }
}

/// Der Zustand der Oberflaeche: welcher Tag, welcher Monat, welches Blatt offen.
///
/// Getrennt vom `StateStore`, der die Daten haelt - was gerade angezeigt wird,
/// gehoert nicht in die gespeicherte Datei.
@MainActor
@Observable
final class AppModel {
    let store: StateStore

    var selectedDate: DateKey {
        didSet { visibleMonth = selectedDate }
    }

    /// Der im Kalender sichtbare Monat. Folgt der Auswahl, laesst sich aber
    /// unabhaengig davon blaettern.
    var visibleMonth: DateKey

    var editorTarget: EditorTarget?
    var pendingUndo: PendingUndo?
    var lastNewKind: NewEntryKind = .event

    var viewMode: ViewMode = .day

    /// Monatsuebersicht als Blatt ueber der Tagesansicht.
    var showsMonthOverview = false

    /// Die Liste aller anstehenden Termine.
    var showsUpcoming = false

    /// Die Notizen in gross.
    var showsNotes = false

    /// „Aus Text anlegen".
    var showsCapture = false

    /// Der dort eingefuegte Text.
    ///
    /// Hier und nicht in der Ansicht: Wer versehentlich daneben klickt, soll
    /// beim Wiederoeffnen nicht vor einem leeren Feld stehen.
    var captureText = ""

    var createdNotice: CreatedNotice?

    /// Wird gerade im kleinen Notizfeld der Seitenspalte geschrieben?
    ///
    /// Hier statt in der Ansicht, weil ein Klick irgendwo ins Fenster das
    /// Schreiben beenden soll - und das Fenster die Seitenspalte nicht kennt.
    var isEditingNotes = false

    /// Liegt gerade ein Blatt ueber dem Fenster?
    ///
    /// Dann sind die Menuebefehle fuer neue Eintraege gesperrt. Das Fenster
    /// kann kein zweites Blatt zeigen; der Wunsch wuerde vorgemerkt und das
    /// Bearbeiten-Blatt spraenge spaeter unvermittelt auf.
    /// Wird hochgezaehlt, wenn neben ein Bearbeiten-Blatt geklickt wurde.
    ///
    /// Das Blatt entscheidet selbst, was das heisst - nur es kennt seinen
    /// Entwurf: unveraendert schliessen, geaendert uebernehmen.
    var editorCloseRequest = 0

    var isPresentingSheet: Bool {
        editorTarget != nil || showsMonthOverview || showsUpcoming || showsNotes || showsCapture
    }

    /// Suchbegriff. Filtert nur die Listen des angezeigten Tages - eine Suche
    /// ueber den gesamten Bestand waere eine eigene Ansicht.
    var searchText = ""
    var isSearchFieldVisible = false

    /// Aktuelle Uhrzeit fuer die Kopfzeile, im Minutentakt nachgefuehrt.
    var now = Date()

    @ObservationIgnored private var undoTimer: Task<Void, Never>?
    @ObservationIgnored private var noticeTimer: Task<Void, Never>?

    init(store: StateStore) {
        self.store = store
        let today = store.today
        self.selectedDate = today
        self.visibleMonth = today
    }

    // MARK: - Navigation

    var isToday: Bool { selectedDate == store.today }

    func goToToday() {
        selectedDate = store.today
    }

    /// In der Wochenansicht springt der Pfeil eine ganze Woche weiter - alles
    /// andere waere ein Sprung, den man in der Anzeige nicht sieht.
    func step(days: Int) {
        selectedDate = selectedDate.adding(days: viewMode.showsWholeWeek ? days * 7 : days)
    }

    func stepMonth(_ months: Int) {
        visibleMonth = visibleMonth.adding(months: months)
    }

    // MARK: - Uhrzeit und Tageswechsel

    /// Wird im Minutentakt aufgerufen. Faellt dabei ein Datumswechsel an, zieht
    /// die ganze Auswertung mit - sonst zeigte die App nach Mitternacht noch
    /// den Vortag als „heute".
    func tick(_ date: Date = Date()) {
        now = date
        let currentDay = DateKey(date)
        guard currentDay != store.today else { return }

        let wasOnToday = selectedDate == store.today
        store.today = currentDay
        if wasOnToday { selectedDate = currentDay }
    }

    /// Tageszeit-Gruss nach Spezifikation 4.1.
    var greeting: String {
        switch ldCalendar.component(.hour, from: now) {
        case 5..<11: "Guten Morgen"
        case 11..<18: "Guten Tag"
        case 18..<23: "Guten Abend"
        default: "Gute Nacht"
        }
    }

    // MARK: - Bearbeiten

    /// Legt einen Eintrag der zuletzt benutzten Art an.
    func newEntry() {
        newEntry(kind: lastNewKind)
    }

    func newEntry(kind: NewEntryKind) {
        lastNewKind = kind
        switch kind {
        case .event: editorTarget = .newEvent(selectedDate)
        case .task: editorTarget = .newTask(selectedDate)
        case .habit: editorTarget = .newHabit
        case .course: newCourse()
        }
    }

    func edit(task: TaskItem) { editorTarget = .task(task) }
    func edit(event: EventItem) { editorTarget = .event(event) }
    func edit(habit: HabitItem) { editorTarget = .habit(habit) }
    func edit(course: CourseItem) { editorTarget = .course(course) }

    // MARK: - Stundenplan

    /// Ein neuer Kurs. Ohne Angabe am angezeigten Tag und zur naechsten
    /// Vorlesungszeit - wer aus dem Raster heraus klickt, bringt beides mit.
    func newCourse(weekday: Int? = nil, start: ClockTime? = nil) {
        lastNewKind = .course
        let day = weekday ?? (selectedDate.isWeekend ? 1 : selectedDate.weekdayIndex)
        editorTarget = .newCourse(weekday: day, start: start ?? ClockTime(hour: 10))
    }

    /// Ein neuer Termin in einer angeklickten Luecke des Stundenplans.
    func newEvent(on day: DateKey, at time: ClockTime) {
        lastNewKind = .event
        editorTarget = .newEventAt(day, time)
    }

    func save(course: CourseItem, isNew: Bool) {
        if isNew { store.add(course: course) } else { store.update(course: course) }
        editorTarget = nil
    }

    func delete(course: CourseItem) { offerUndo(store.delete(courseID: course.id)) }

    /// Eine einzelne Sitzung faellt aus - der Kurs bleibt.
    func cancelSession(_ course: CourseItem, on day: DateKey) {
        store.cancelSession(courseID: course.id, on: day)
    }

    func restoreSession(_ course: CourseItem, on day: DateKey) {
        store.restoreSession(courseID: course.id, on: day)
    }

    var hasCourses: Bool { store.hasCourses }

    // MARK: - Verschieben

    /// Schiebt eine Aufgabe vom angezeigten Tag um `days` Tage weiter.
    func move(task: TaskItem, by days: Int) {
        store.move(task: task, from: selectedDate, to: selectedDate.adding(days: days))
    }

    func move(task: TaskItem, to target: DateKey) {
        store.move(task: task, from: selectedDate, to: target)
    }

    /// Ziel einer Ziehbewegung: Die gezogene Aufgabe nimmt den Platz der
    /// anderen ein.
    func place(draggedTaskID raw: String, at target: TaskItem) {
        guard let dragged = UUID(uuidString: raw) else { return }
        store.placeTask(dragged, at: target.id)
    }

    // MARK: - Verdoppeln

    /// Legt eine Kopie an - der schnellste Weg zu einem aehnlichen Eintrag.
    func duplicate(task: TaskItem) {
        var copy = task
        copy.id = UUID()
        copy.title = Self.copyTitle(task.title)
        store.add(task: copy)
        editorTarget = .task(copy)
    }

    func duplicate(event: EventItem) {
        var copy = event
        copy.id = UUID()
        copy.title = Self.copyTitle(event.title)
        store.add(event: copy)
        editorTarget = .event(copy)
    }

    private static func copyTitle(_ title: String) -> String {
        title.hasSuffix(" Kopie") ? title : "\(title) Kopie"
    }

    // MARK: - Loeschen mit Rueckholung

    func delete(task: TaskItem) { offerUndo(store.delete(taskID: task.id)) }
    func delete(event: EventItem) { offerUndo(store.delete(eventID: event.id)) }
    func delete(habit: HabitItem) { offerUndo(store.delete(habitID: habit.id)) }

    /// Zeigt den Rueckholen-Hinweis und laesst ihn nach fuenf Sekunden
    /// verschwinden. Kein Bestaetigungsdialog - Loeschen ist sofort, aber
    /// umkehrbar (Spezifikation 4.17).
    private func offerUndo(_ deleted: DeletedItem?) {
        guard let deleted else { return }
        pendingUndo = PendingUndo(deleted: deleted)

        undoTimer?.cancel()
        let id = pendingUndo?.id
        undoTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            // Nur ausblenden, wenn inzwischen nichts Neues geloescht wurde.
            if self?.pendingUndo?.id == id { self?.pendingUndo = nil }
        }
    }

    func undoDeletion() {
        guard let pending = pendingUndo else { return }
        store.restore(pending.deleted)
        pendingUndo = nil
        undoTimer?.cancel()
    }

    func dismissUndo() {
        pendingUndo = nil
        undoTimer?.cancel()
    }

    // MARK: - Speichern aus dem Blatt

    func save(task: TaskItem, isNew: Bool) {
        if isNew { store.add(task: task) } else { store.update(task: task) }
        editorTarget = nil
    }

    func save(event: EventItem, isNew: Bool) {
        if isNew { store.add(event: event) } else { store.update(event: event) }
        editorTarget = nil
    }

    func save(habit: HabitItem, isNew: Bool) {
        if isNew { store.add(habit: habit) } else { store.update(habit: habit) }
        editorTarget = nil
    }

    // MARK: - Aus Text anlegen

    func openCapture() {
        isEditingNotes = false
        showsCapture = true
    }

    /// Legt die ausgewaehlten Entwuerfe an.
    ///
    /// Danach steht fuer einige Sekunden ein Hinweis mit „Rueckgaengig" da. Ein
    /// Leser, der aus fremdem Text Eintraege macht, kann sich irren - dann soll
    /// ein Klick genuegen, um alles wieder herauszunehmen, statt zehn Eintraege
    /// einzeln zu loeschen.
    func create(from drafts: [EntryDraft]) {
        var eventIDs: [UUID] = []
        var taskIDs: [UUID] = []
        var days: Set<DateKey> = []

        for draft in drafts where draft.isIncluded {
            guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            switch draft.kind {
            case .event:
                let event = draft.makeEvent()
                store.add(event: event)
                eventIDs.append(event.id)
            case .task:
                let task = draft.makeTask()
                store.add(task: task)
                taskIDs.append(task.id)
            }
            days.insert(draft.date)
        }

        guard !eventIDs.isEmpty || !taskIDs.isEmpty else { return }

        captureText = ""
        showsCapture = false
        // Liegt alles an einem Tag, dorthin springen: Man will sehen, was
        // entstanden ist.
        if days.count == 1, let day = days.first { selectedDate = day }

        dismissUndo()
        let notice = CreatedNotice(eventIDs: eventIDs, taskIDs: taskIDs)
        createdNotice = notice
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            if self?.createdNotice?.id == notice.id { self?.createdNotice = nil }
        }
    }

    /// Nimmt die eben angelegten Eintraege wieder heraus.
    func undoCreation() {
        guard let notice = createdNotice else { return }
        for id in notice.eventIDs { _ = store.delete(eventID: id) }
        for id in notice.taskIDs { _ = store.delete(taskID: id) }
        dismissCreatedNotice()
    }

    func dismissCreatedNotice() {
        createdNotice = nil
        noticeTimer?.cancel()
    }

    // MARK: - Suche (Spezifikation 4.22)

    func toggleSearch() {
        isSearchFieldVisible.toggle()
        if !isSearchFieldVisible { searchText = "" }
    }

    func matches(_ title: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
    }

    // MARK: - Urlaub

    var isOnVacation: Bool { store.isOnVacation }

    func toggleVacation() {
        if store.isOnVacation { store.endVacation() } else { store.startVacation() }
    }

    /// Seit wann der laufende Urlaub geht - fuer den Hinweis im Kopf.
    var vacationSince: DateKey? { store.state.vacation.since }

    /// Ist der angezeigte Tag ein Urlaubstag?
    var selectedDayIsVacation: Bool {
        store.state.isVacationDay(selectedDate, today: store.today)
    }

    func clearVacationOnSelectedDay() {
        store.clearVacation(on: selectedDate)
    }

    // MARK: - Kalendermarkierungen

    /// Der Punkt im Kalender steht fuer Termine, nicht fuer jeden Eintrag.
    ///
    /// Wuerden taegliche Aufgaben und Gewohnheiten mitzaehlen, traege jeder Tag
    /// einen Punkt - und eine Markierung, die immer da ist, sagt nichts mehr.
    func mark(for day: DateKey) -> DayMark {
        DayMark(
            hasEvents: !store.state.events(on: day, today: store.today).isEmpty,
            isPerfect: store.stats(for: day).isPerfect
        )
    }
}
