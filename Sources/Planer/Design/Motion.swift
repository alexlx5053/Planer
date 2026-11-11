import SwiftUI

/// Bewegungsvorgaben der App.
///
/// Grundsatz: Federn statt fester Dauern. Eine lineare Animation verraet, dass
/// etwas animiert wird; eine Feder wirkt, als haette man den Gegenstand
/// tatsaechlich bewegt.
///
/// Jede Vorgabe hat eine reduzierte Fassung. Ist „Bewegung reduzieren" aktiv,
/// wird nicht etwa gar nichts animiert - dann wuerden Zustaende hart springen -
/// sondern kurz und ohne Nachschwingen ueberblendet.
enum Motion {

    /// Zustandswechsel: Haekchen, Auswahl, Ein- und Ausblenden.
    static func snappy(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .snappy(duration: 0.26, extraBounce: 0.04)
    }

    /// Layoutwechsel: Listen sortieren sich um, Karten wachsen.
    static func smooth(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.14) : .smooth(duration: 0.34)
    }

    /// Der kurze Nachschwinger beim Abhaken.
    static func bounce(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.52)
    }

    /// Werte, die sich fortlaufend aendern - Ring, Fortschrittsbalken.
    static func value(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.15) : .smooth(duration: 0.5)
    }
}

extension View {
    /// Animiert nur, wenn es der Nutzer zulaesst.
    func animation(_ builder: (Bool) -> Animation, value: some Equatable, reduced: Bool) -> some View {
        animation(builder(reduced), value: value)
    }
}
