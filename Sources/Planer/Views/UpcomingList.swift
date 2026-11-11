import PlanerCore
import SwiftUI

/// Was als Naechstes ansteht. (Spezifikation 4.12)
///
/// Bewusst nur Termine: Eine Aufgabe hat kein „wann", sondern ein „ob" - sie
/// steht auf einem Tag, laesst sich aber verschieben, ohne dass etwas verpasst
/// waere. Ein Termin dagegen kommt, ob man will oder nicht, und genau dafuer
/// braucht man den Vorlauf.
///
/// Die Naehe wird ueber Helligkeit erzaehlt, nicht ueber Farbe: Auf schwarzem
/// Grund ist das der staerkste Kontrast, den es gibt, und er passt zum uebrigen
/// Bild, in dem Farbe nur am Blatt vorkommt.
struct UpcomingList: View {
    let items: [UpcomingEvent]
    /// Wie viele insgesamt anstehen - auch die, fuer die hier kein Platz ist.
    var totalCount: Int = 0
    let onSelect: (UpcomingEvent) -> Void
    /// Oeffnet die vollstaendige Liste.
    var onShowAll: (() -> Void)?

    @State private var headerHovering = false

    /// Feste Breite fuer die Tageszahl. Rechtsbuendig in einer eigenen Spalte
    /// stehen die Zahlen untereinander - erst dadurch laesst sich die Liste
    /// ueberfliegen, statt sie zu lesen.
    private let countdownWidth: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing4) {
            header
                .padding(.bottom, Metrics.spacing2)

            if items.isEmpty {
                Text("Nichts in Sicht.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, Metrics.spacing4)
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
        }
    }

    /// Die Ueberschrift ist der Weg zur ganzen Liste.
    ///
    /// Hier stehen nur so viele Termine, wie in die Spalte passen. Was darueber
    /// hinausgeht, ist einen Klick entfernt - und der Zaehler rechts sagt, ob
    /// sich der Klick lohnt.
    @ViewBuilder
    private var header: some View {
        if let onShowAll {
            Button(action: onShowAll) {
                HStack(spacing: Metrics.spacing4) {
                    SectionHeader(title: "Nächste Termine")
                    Text(totalCount > items.count ? "Alle \(totalCount)" : "Alle")
                        .font(Typo.chip)
                        .monospacedDigit()
                        .foregroundStyle(headerHovering ? Palette.textPrimary : Palette.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(headerHovering ? Palette.textPrimary : Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.98))
            .onHover { headerHovering = $0 }
            .help("Alle anstehenden Termine zeigen")
        } else {
            SectionHeader(title: "Nächste Termine")
        }
    }

    private func row(_ item: UpcomingEvent) -> some View {
        // Die Betonung haengt an der Naehe, nicht an der Position in der Liste:
        // Stehen zwei Termine heute an, sind beide gleich dringend.
        let step = Emphasis(daysAway: item.daysAway)

        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: Metrics.spacing8) {
                Circle()
                    .fill(Palette.eventColor(key: item.event.colorKey))
                    .frame(width: 5, height: 5)
                    .opacity(step.dotOpacity)

                Text(item.event.title)
                    .font(step.isImminent ? Typo.bodyEmphasized : Typo.body)
                    .foregroundStyle(step.title)
                    .lineLimit(1)

                Spacer(minLength: Metrics.spacing6)

                countdown(item, step: step)
            }
            .padding(.vertical, Metrics.spacing4)
            .padding(.horizontal, Metrics.spacing4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98))
        .help("Zum \(DateField.format(item.day))")
        .accessibilityLabel("\(item.event.title), \(item.longLabel)")
    }

    /// Die Tageszahl. Was unmittelbar bevorsteht, bekommt eine eigene Flaeche -
    /// das macht es sichtbar, ohne dass Farbe oder Groesse aufdringlich werden.
    @ViewBuilder
    private func countdown(_ item: UpcomingEvent, step: Emphasis) -> some View {
        if step.isImminent {
            Text(item.shortLabel)
                .font(Typo.metricSmall)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Metrics.spacing6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .fill(Palette.surfaceRaised)
                )
                .frame(width: countdownWidth, alignment: .trailing)
        } else {
            Text(item.shortLabel)
                .font(Typo.metricSmall)
                .foregroundStyle(step.countdown)
                .frame(width: countdownWidth, alignment: .trailing)
        }
    }

    /// Drei Stufen: was unmittelbar bevorsteht, was diese Woche kommt, der Rest.
    private struct Emphasis {
        let daysAway: Int

        var isImminent: Bool { daysAway <= 1 }

        var title: Color {
            switch daysAway {
            case 0...1: Palette.textPrimary
            case 2...7: Palette.textSecondary
            default: Palette.textTertiary
            }
        }

        var countdown: Color {
            switch daysAway {
            case 0...1: Palette.textPrimary
            case 2...7: Palette.textSecondary
            default: Palette.textTertiary
            }
        }

        var dotOpacity: Double {
            switch daysAway {
            case 0...1: 1.0
            case 2...7: 0.7
            default: 0.4
            }
        }
    }
}
