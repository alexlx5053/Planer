import Foundation
import Testing
@testable import PlanerCore
@testable import PlanerData

/// Laden, Speichern, Sicherungen und Wiederherstellung.
@Suite("Speicher")
@MainActor
struct StateStoreTests {

    private func day(_ raw: String) -> DateKey { DateKey(raw)! }

    /// Jeder Test bekommt ein eigenes, leeres Verzeichnis.
    private func makeLocation() throws -> StoreLocation {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LD-Test-\(UUID().uuidString)", isDirectory: true)
        let location = StoreLocation(directory: directory)
        try location.ensureDirectories()
        return location
    }

    private func write(_ raw: String, to location: StoreLocation) throws {
        try Data(raw.utf8).write(to: location.file)
    }

    // MARK: - Rundlauf

    @Test func savesAndReloads() throws {
        let location = try makeLocation()

        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(task: TaskItem(title: "Lesen", startDate: day("2026-09-04"), recurrence: .daily))
        store.toggleCompletion(store.state.tasks[0].id, on: day("2026-09-04"))
        store.flush()

        let reloaded = StateStore(location: location, today: day("2026-09-04"))
        #expect(reloaded.state.tasks.map(\.title) == ["Lesen"])
        #expect(reloaded.isDone(reloaded.state.tasks[0].id, on: day("2026-09-04")))
        #expect(reloaded.loadOutcome == .ok)
    }

    @Test func startsEmptyWhenNoFileExists() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))

        #expect(store.state == DashboardState())
        #expect(store.loadOutcome == .ok)
    }

    /// Ohne Aenderung darf `flush` keine Datei anlegen - sonst entstuende beim
    /// blossen Oeffnen der App eine Datei, die es vorher nicht gab.
    @Test func flushWithoutChangesWritesNothing() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))

        store.flush()
        #expect(!FileManager.default.fileExists(atPath: location.file.path))
    }

    /// Das entprellte Speichern muss ohne ausdrueckliches `flush` greifen.
    @Test func debouncedSaveWritesOnItsOwn() async throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(habit: HabitItem(title: "Wasser", startDate: day("2026-08-01")))

        try await Task.sleep(for: .milliseconds(600))

        let reloaded = StateStore(location: location, today: day("2026-09-04"))
        #expect(reloaded.state.habits.map(\.title) == ["Wasser"])
    }

    // MARK: - Beschaedigte Datei

    @Test func recoversFromBackupWhenFileIsUnreadable() throws {
        let location = try makeLocation()

        // Erst einen gueltigen Stand erzeugen und sichern lassen.
        let first = StateStore(location: location, today: day("2026-09-04"))
        first.add(task: TaskItem(title: "Wichtig", startDate: day("2026-09-04")))
        first.flush()
        try BackupService(location: location).makeDailyBackup()

        try write("{ das ist kein JSON", to: location)

        let recovered = StateStore(location: location, today: day("2026-09-04"))

        #expect(recovered.state.tasks.map(\.title) == ["Wichtig"])
        if case .recoveredFromBackup = recovered.loadOutcome {} else {
            Issue.record("Erwartet wurde eine Wiederherstellung, war: \(recovered.loadOutcome)")
        }
    }

    /// Nach der Wiederherstellung liegt sofort wieder eine gueltige Datei
    /// bereit - der naechste Start soll regulaer laufen.
    @Test func recoveryRewritesTheMainFile() throws {
        let location = try makeLocation()
        let first = StateStore(location: location, today: day("2026-09-04"))
        first.add(task: TaskItem(title: "Wichtig", startDate: day("2026-09-04")))
        first.flush()
        try BackupService(location: location).makeDailyBackup()
        try write("kaputt", to: location)

        _ = StateStore(location: location, today: day("2026-09-04"))
        let third = StateStore(location: location, today: day("2026-09-04"))

        #expect(third.loadOutcome == .ok)
        #expect(third.state.tasks.map(\.title) == ["Wichtig"])
    }

    /// Eine unlesbare Datei wird beiseitegelegt, nie ueberschrieben.
    @Test func corruptFileIsQuarantinedNotDiscarded() throws {
        let location = try makeLocation()
        try write("voellig kaputt", to: location)

        let store = StateStore(location: location, today: day("2026-09-04"))

        guard case .startedEmpty(let quarantined) = store.loadOutcome else {
            Issue.record("Erwartet wurde ein leerer Start, war: \(store.loadOutcome)")
            return
        }
        #expect(quarantined != nil)

        let files = try FileManager.default.contentsOfDirectory(atPath: location.directory.path)
        let kept = files.first { $0.hasPrefix("dashboard-beschaedigt-") }
        #expect(kept != nil, "Die beschaedigte Datei muss erhalten bleiben")

        let content = try String(contentsOf: location.directory.appendingPathComponent(kept ?? ""),
                                 encoding: .utf8)
        #expect(content == "voellig kaputt")
    }

    // MARK: - Loeschen und Wiederherstellen

    @Test func deleteAndRestoreKeepsCompletionsAndPosition() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(task: TaskItem(title: "Erste", startDate: day("2026-09-04")))
        store.add(task: TaskItem(title: "Zweite", startDate: day("2026-09-04"), recurrence: .daily))
        store.add(task: TaskItem(title: "Dritte", startDate: day("2026-09-04")))

        let middle = store.state.tasks[1]
        store.toggleCompletion(middle.id, on: day("2026-09-02"))
        store.toggleCompletion(middle.id, on: day("2026-09-03"))

        let deleted = try #require(store.delete(taskID: middle.id))
        #expect(store.state.tasks.map(\.title) == ["Erste", "Dritte"])
        #expect(!store.isDone(middle.id, on: day("2026-09-02")))

        store.restore(deleted)
        #expect(store.state.tasks.map(\.title) == ["Erste", "Zweite", "Dritte"],
                "Der Eintrag muss an seine alte Stelle zurueck")
        #expect(store.isDone(middle.id, on: day("2026-09-02")))
        #expect(store.isDone(middle.id, on: day("2026-09-03")))
    }

    @Test func deletingUnknownItemDoesNothing() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        #expect(store.delete(taskID: UUID()) == nil)
    }

    // MARK: - Umbenennung der App

    /// Beim Umbenennen von „Lebens-Dashboard" zu „Planer" darf kein Eintrag
    /// verloren gehen: Der alte Ordner wird unter dem neuen Namen weitergefuehrt.
    @Test func adoptsFolderOfThePreviousAppName() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LD-Umzug-\(UUID().uuidString)", isDirectory: true)
        let old = base.appendingPathComponent("Lebens-Dashboard", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)

        let oldLocation = StoreLocation(directory: old)
        let before = StateStore(location: oldLocation, today: day("2026-09-04"))
        before.add(habit: HabitItem(title: "Wasser", startDate: day("2026-08-01")))
        before.flush()

        let adopted = StoreLocation.adopting(previousName: "Lebens-Dashboard",
                                             newName: "Planer", in: base)
        let after = StateStore(location: adopted, today: day("2026-09-04"))

        #expect(after.state.habits.map(\.title) == ["Wasser"])
        #expect(!FileManager.default.fileExists(atPath: old.path),
                "Der alte Ordner darf nicht zurueckbleiben")
    }

    /// Gegenprobe: Ein bereits begonnener neuer Bestand darf nicht ueberschrieben
    /// werden.
    @Test func keepsExistingDataWhenBothFoldersExist() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LD-Umzug-\(UUID().uuidString)", isDirectory: true)
        let old = StoreLocation(directory: base.appendingPathComponent("Lebens-Dashboard"))
        let new = StoreLocation(directory: base.appendingPathComponent("Planer"))
        try old.ensureDirectories()
        try new.ensureDirectories()

        let alt = StateStore(location: old, today: day("2026-09-04"))
        alt.add(habit: HabitItem(title: "Alt", startDate: day("2026-08-01")))
        alt.flush()

        let neu = StateStore(location: new, today: day("2026-09-04"))
        neu.add(habit: HabitItem(title: "Neu", startDate: day("2026-08-01")))
        neu.flush()

        let adopted = StoreLocation.adopting(previousName: "Lebens-Dashboard",
                                             newName: "Planer", in: base)
        let reopened = StateStore(location: adopted, today: day("2026-09-04"))

        #expect(reopened.state.habits.map(\.title) == ["Neu"])
    }

    // MARK: - Zwischenspeicher

    /// Beim Abhaken rutscht Erledigtes nach unten - der zwischengespeicherte
    /// Tagesinhalt muss diese neue Reihenfolge zeigen, nicht die alte.
    @Test func cachedAgendaFollowsTheNewOrderAfterToggling() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(event: EventItem(title: "Früh", startDate: day("2026-09-04"), time: "08:00"))
        store.add(event: EventItem(title: "Spät", startDate: day("2026-09-04"), time: "18:00"))

        #expect(store.agenda(for: day("2026-09-04")).events.map(\.title) == ["Früh", "Spät"])

        let early = store.state.events[0].id
        store.toggleCompletion(early, on: day("2026-09-04"))

        #expect(store.agenda(for: day("2026-09-04")).events.map(\.title) == ["Spät", "Früh"],
                "Erledigtes gehoert nach unten")
    }

    /// Was abgehakt wurde, faellt aus der Terminvorschau heraus.
    @Test func upcomingEventsFollowCompletions() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(event: EventItem(title: "Zahnarzt", startDate: day("2026-09-04")))
        store.add(event: EventItem(title: "Später", startDate: day("2026-09-10")))

        #expect(store.upcomingEvents().map(\.event.title) == ["Zahnarzt", "Später"])

        store.toggleCompletion(store.state.events[0].id, on: day("2026-09-04"))
        #expect(store.upcomingEvents().map(\.event.title) == ["Später"])
    }

    /// Ein neuer Termin muss sofort in der Vorschau auftauchen.
    @Test func upcomingEventsFollowNewEntries() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        #expect(store.upcomingEvents().isEmpty)

        store.add(event: EventItem(title: "Neu", startDate: day("2026-09-05")))
        #expect(store.upcomingEvents().map(\.event.title) == ["Neu"])
    }


    /// Der Zwischenspeicher darf nie einen veralteten Wert liefern.
    @Test func statsFollowCompletionChanges() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(task: TaskItem(title: "Lesen", startDate: day("2026-09-04")))
        let id = store.state.tasks[0].id

        #expect(store.stats(for: day("2026-09-04")).percent == 0)

        store.toggleCompletion(id, on: day("2026-09-04"))
        #expect(store.stats(for: day("2026-09-04")).percent == 100)

        store.toggleCompletion(id, on: day("2026-09-04"))
        #expect(store.stats(for: day("2026-09-04")).percent == 0)
    }

    /// Ein wiederkehrender Eintrag beruehrt viele Tage - nach einer Aenderung am
    /// Eintrag muessen alle zwischengespeicherten Tage neu gerechnet werden.
    @Test func structuralChangesInvalidateEveryCachedDay() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))

        #expect(store.stats(for: day("2026-09-03")).total == 0)
        #expect(store.stats(for: day("2026-09-04")).total == 0)

        store.add(task: TaskItem(title: "Lesen", startDate: day("2026-09-01"), recurrence: .daily))

        #expect(store.stats(for: day("2026-09-03")).total == 1)
        #expect(store.stats(for: day("2026-09-04")).total == 1)
    }

    @Test func streakFollowsChanges() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(task: TaskItem(title: "Lesen", startDate: day("2026-09-01"), recurrence: .daily))
        let id = store.state.tasks[0].id

        #expect(store.streak == 0)

        store.toggleCompletion(id, on: day("2026-09-03"))
        store.toggleCompletion(id, on: day("2026-09-04"))
        #expect(store.streak == 2)
    }

    /// Der Tageswechsel um Mitternacht muss die Auswertung mitnehmen.
    @Test func changingTodayRefreshesStats() throws {
        let location = try makeLocation()
        let store = StateStore(location: location, today: day("2026-09-04"))
        store.add(task: TaskItem(title: "Lesen", startDate: day("2026-09-01"), recurrence: .daily))
        let id = store.state.tasks[0].id
        store.toggleCompletion(id, on: day("2026-09-04"))

        #expect(store.streak == 1)

        store.today = day("2026-09-05")
        #expect(store.streak == 1, "Gestern war perfekt, heute noch offen")
    }
}

/// Wer die Datendateien lesen darf.
@Suite("Zugriffsrechte")
@MainActor
struct FilePermissionTests {

    private let today = DateKey(year: 2026, month: 11, day: 11)

    private func temporaryLocation() -> StoreLocation {
        StoreLocation(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("planer-rechte-\(UUID().uuidString)"))
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func dataFileIsReadableByTheOwnerOnly() {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let store = StateStore(location: location, today: today)
        store.add(task: TaskItem(title: "Geheim", startDate: today))
        store.flush()

        #expect(permissions(location.file) == 0o600)
        #expect(permissions(location.directory) == 0o700)
        #expect(permissions(location.backupDirectory) == 0o700)
    }

    /// Atomares Schreiben ersetzt die Datei - die Rechte muessen danach wieder
    /// stimmen, nicht nur beim ersten Mal.
    @Test func permissionsSurviveRepeatedSaving() {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let store = StateStore(location: location, today: today)
        for index in 1...3 {
            store.add(task: TaskItem(title: "Aufgabe \(index)", startDate: today))
            store.flush()
        }
        #expect(permissions(location.file) == 0o600)
    }

    /// Dateien, die eine aeltere Fassung der App offen angelegt hat, werden
    /// beim Start nachgezogen.
    @Test func olderFilesAreTightenedOnLaunch() throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let first = StateStore(location: location, today: today)
        first.add(task: TaskItem(title: "Alt", startDate: today))
        first.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: location.file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: location.directory.path)

        _ = StateStore(location: location, today: today)

        #expect(permissions(location.file) == 0o600)
        #expect(permissions(location.directory) == 0o700)
    }

    @Test func backupsAndExportsAreProtectedToo() throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let store = StateStore(location: location, today: today)
        store.add(task: TaskItem(title: "Geheim", startDate: today))
        store.flush()

        // Ein zweiter Start legt die Tagessicherung an.
        let second = StateStore(location: location, today: today)
        let backups = BackupService(location: location).availableBackups()
        #expect(!backups.isEmpty)
        #expect(backups.allSatisfy { permissions($0) == 0o600 })

        let export = location.directory.appendingPathComponent("export.json")
        try second.export(to: export)
        #expect(permissions(export) == 0o600)
    }

    @Test func oversizedFilesAreNotImported() throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = StateStore(location: location, today: today)
        store.add(task: TaskItem(title: "Bleibt", startDate: today))

        let huge = location.directory.appendingPathComponent("riesig.json")
        try Data(count: StateStore.importSizeLimit + 1).write(to: huge)

        #expect(throws: StateStore.ImportError.self) { try store.importFrom(huge) }
        // Der Bestand ist unberuehrt.
        #expect(store.state.tasks.map(\.title) == ["Bleibt"])
    }
}
