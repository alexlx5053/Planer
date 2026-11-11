import SwiftUI

// MARK: - Karte

/// Die Grundflaeche fuer alle Inhaltsbloecke.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.spacing16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

// MARK: - Abschnittsueberschrift

/// Ueberschrift einer Liste, rechts der Zaehler „erledigt/gesamt".
struct SectionHeader: View {
    let title: String
    var done: Int?
    var total: Int?

    var body: some View {
        HStack(spacing: Metrics.spacing6) {
            Text(title)
                .font(Typo.sectionTitle)
                .tracking(Typo.sectionTracking)
                .foregroundStyle(Palette.textSecondary)

            Spacer(minLength: Metrics.spacing8)

            if let done, let total, total > 0 {
                Text("\(done)/\(total)")
                    .font(Typo.chip)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Kennzeichnung

/// Kleine Beschriftung wie „täglich" oder „14:30".
///
/// Ohne Hintergrundflaeche, nur in gedaempfter Farbe. Eine Kachel um jedes
/// Woertchen erzeugt Unruhe, wo eigentlich nur eine Nebeninformation steht.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Palette.textSecondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(Typo.chip)
        .monospacedDigit()
        .foregroundStyle(tint)
    }
}

/// Kennzeichnung mit Flaeche - nur fuer Zustaende, die auffallen sollen.
struct SolidChip: View {
    let text: String
    var systemImage: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(Typo.chip)
        .foregroundStyle(tint)
        .padding(.horizontal, Metrics.spacing6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }
}

// MARK: - Haekchen

/// Das meistbenutzte Bedienelement der App.
///
/// Eckig fuer Aufgaben, rund fuer Gewohnheiten und Ereignisse - so lassen sich
/// die Listen auch mit einem Blick auseinanderhalten.
struct CheckToggle: View {
    enum Shape { case square, round }

    let isOn: Bool
    var shape: Shape = .square
    var tint: Color = Palette.accent
    var label: String = ""
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var burstStart: Date?

    private var size: CGFloat { 17 }
    private var cornerRadius: CGFloat { shape == .square ? 4.5 : size / 2 }

    private var strokeColor: Color {
        if isOn { return tint }
        return isHovering ? Palette.borderStrong : Palette.borderStrong.opacity(0.7)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isOn ? tint : Color.clear)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1.4)

                // Dunkles Haekchen auf gedaempfter Fuellung: Weiss wirkt auf
                // einem entsaettigten Ton flau.
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Palette.onAccent)
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.4)
            }
            .frame(width: size, height: size)
            .animation(Motion.bounce(reduced: reduceMotion), value: isOn)
            .expandedHitArea()
        }
        .buttonStyle(.pressable(scale: 0.86))
        .onHover { isHovering = $0 }
        .overlay {
            if let burstStart {
                ConfettiBurst(start: burstStart)
            }
        }
        .onChange(of: isOn) { wasOn, nowOn in
            // Nur beim Abhaken, nicht beim Zuruecknehmen - und nie, wenn der
            // Nutzer Bewegung reduziert haben will.
            guard nowOn, !wasOn, !reduceMotion else { return }
            let started = Date()
            burstStart = started
            Task {
                try? await Task.sleep(for: .milliseconds(620))
                // Die Zeichenschleife laeuft mit der Bildwiederholrate; sie muss
                // wieder verschwinden, sonst rechnet sie dauerhaft weiter.
                if burstStart == started { burstStart = nil }
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "erledigt" : "offen")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Fortschritts-Ring

/// Tagesfortschritt als Ring. (Spezifikation 4.9)
struct ProgressRing: View {
    let fraction: Double
    var isPerfect: Bool = false
    var caption: String?
    var diameter: CGFloat = 104
    var lineWidth: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { isPerfect ? Palette.perfect : Palette.accent }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.border, lineWidth: lineWidth)

            // Ein runder Strichabschluss auf minimaler Laenge ergaebe bei 0 %
            // einen Punkt bei zwoelf Uhr - also gar nichts zeichnen.
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fraction > 0 ? 1 : 0)
                .animation(Motion.value(reduced: reduceMotion), value: fraction)

            VStack(spacing: 2) {
                if isPerfect {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(tint)
                    Text("perfekt")
                        .font(Typo.chip)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int((fraction * 100).rounded()))")
                            .font(Typo.metric)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(Typo.metricSmall)
                            .foregroundStyle(Palette.textSecondary)
                    }

                    if let caption {
                        Text(caption)
                            .font(Typo.chip)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel("Tagesfortschritt")
        .accessibilityValue(
            isPerfect ? "perfekter Tag" : "\(Int((fraction * 100).rounded())) Prozent"
        )
    }
}

// MARK: - Streak

/// Serie perfekter Tage. Ohne laufende Serie bleibt die Anzeige stumm statt
/// eine Null zu zeigen - eine grosse 0 waere jeden Morgen ein Vorwurf.
struct StreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: Metrics.spacing6) {
            Image(systemName: "flame")
                .imageScale(.small)
                .foregroundStyle(days > 0 ? Palette.accent : Palette.textTertiary)
            if days > 0 {
                Text("\(days)")
                    .font(Typo.metricSmall)
                    .contentTransition(.numericText())
                Text(days == 1 ? "Tag in Folge" : "Tage in Folge")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text("Noch keine Serie")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Zeile

/// Grundgeruest einer Listenzeile: farbiger Streifen links, dann der Inhalt.
///
/// Der Streifen liegt als Ueberlagerung auf der Zeile statt als Geschwister im
/// Stapel. Als Geschwister waere er ein in der Hoehe flexibles Element und
/// wuerde den freien Platz der Karte an sich ziehen - die Zeilen liefen
/// auseinander.
struct ItemRow<Content: View>: View {
    var stripColor: Color?
    var isDone: Bool = false
    @ViewBuilder var content: Content

    @State private var isHovering = false

    private var leadingInset: CGFloat {
        Metrics.spacing6 + Metrics.accentStripWidth + Metrics.spacing8
    }

    var body: some View {
        HStack(spacing: Metrics.spacing8) {
            content
        }
        .padding(.vertical, Metrics.spacing6)
        .padding(.leading, leadingInset)
        .padding(.trailing, Metrics.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(isHovering ? Palette.surfaceRaised : .clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                .fill(stripColor ?? .clear)
                .frame(width: Metrics.accentStripWidth)
                .padding(.vertical, 4)
                .padding(.leading, Metrics.spacing6)
        }
        .opacity(isDone ? 0.45 : 1)
        .onHover { isHovering = $0 }
    }
}
