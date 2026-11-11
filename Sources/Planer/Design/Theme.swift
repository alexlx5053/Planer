import AppKit
import SwiftUI

// MARK: - Farbwerte

extension Color {
    /// Fester Farbwert aus einem Hex-String.
    ///
    /// Keine Hell-Dunkel-Umschaltung mehr: Die App laeuft ausschliesslich im
    /// Dunkelmodus. Eine zweite Fassung zu pflegen, die niemand zu sehen
    /// bekommt, waere nur eine Fehlerquelle.
    static func hex(_ value: String) -> Color {
        Color(nsColor: NSColor(hex: value) ?? .textColor)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Das Farbsystem der App: Space Black, durchgehend monochrom.
///
/// Der Fenstergrund ist echtes Schwarz. Auf dem XDR-Display des MacBook Pro
/// schaltet die Hintergrundbeleuchtung dort tatsaechlich ab - jedes Grau statt
/// Schwarz waere sichtbar heller und wuerde genau den Effekt verschenken, um den
/// es geht. Alles Weitere sind Graphitstufen, die sich vom Schwarz abheben.
///
/// Farbe gibt es an genau einer Stelle: dem Blatt, dem Zeichen der App.
enum Palette {

    // MARK: Flaechen

    /// Fenstergrund und Seitenspalte: echtes Schwarz.
    static let canvas = Color.black

    /// Karten und Listen - die erste Stufe ueber dem Schwarz.
    static let surface = Color.hex("#0F0F11")

    /// Zeile unter dem Zeiger oder ausgewaehlt.
    static let surfaceRaised = Color.hex("#1A1A1D")

    /// Haarlinie. Auf schwarzem Grund der wichtigste Baustein ueberhaupt -
    /// er trennt Flaechen, die sich sonst kaum unterscheiden.
    static let border = Color.hex("#242428")

    static let borderStrong = Color.hex("#3A3A40")

    // MARK: Akzent
    //
    // Monochrom: Ein gebrochenes Weiss traegt saemtliche Hervorhebungen -
    // gefuellte Haekchen, den Fortschrittsring, den gewaehlten Tag. Auf Schwarz
    // ist Helligkeit der staerkste Kontrast, den es gibt; Farbe braucht es dafuer
    // nicht.

    static let accent = Color.hex("#FFFFFF")

    /// Was auf dem Akzent liegt - etwa das Haekchen im gefuellten Kasten.
    static let onAccent = Color.black

    /// Zurueckgenommene Hervorhebung, etwa hinterlegte Kennzeichnungen.
    static let accentMuted = Color.hex("#1F1F23")

    // MARK: Zeichen der App
    //
    // Das einzige Gruen im ganzen Programm. Es steht fuer das Blatt - im Icon
    // und am Zeichen in der Symbolleiste - und sonst nirgends.

    static let leaf = Color.hex("#7CB342")

    // MARK: Kategorienfarben
    //
    // Sechs Toene fuer Ereignisse. Sie muessen unterscheidbar sein, sollen aber
    // nicht bunt wirken: fast neutrale Graustufen mit einem Hauch Farbton, die
    // sich staerker in der Helligkeit als im Ton unterscheiden.

    static let stone = Color.hex("#8E8E96")
    static let mist = Color.hex("#7C8794")
    static let sand = Color.hex("#9C9285")
    static let clay = Color.hex("#9C8380")
    static let moss = Color.hex("#86907E")
    static let chalk = Color.hex("#C6C6CC")

    /// Auswahl fuer Ereignisfarben. Die Kennungen bleiben stabil, auch wenn sich
    /// die Farbwerte spaeter noch verschieben.
    static let eventPalette: [(name: String, key: String, color: Color)] = [
        ("Stein", "stone", stone),
        ("Nebel", "mist", mist),
        ("Sand", "sand", sand),
        ("Ton", "clay", clay),
        ("Moos", "moss", moss),
        ("Kreide", "chalk", chalk),
    ]

    static func eventColor(key: String) -> Color {
        eventPalette.first { $0.key == key }?.color ?? stone
    }

    // MARK: Zustaende

    /// Voller Tag. Das hellste Weiss der App - Helligkeit als Belohnung.
    static let perfect = Color.hex("#FFFFFF")

    /// Teilweise erledigt.
    static let partial = Color.hex("#7A7A82")

    /// Hohe Prioritaet. Ein warm gebrochenes Grau: Es hebt sich ab, ohne aus dem
    /// monochromen Bild auszubrechen.
    static let urgent = Color.hex("#B08C82")

    // MARK: Text
    //
    // Bewusst eigene Werte statt `.primary`/`.secondary`: Auf echtem Schwarz
    // setzt das System ein reines Weiss, das bei laengerem Lesen flimmert.

    static let textPrimary = Color.hex("#EDEDEF")
    static let textSecondary = Color.hex("#8E8E96")
    static let textTertiary = Color.hex("#5A5A62")
}

// MARK: - Abstaende, Radien

enum Metrics {
    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 7
    static let chipRadius: CGFloat = 5

    /// Breite des farbigen Streifens an Ereigniszeilen.
    static let accentStripWidth: CGFloat = 2.5

    static let sidebarWidth: CGFloat = 288
    static let minWindowWidth: CGFloat = 900
    static let minWindowHeight: CGFloat = 660

    /// Breite der Inhaltsspalte in der Tagesansicht.
    ///
    /// Zeilen, die ueber die halbe Bildschirmbreite laufen, liest niemand gern -
    /// das Auge verliert beim Ruecksprung die Zeile. Darueber hinaus wird
    /// zentriert statt gestreckt.
    static let contentWidth: CGFloat = 920
}

// MARK: - Typografie

enum Typo {
    /// Ueberschrift der Tagesansicht.
    static let pageTitle = Font.system(.title2, weight: .semibold)
    /// Untertitel mit Datum.
    static let pageSubtitle = Font.system(.subheadline, weight: .regular)
    /// Ueberschrift einer Karte bzw. Liste.
    static let sectionTitle = Font.system(.caption, weight: .semibold)
    static let body = Font.system(.body)
    static let bodyEmphasized = Font.system(.body, weight: .medium)
    static let caption = Font.system(.caption)
    /// Kleine Kennzeichnungen wie „täglich" oder „14:30".
    static let chip = Font.system(.caption2, weight: .medium)

    /// Uhr in der Symbolleiste. Tabellenziffern, damit die Breite konstant bleibt.
    static let clock = Font.system(.callout, weight: .regular).monospacedDigit()
    /// Grosse Kennzahl, etwa im Fortschritts-Ring.
    static let metric = Font.system(size: 27, weight: .light, design: .rounded).monospacedDigit()
    static let metricSmall = Font.system(size: 14, weight: .medium, design: .rounded).monospacedDigit()

    /// Abschnittsbeschriftungen bekommen eine leichte Sperrung - der einzige
    /// Kniff, mit dem kleine Beschriftungen ruhig statt gedraengt wirken.
    static let sectionTracking: CGFloat = 0.6
}

// MARK: - Flaechen

extension View {
    /// Die Standardflaeche fuer Karten.
    ///
    /// Ohne Schlagschatten: Auf echtem Schwarz wird er zu einem schmutzigen
    /// Fleck. Die Karte hebt sich allein durch ihre hellere Flaeche und die
    /// Haarlinie ab - beides genuegt, weil daneben wirklich nichts leuchtet.
    func cardSurface(radius: CGFloat = Metrics.cardRadius) -> some View {
        self
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }
}
