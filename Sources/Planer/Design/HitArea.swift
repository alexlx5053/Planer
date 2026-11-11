import SwiftUI

extension View {
    /// Vergroessert die klickbare Flaeche, ohne das Layout zu veraendern.
    ///
    /// Der Trick ist das negative Innenmass am Ende: Erst wird das Element
    /// aufgeblasen und die Trefferflaeche darauf gelegt, dann wird die
    /// Vergroesserung fuer die Anordnung wieder zurueckgenommen. Sichtbar
    /// aendert sich nichts - man muss nur nicht mehr punktgenau treffen.
    ///
    /// Apple gibt 28 pt als Mindestmass fuer Zeigergeraete an; ein 17 pt grosses
    /// Haekchen braucht also rund 6 pt Zugabe pro Seite.
    func expandedHitArea(_ inset: CGFloat = 6) -> some View {
        padding(inset)
            .contentShape(Rectangle())
            .padding(-inset)
    }
}

/// Knopfstil mit spuerbarer Druckreaktion.
///
/// `.plain` sieht richtig aus, gibt aber keinerlei Rueckmeldung beim Druecken -
/// der Klick fuehlt sich dadurch „leer" an. Ein kurzes Zusammenziehen genuegt,
/// um den Druck zu bestaetigen, ohne die Optik zu veraendern.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    static func pressable(scale: CGFloat) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale)
    }
}

extension View {
    /// Macht die freie Flaeche einer Karte zum Knopf fuer „hinzufuegen".
    ///
    /// Zeilen und Haekchen darin behalten ihre eigene Reaktion - in SwiftUI
    /// gewinnt die innere Geste. Getroffen wird also nur, was daneben liegt:
    /// der Rand, die Ueberschrift, der leere Platz darunter.
    func addOnTap(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
