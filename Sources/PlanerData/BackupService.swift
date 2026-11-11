import Foundation

/// Rotierende Sicherungskopien der Datendatei.
///
/// In dieser einen Datei liegt irgendwann die gesamte Historie. Ein Fehler beim
/// Schreiben, ein abgestuerzter Rechner, ein versehentliches Loeschen - ohne
/// Kopien waere das endgueltig.
public struct BackupService: Sendable {
    public static let keepCount = 14

    let location: StoreLocation

    /// Nicht als gespeicherte Eigenschaft: `FileManager` ist nicht `Sendable`,
    /// und `BackupService` soll ueber Aufgabengrenzen hinweg nutzbar bleiben.
    private var fileManager: FileManager { .default }

    public init(location: StoreLocation) {
        self.location = location
    }

    /// Legt hoechstens eine Kopie pro Tag an und raeumt alte Staende ab.
    public func makeDailyBackup(now: Date = Date()) throws {
        guard fileManager.fileExists(atPath: location.file.path) else { return }
        try location.ensureDirectories()

        let target = location.backupDirectory.appendingPathComponent("dashboard-\(Self.stamp(now)).json")
        guard !fileManager.fileExists(atPath: target.path) else { return }

        try fileManager.copyItem(at: location.file, to: target)
        StoreLocation.restrictToOwner(target)
        try prune()
    }

    /// Vorhandene Tagessicherungen, neueste zuerst.
    ///
    /// Die Kopien vor einem Import gehoeren nicht dazu: Sie haben ihre eigene
    /// Rotation, und beim Wiederherstellen nach einem Lesefehler waere ein
    /// Stand von vor dem Import der falsche.
    public func availableBackups() -> [URL] {
        backupFiles()
            .filter { !$0.lastPathComponent.hasPrefix(Self.preImportPrefix) }
    }

    private func prune() throws {
        for url in availableBackups().dropFirst(Self.keepCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Kopie vor dem Import

    public static let preImportKeepCount = 10
    static let preImportPrefix = "dashboard-vor-import-"

    /// Kopiert den aktuellen Stand immer - auch wenn es heute schon eine
    /// Tagessicherung gibt. Gibt die Kopie zurueck, oder `nil`, wenn es noch
    /// keine Datendatei gibt.
    @discardableResult
    public func makePreImportBackup(now: Date = Date()) throws -> URL? {
        guard fileManager.fileExists(atPath: location.file.path) else { return nil }
        try location.ensureDirectories()

        let base = "\(Self.preImportPrefix)\(Self.stamp(now, withTime: true))"
        var target = location.backupDirectory.appendingPathComponent("\(base).json")
        var counter = 2
        while fileManager.fileExists(atPath: target.path) {
            target = location.backupDirectory.appendingPathComponent("\(base)-\(counter).json")
            counter += 1
        }

        try fileManager.copyItem(at: location.file, to: target)
        StoreLocation.restrictToOwner(target)

        for url in preImportBackups().dropFirst(Self.preImportKeepCount) {
            try? fileManager.removeItem(at: url)
        }
        return target
    }

    /// Vorhandene Kopien vor einem Import, neueste zuerst.
    public func preImportBackups() -> [URL] {
        backupFiles().filter { $0.lastPathComponent.hasPrefix(Self.preImportPrefix) }
    }

    private func backupFiles() -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: location.backupDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("dashboard-") && $0.pathExtension == "json" }
            // Ohne Endung vergleichen: Sonst saehe "...-153000-2.json" aelter
            // aus als "...-153000.json", weil "-" vor "." sortiert.
            .sorted { $0.deletingPathExtension().lastPathComponent > $1.deletingPathExtension().lastPathComponent }
    }

    /// Legt eine beschaedigte Datei beiseite, statt sie zu ueberschreiben.
    ///
    /// Wenn das Laden scheitert, ist die Ursache unbekannt - vielleicht ein
    /// Fehler beim Schreiben, vielleicht ein Programmfehler. In beiden Faellen
    /// waere es falsch, die Datei stillschweigend zu ersetzen.
    public func quarantineCorruptFile(now: Date = Date()) -> URL? {
        guard fileManager.fileExists(atPath: location.file.path) else { return nil }
        let target = location.directory
            .appendingPathComponent("dashboard-beschaedigt-\(Self.stamp(now, withTime: true)).json")
        try? fileManager.moveItem(at: location.file, to: target)
        StoreLocation.restrictToOwner(target)
        return target
    }

    static func stamp(_ date: Date, withTime: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = withTime ? "yyyy-MM-dd-HHmmss" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
