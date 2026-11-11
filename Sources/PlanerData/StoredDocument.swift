import Foundation
import PlanerCore

/// Was tatsaechlich in der Datei steht: der Zustand plus eine Versionsnummer.
///
/// Die Nummer ist heute ungenutzt, kostet aber nichts - und ohne sie waere eine
/// spaetere Formataenderung ein Ratespiel.
public struct StoredDocument: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var state: DashboardState
    /// Zeitpunkt des Speicherns, nur zur Information beim Aufraeumen von Backups.
    public var savedAt: Date

    public init(state: DashboardState, savedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.state = state
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, state, savedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        state = try c.decodeIfPresent(DashboardState.self, forKey: .state) ?? DashboardState()
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
    }

    // MARK: - Kodierung

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Lesbar und zeilenweise vergleichbar - falls jemals von Hand in die
        // Datei geschaut werden muss, ist das Gold wert.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
