import PlanerCore
import SwiftUI

/// Der Tag als waagerechter Streifen: belegt dunkel, frei leer.
///
/// Gedacht fuer das Bearbeiten-Blatt. Wer dort eine Uhrzeit eintippt, will
/// nicht lesen, ob sie passt, sondern es sehen - ein Blick auf einen Streifen
/// beantwortet in einem Zug, was drei Zeilen Text umschreiben muessten: Wo ist
/// schon etwas, wo ist noch Platz, und wo genau liegt das, was ich gerade
/// vorhabe.
///
/// Waagerecht statt senkrecht wie im Stundenplanraster, weil ein Blatt breit
/// und niedrig ist. Dieselbe Darstellung in einer Spalte haette dort nur
/// zwanzig Pixel Hoehe pro Stunde.
struct DayRail: View {
    let window: TimeSpan
    let blocks: [BusyBlock]
    /// Was gerade geplant wird - liegt oben auf.
    var planned: TimeSpan?
    /// Beisst sich das Geplante mit etwas?
    var hasConflict = false

    private static let railHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .fill(Palette.canvas)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1)
                        )

                    // Stundenstriche, nur als Orientierung.
                    ForEach(tickHours, id: \.self) { hour in
                        Rectangle()
                            .fill(Palette.border)
                            .frame(width: 1)
                            .offset(x: x(ClockTime(hour: hour), in: geometry.size.width))
                    }

                    ForEach(blocks) { block in
                        bar(block, width: geometry.size.width)
                    }

                    if let planned {
                        plannedBar(planned, width: geometry.size.width)
                    }
                }
            }
            .frame(height: Self.railHeight)

            // Die Beschriftung sitzt unter dem Streifen und nicht darin: im
            // Streifen waere sie von Bloecken verdeckt, sobald der Tag voll ist.
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(labelHours, id: \.self) { hour in
                        Text(ClockTime(hour: hour).shortText)
                            .font(.system(size: 8))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                            .offset(x: x(ClockTime(hour: hour), in: geometry.size.width) - 3)
                    }
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement()
        .accessibilityLabel("Belegung des Tages")
        .accessibilityValue(spokenSummary)
    }

    // MARK: - Bloecke

    private func bar(_ block: BusyBlock, width: CGFloat) -> some View {
        let color = Palette.eventColor(key: block.colorKey)

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(block.isCourse ? color.opacity(0.55) : color.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(color.opacity(block.isCourse ? 0 : 0.7), lineWidth: 1)
            )
            .frame(width: barWidth(block.span, in: width), height: Self.railHeight - 8)
            .offset(x: x(block.span.start, in: width), y: 4)
            .help("\(block.label) · \(block.span.text)")
    }

    /// Das Geplante liegt oben auf und ist das Hellste im Streifen - oder, wenn
    /// es sich beisst, das Auffaelligste.
    private func plannedBar(_ span: TimeSpan, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(hasConflict ? Palette.urgent : Palette.accent)
            .frame(width: barWidth(span, in: width), height: Self.railHeight - 4)
            .offset(x: x(span.start, in: width), y: 2)
    }

    // MARK: - Umrechnung

    private func fraction(_ time: ClockTime) -> CGFloat {
        guard window.minutes > 0 else { return 0 }
        let value = CGFloat(time.minutes - window.start.minutes) / CGFloat(window.minutes)
        return min(max(value, 0), 1)
    }

    private func x(_ time: ClockTime, in width: CGFloat) -> CGFloat {
        fraction(time) * width
    }

    /// Mindestens zwei Punkte breit: Ein Viertelstuendchen waere sonst
    /// unsichtbar.
    private func barWidth(_ span: TimeSpan, in width: CGFloat) -> CGFloat {
        max((fraction(span.end) - fraction(span.start)) * width, 2)
    }

    private var tickHours: [Int] {
        Array(window.start.hour...window.end.hour)
    }

    /// Jede zweite Stunde beschriften - alle waeren bei dieser Breite ein
    /// Zahlenteppich.
    private var labelHours: [Int] {
        tickHours.filter { $0 % 2 == 0 }
    }

    private var spokenSummary: String {
        guard !blocks.isEmpty else { return "nichts eingetragen" }
        return blocks.map { "\($0.label) \($0.span.text)" }.joined(separator: ", ")
    }
}
