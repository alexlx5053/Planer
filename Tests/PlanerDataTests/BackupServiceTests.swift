import Foundation
import Testing
@testable import PlanerData

@Suite("Sicherungen")
struct BackupServiceTests {

    private func makeLocation() throws -> StoreLocation {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LD-Backup-\(UUID().uuidString)", isDirectory: true)
        let location = StoreLocation(directory: directory)
        try location.ensureDirectories()
        try Data("{\"schemaVersion\":1}".utf8).write(to: location.file)
        return location
    }

    private func date(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw) ?? Date()
    }

    @Test func createsOneBackupPerDay() throws {
        let location = try makeLocation()
        let service = BackupService(location: location)

        try service.makeDailyBackup(now: date("2026-09-04"))
        try service.makeDailyBackup(now: date("2026-09-04"))
        try service.makeDailyBackup(now: date("2026-09-05"))

        #expect(service.availableBackups().count == 2)
    }

    @Test func keepsOnlyTheMostRecentBackups() throws {
        let location = try makeLocation()
        let service = BackupService(location: location)

        for offset in 0..<20 {
            let stamp = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: date("2026-09-01")) ?? Date()
            try service.makeDailyBackup(now: stamp)
        }

        let backups = service.availableBackups()
        #expect(backups.count == BackupService.keepCount)
        #expect(backups.first?.lastPathComponent == "dashboard-2026-09-20.json",
                "Die neueste Sicherung muss vorne stehen")
        #expect(backups.last?.lastPathComponent == "dashboard-2026-09-07.json",
                "Aeltere Staende fallen hinten heraus")
    }

    @Test func doesNothingWithoutASourceFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LD-Backup-\(UUID().uuidString)", isDirectory: true)
        let location = StoreLocation(directory: directory)
        try location.ensureDirectories()

        let service = BackupService(location: location)
        try service.makeDailyBackup()

        #expect(service.availableBackups().isEmpty)
    }

    @Test func quarantineMovesTheFileAside() throws {
        let location = try makeLocation()
        let service = BackupService(location: location)

        let moved = service.quarantineCorruptFile(now: date("2026-09-04"))

        #expect(moved != nil)
        #expect(!FileManager.default.fileExists(atPath: location.file.path))
        #expect(FileManager.default.fileExists(atPath: moved?.path ?? ""))
    }

    // MARK: - Kopie vor dem Import

    /// Auch wenn es die Tagessicherung schon gibt, entsteht eine neue Kopie.
    @Test func preImportBackupIsAlwaysMade() throws {
        let location = try makeLocation()
        let service = BackupService(location: location)
        let now = date("2026-09-04")

        try service.makeDailyBackup(now: now)
        let first = try service.makePreImportBackup(now: now)
        let second = try service.makePreImportBackup(now: now)

        #expect(first?.lastPathComponent.hasPrefix("dashboard-vor-import-2026-09-04-") == true)
        #expect(first != second, "Zwei Importe in derselben Sekunde ueberschreiben sich nicht")
        #expect(service.preImportBackups().count == 2)
        #expect(service.preImportBackups().first?.lastPathComponent == second?.lastPathComponent,
                "Die zuletzt angelegte Kopie steht vorne")
    }

    /// Die Kopien vor dem Import zaehlen nicht zur taeglichen Rotation - sie
    /// verdraengen keine Tagessicherung und werden von ihr nicht geloescht.
    @Test func preImportBackupsStayOutOfTheDailyRotation() throws {
        let location = try makeLocation()
        let service = BackupService(location: location)

        let copy = try service.makePreImportBackup(now: date("2026-09-01"))
        for offset in 0..<20 {
            let stamp = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: date("2026-09-01")) ?? Date()
            try service.makeDailyBackup(now: stamp)
        }

        #expect(service.availableBackups().count == BackupService.keepCount)
        #expect(service.availableBackups().allSatisfy {
            !$0.lastPathComponent.hasPrefix("dashboard-vor-import-")
        })
        #expect(FileManager.default.fileExists(atPath: copy?.path ?? ""))
    }
}
