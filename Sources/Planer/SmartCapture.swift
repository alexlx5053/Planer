import Foundation
import PlanerCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Die Verbindung zum Sprachmodell von Apple, das auf dem Mac selbst laeuft.
///
/// **Lokal und ohne Kosten.** Der Text verlaesst den Rechner nicht, es gibt
/// keinen Schluessel, kein Konto und keine Rechnung - das war die Bedingung, als
/// die App entstand, und sie gilt weiter. Dafuer ist das Modell klein, und
/// genau deshalb bekommt es nur die Aufgabe, in der es verlaesslich ist: sagen,
/// was im Text ein Eintrag ist und wie er heisst. Gerechnet wird woanders
/// (`QuickParser`).
///
/// Gibt es das Modell nicht - aelteres System, Apple Intelligence
/// ausgeschaltet, Modell noch nicht geladen -, antwortet `suggestions` mit
/// `nil`, und die Regeln arbeiten allein.
@MainActor
enum SmartCapture {

    /// Steht das Modell auf diesem Mac gerade bereit?
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Laenger darf der Text fuer das Modell nicht sein - sein Fenster ist
    /// klein. Die Regeln lesen in jedem Fall den ganzen Text.
    private static let characterLimit = 3500

    private static let instructions = """
    Du liest einen Text und findest darin Termine und Aufgaben. Du antwortest ausschließlich \
    mit einem JSON-Array, ohne Erklärung.
    Jedes Element hat genau diese Felder:
    - "art": "termin" (findet zu einer Zeit statt) oder "aufgabe" (ist zu erledigen, oft mit Frist)
    - "titel": kurzer Name, höchstens sechs Wörter, ohne Datum und ohne Uhrzeit
    - "ausschnitt": der Satz oder die Zeile aus dem Text, wörtlich kopiert, in der Datum oder \
    Uhrzeit dieses Eintrags steht
    Grüße, Anreden und Floskeln sind keine Einträge. Erfinde nichts. Steht nichts Passendes \
    im Text, antworte mit [].
    """

    /// Fragt das Modell, was im Text steht. `nil`, wenn es nicht verfuegbar
    /// ist oder nichts Lesbares antwortet.
    static func suggestions(for text: String) async -> [QuickParser.Suggestion]? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isAvailable else { return nil }
        do {
            // Jede Anfrage in einer frischen Sitzung: Der vorige Text soll den
            // naechsten nicht faerben.
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Text:\n\(text.prefix(characterLimit))",
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 900)
            )
            return QuickParser.suggestions(fromModelOutput: response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
