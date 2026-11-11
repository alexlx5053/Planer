import Foundation

/// Wo die Daten liegen.
///
/// Die Pfade stecken bewusst in einem eigenen Typ: Ein spaeterer Umzug nach
/// iCloud Drive ist damit eine Aenderung an genau dieser Stelle.
public struct StoreLocation: Sendable {
    public let directory: URL

    public var file: URL { directory.appendingPathComponent("dashboard.json") }
    public var backupDirectory: URL { directory.appendingPathComponent("Backups") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Das echte Benutzerverzeichnis.
    ///
    /// `FileManager` liefert innerhalb einer Sandbox den Container des laufenden
    /// Prozesses statt des Benutzers. Das Widget laeuft in einer Sandbox, die App
    /// nicht - beide muessen aber dieselbe Datei meinen. Ueber die
    /// Benutzerdatenbank ist der Pfad in beiden Faellen derselbe.
    public static var userHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory))
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    /// `~/Library/Application Support/Planer`
    public static var applicationSupport: StoreLocation {
        let base = userHome.appendingPathComponent("Library/Application Support", isDirectory: true)
        return adopting(previousName: previousFolderName, newName: "Planer", in: base)
    }

    /// Liefert den Ordner unter `newName` und uebernimmt dabei einen vorhandenen
    /// Ordner unter `previousName`. Ausgelagert, damit sich der Umzug pruefen
    /// laesst, ohne den echten Benutzerordner anzufassen.
    public static func adopting(previousName: String, newName: String, in base: URL) -> StoreLocation {
        let location = StoreLocation(directory: base.appendingPathComponent(newName, isDirectory: true))
        let fileManager = FileManager.default
        let previous = base.appendingPathComponent(previousName, isDirectory: true)

        // Nur uebernehmen, wenn es den alten Ordner gibt und den neuen noch
        // nicht - sonst wuerde ein bereits begonnener Bestand ueberschrieben.
        if fileManager.fileExists(atPath: previous.path),
           !fileManager.fileExists(atPath: location.directory.path) {
            try? fileManager.moveItem(at: previous, to: location.directory)
        }
        return location
    }

    /// Frueherer Ordnername der App.
    ///
    /// Die App hiess urspruenglich „Lebens-Dashboard". Wer sie damals schon
    /// benutzt hat, soll seine Eintraege behalten - deshalb wird der alte Ordner
    /// beim ersten Start unter dem neuen Namen weitergefuehrt.
    private static let previousFolderName = "Lebens-Dashboard"

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        Self.restrictToOwner(directory)
        Self.restrictToOwner(backupDirectory)
    }

    // MARK: - Zugriffsrechte

    /// Nur der Besitzer darf lesen und schreiben.
    ///
    /// In der Datei steht ein Leben: Termine, Gewohnheiten, Notizen. macOS
    /// legt neue Dateien fuer alle Benutzer des Rechners lesbar an; meist
    /// schuetzt der Ordner darueber, aber darauf soll es nicht ankommen. Die
    /// Rechte werden deshalb ausdruecklich gesetzt - bei jedem Schreiben und
    /// bei jedem Start, sodass auch aeltere Dateien nachgezogen werden.
    ///
    /// Ein Fehler hier ist kein Grund, das Speichern abzubrechen: Lieber eine
    /// gesicherte Datei mit zu weiten Rechten als keine.
    static func restrictToOwner(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        let permissions = isDirectory.boolValue ? 0o700 : 0o600
        try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    /// Zieht die Rechte aller vorhandenen Dateien nach - Datendatei,
    /// Sicherungen und beiseitegelegte Staende.
    func restrictExistingFiles() {
        Self.restrictToOwner(directory)
        Self.restrictToOwner(backupDirectory)
        for folder in [directory, backupDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )) ?? []
            for file in files where file.pathExtension == "json" {
                Self.restrictToOwner(file)
            }
        }
    }
}
