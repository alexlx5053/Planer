import PlanerCore
import SwiftUI

/// Was ein Tag im Kalender ueber sich verraet.
struct DayMark {
    /// Der Tag hat mindestens einen Termin.
    var hasEvents = false
    /// Alles an diesem Tag ist erledigt.
    var isPerfect = false
}

/// Monatsraster, montagsbeginnend. (Spezifikation 4.2)
struct MiniCalendar: View {
    let month: DateKey
    let selected: DateKey
    let today: DateKey
    var mark: (DateKey) -> DayMark
    var onSelect: (DateKey) -> Void
    var onStep: (Int) -> Void
    var onToday: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: Metrics.spacing8) {
            header
            weekdayRow
            grid
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: 0) {
            Button { onToday() } label: {
                Text(Self.monthTitle(month))
                    .font(Typo.sectionTitle)
                    .tracking(Typo.sectionTracking)
                    .foregroundStyle(Palette.textPrimary)
                    .expandedHitArea(5)
            }
            .buttonStyle(.plain)
            .help("Zu heute springen")

            Spacer()

            HStack(spacing: Metrics.spacing2) {
                stepButton("chevron.left", step: -1, help: "Vorheriger Monat")
                stepButton("chevron.right", step: 1, help: "Nächster Monat")
            }
        }
    }

    private func stepButton(_ symbol: String, step: Int, help: String) -> some View {
        Button { onStep(step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24, height: 24)
                .expandedHitArea(4)
        }
        .buttonStyle(.pressable(scale: 0.8))
        .help(help)
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            // Ueber den Index, nicht ueber den Namen: „Mo" und „Mi" sind
            // verschieden, „M" und „M" waeren es nicht - `id: \.self` wuerde
            // doppelte Kuerzel verschlucken.
            ForEach(Array(Self.weekdayNames.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Raster

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Self.gridDays(of: month), id: \.self) { day in
                DayCell(
                    day: day,
                    isInMonth: day.month == month.month,
                    isSelected: day == selected,
                    isToday: day == today,
                    mark: mark(day)
                ) {
                    onSelect(day)
                }
            }
        }
    }

    // MARK: - Aufbau des Rasters

    /// Immer sechs volle Wochen: So springt das Raster beim Monatswechsel nicht
    /// in der Hoehe, und die Seitenspalte bleibt ruhig.
    static func gridDays(of month: DateKey) -> [DateKey] {
        let start = month.startOfMonth.startOfWeek
        return (0..<42).map { start.adding(days: $0) }
    }

    static let weekdayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    static func monthTitle(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: day.date)
    }
}

// MARK: - Einzelner Tag

private struct DayCell: View {
    let day: DateKey
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let mark: DayMark
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var foreground: Color {
        if isSelected { return Palette.onAccent }
        if !isInMonth { return Palette.textTertiary.opacity(0.55) }
        if isToday { return Palette.accent }
        return .primary
    }

    private var background: Color {
        if isSelected { return Palette.accent }
        if isHovering { return Palette.surfaceRaised }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 11.5, weight: isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(foreground)

                // Ein Punkt sagt „hier steht etwas an", die Farbe sagt „und es
                // ist erledigt". Zwei Angaben in drei Pixeln - mehr braucht die
                // Uebersicht nicht.
                Circle()
                    .fill(mark.isPerfect ? Palette.perfect : Palette.borderStrong)
                    .frame(width: 3, height: 3)
                    .opacity((mark.hasEvents || mark.isPerfect) && !isSelected ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.93))
        .onHover { isHovering = $0 }
        .animation(Motion.snappy(reduced: reduceMotion), value: isSelected)
        .accessibilityLabel(Self.accessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    static func accessibilityLabel(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        return formatter.string(from: day.date)
    }
}
