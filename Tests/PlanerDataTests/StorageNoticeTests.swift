import Foundation
import Testing
@testable import PlanerCore
@testable import PlanerData

/// Was beim Laden oder Speichern schiefging, muss sich der Oberflaeche
/// mitteilen lassen - und ein gescheitertes Speichern wird wiederholt.
@Suite("Hinweise zum Speicher")
@MainActor
struct StorageNoticeTests {

    private let today = DateKey(year: 2026, month: 11, day: 11)

    private func temporaryLocation() throws -> StoreLocation {
        let location = StoreLocation(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("planer-hinweis-\(UUID().uuidString)"))
        try location.ensureDirectories()
        return location
    }

    // MARK: - Laden

    @Test func regularLoadHasNoMessage() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        #expect(StateStore(location: location, today: today).loadOutcome.message == nil)
    }

    @Test func recoveryNamesBackupAndSetAsideFile() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let first = StateStore(location: location, today: today)
        first.add(task: TaskItem(title: "Beispiel", startDate: today))
        first.flush()
        try BackupService(location: location).makeDailyBackup()
        try Data("kaputt".utf8).write(to: location.file)

        let store = StateStore(location: location, today: today)
        guard case .recoveredFromBackup(let backup, let quarantined?) = store.loadOutcome,
              let message = store.loadOutcome.message
        else {
            Issue.record("Erwartet: Wiederherstellung mit Hinweis, war \(store.loadOutcome)")
            return
        }
        #expect(message.contains(backup))
        #expect(message.contains(quarantined))
    }

    @Test func emptyStartNamesSetAsideFile() throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try Data("kaputt".utf8).write(to: location.file)

        let store = StateStore(location: location, today: today)
        guard case .startedEmpty(let quarantined?) = store.loadOutcome,
              let message = store.loadOutcome.message
        else {
            Issue.record("Erwartet: leerer Start mit Hinweis, war \(store.loadOutcome)")
            return
        }
        #expect(message.contains(quarantined))
    }

    // MARK: - Speichern

    /// Schreibfehler werden gemeldet und nach kurzer Zeit erneut versucht.
    @Test func failedSaveIsReportedAndRetried() async throws {
        let location = try temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = StateStore(location: location, today: today)
        store.saveRetryDelay = .milliseconds(50)

        // Ein Ordner an der Stelle der Datei laesst jedes Schreiben scheitern.
        try FileManager.default.createDirectory(at: location.file, withIntermediateDirectories: true)
        store.add(task: TaskItem(title: "Beispiel", startDate: today))
        store.flush()
        #expect(store.saveFailure != nil)

        // Das Hindernis verschwindet - ohne weiteres Zutun wird gespeichert.
        try FileManager.default.removeItem(at: location.file)
        for _ in 0..<40 where store.saveFailure != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.saveFailure == nil)

        let data = try Data(contentsOf: location.file)
        let document = try StoredDocument.decoder.decode(StoredDocument.self, from: data)
        #expect(document.state.tasks.map(\.title) == ["Beispiel"])
    }
}
