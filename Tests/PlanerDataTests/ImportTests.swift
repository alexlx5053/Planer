import Foundation
import Testing
@testable import PlanerCore
@testable import PlanerData

/// Zurueckspielen einer Sicherung: Was abgelehnt wird und was vorher gesichert wird.
@Suite("Import")
@MainActor
struct ImportTests {

    private let today = DateKey(year: 2026, month: 11, day: 11)

    private func temporaryLocation() throws -> StoreLocation {
        let location = StoreLocation(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("planer-import-\(UUID().uuidString)"))
        try location.ensureDirectories()
        return location
    }

    private func file(_ raw: String, in location: StoreLocation, named name: String = "fremd.json") throws -> URL {
        let url = location.directory.appendingPathComponent(name)
        try Data(raw.utf8).write(to: url)
        return url
    }

    // MARK: - Fremde Dateien

    @Test("Fremdes JSON wird abgelehnt", arguments: [
        "{}",
        #"{"name":"x"}"#,
        #"{"state":null}"#,
        #"{"schemaVersion":1,"state":null}"#,
    ])
    func foreignJSONIsRejected(raw: String) throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = StateStore(location: location, today: today)
        store.add(task: TaskItem(title: "Bleibt", startDate: today))
        store.flush()

        let foreign = try file(raw, in: location)
        #expect(throws: StateStore.ImportError.notABackup) { try store.importFrom(foreign) }

        #expect(store.state.tasks.map(\.title) == ["Bleibt"])
        let reloaded = StateStore(location: location, today: today)
        #expect(reloaded.state.tasks.map(\.title) == ["Bleibt"])
    }

    /// Eine Datei aus einer neueren App-Fassung koennte Felder enthalten, die
    /// hier verloren gingen.
    @Test func newerSchemaIsRejected() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = StateStore(location: location, today: today)
        store.add(task: TaskItem(title: "Bleibt", startDate: today))

        let newer = try file(
            #"{"schemaVersion": \#(StoredDocument.currentSchemaVersion + 1), "state": {}}"#,
            in: location
        )
        #expect(throws: StateStore.ImportError.newerVersion) { try store.importFrom(newer) }
        #expect(store.state.tasks.map(\.title) == ["Bleibt"])
    }

    /// Eine eigene Sicherung geht weiterhin durch.
    @Test func ownExportIsImported() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let source = StateStore(location: location, today: today)
        source.add(task: TaskItem(title: "Aus der Sicherung", startDate: today))
        let export = location.directory.appendingPathComponent("export.json")
        try source.export(to: export)

        let target = StateStore(inMemory: DashboardState(), today: today)
        try target.importFrom(export)
        #expect(target.state.tasks.map(\.title) == ["Aus der Sicherung"])
    }

    /// Das normale Laden bleibt nachsichtig: Eine eigene Datei ohne "state"
    /// ergibt weiterhin einen leeren Planer statt eines Fehlers.
    @Test func loadingStaysTolerant() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try Data("{}".utf8).write(to: location.file)

        let store = StateStore(location: location, today: today)
        #expect(store.loadOutcome == .ok)
        #expect(store.state == DashboardState())
    }

    // MARK: - Sicherung vor dem Import

    /// Alle Sicherungsdateien samt Inhalt.
    private func backupContents(_ location: StoreLocation) throws -> [(URL, StoredDocument)] {
        try FileManager.default
            .contentsOfDirectory(at: location.backupDirectory, includingPropertiesForKeys: nil)
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let document = try? StoredDocument.decoder.decode(StoredDocument.self, from: data)
                else { return nil }
                return (url, document)
            }
    }

    /// Die Tagessicherung gibt es heute schon. Was danach geaendert wurde, muss
    /// trotzdem in einer Kopie vor dem Import landen.
    @Test func changesSinceTheDailyBackupAreSavedBeforeImport() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        let first = StateStore(location: location, today: today)
        first.add(task: TaskItem(title: "Vor dem Start", startDate: today))
        first.flush()

        // Zweiter Start: legt die heutige Tagessicherung an.
        let store = StateStore(location: location, today: today)
        #expect(BackupService(location: location).availableBackups().count == 1)

        store.add(task: TaskItem(title: "Nach dem Start", startDate: today))

        let other = StateStore(inMemory: DashboardState(), today: today)
        other.add(task: TaskItem(title: "Importiert", startDate: today))
        let export = location.directory.appendingPathComponent("export.json")
        try other.export(to: export)

        try store.importFrom(export)
        #expect(store.state.tasks.map(\.title) == ["Importiert"])

        let saved = try backupContents(location).filter { _, document in
            document.state.tasks.map(\.title).contains("Nach dem Start")
        }
        #expect(saved.count == 1)
        if let (url, _) = saved.first {
            #expect(url.lastPathComponent.hasPrefix("dashboard-vor-import-"))
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }
}
