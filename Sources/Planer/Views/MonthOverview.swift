import PlanerCore
import PlanerData
import SwiftUI

/// Der ganze Monat auf einen Blick. (Spezifikation 4.18)
struct MonthOverview: View {
    @Bindable var model: AppModel
    @Environment(\.closePanel) private var dismiss

    private var store: StateStore { model.store }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            weekdayRow
            grid
        }
        .frame(maxWidth: 980, maxHeight: 660)
        .background(Palette.canvas)
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: Metrics.spacing12) {
            Text(MiniCalendar.monthTitle(model.visibleMonth))
                .font(Typo.pageTitle)
                .foregroundStyle(Palette.textPrimary)

            Button("Heute") {
                model.goToToday()
            }
            .buttonStyle(.pressable)
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)
            .expandedHitArea(6)

            Spacer()

            HStack(spacing: Metrics.spacing2) {
                stepButton("chevron.left", step: -1)
                stepButton("chevron.right", step: 1)
            }

            Button("Fertig") { dismiss() }
                .buttonStyle(.pressable)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
                .expandedHitArea(6)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Metrics.spacing20)
        .frame(height: 52)
    }

    private func stepButton(_ symbol: String, step: Int) -> some View {
        Button { model.stepMonth(step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 26, height: 26)
                .expandedHitArea(4)
        }
        .buttonStyle(.pressable(scale: 0.8))
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(Self.weekdayNames.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metrics.spacing6)
            }
        }
        .background(Palette.canvas)
    }

    private static let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag",
                                       "Freitag", "Samstag", "Sonntag"]

    // MARK: - Raster

    /// Sechs Wochenzeilen, die sich die Hoehe gleichmaessig teilen.
    ///
    /// Bewusst kein `LazyVGrid`: Dessen Zeilen nehmen nur ihre Eigenhoehe ein
    /// und sammeln sich in der Mitte, statt den Monat auszufuellen.
    private var grid: some View {
        VStack(spacing: 1) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { weekday in
                        cell(for: MiniCalendar.gridDays(of: model.visibleMonth)[week * 7 + weekday])
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(1)
        .background(Palette.border)
        .frame(maxHeight: .infinity)
    }

    private func cell(for day: DateKey) -> some View {
        MonthCell(
            day: day,
            isInMonth: day.month == model.visibleMonth.month,
            isToday: day == store.today,
            isSelected: day == model.selectedDate,
            holiday: Holidays.name(on: day),
            isVacation: store.state.isVacationDay(day, today: store.today),
            events: store.state.events(on: day, today: store.today),
            isPerfect: store.stats(for: day).isPerfect
        ) {
            model.selectedDate = day
            dismiss()
        }
    }
}

// MARK: - Ein Tag im Monatsraster

private struct MonthCell: View {
    let day: DateKey
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let holiday: String?
    let isVacation: Bool
    let events: [EventItem]
    let isPerfect: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// Wochenenden liegen eine Spur dunkler - genug, um die Woche zu gliedern,
    /// zu wenig, um als eigener Zustand zu wirken.
    private var background: Color {
        if !isInMonth { return Palette.canvas }
        if isHovering { return Palette.surfaceRaised }
        return day.isWeekend ? Palette.canvas : Palette.surface
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Metrics.spacing4) {
                HStack(spacing: Metrics.spacing4) {
                    Text("\(day.day)")
                        .font(.system(size: 12, weight: isToday ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(dayColor)

                    if isPerfect {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.perfect)
                    }

                    Spacer(minLength: 0)
                }

                if let holiday {
                    Text(holiday)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.urgent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if isVacation {
                    Label("Urlaub", systemImage: "beach.umbrella")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                // Hoechstens drei Termine, danach nur noch die Zahl - eine
                // Zelle, die alles zeigt, zeigt am Ende nichts.
                ForEach(events.prefix(3)) { event in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Palette.eventColor(key: event.colorKey))
                            .frame(width: 4, height: 4)
                        Text(event.title)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                if events.count > 3 {
                    Text("+\(events.count - 3) weitere")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(Metrics.spacing6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Palette.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityText)
    }

    private var dayColor: Color {
        if !isInMonth { return Palette.textTertiary.opacity(0.5) }
        if isToday { return Palette.accent }
        if holiday != nil { return Palette.urgent }
        return Palette.textPrimary
    }

    private var accessibilityText: String {
        var parts = [DateField.format(day)]
        if let holiday { parts.append(holiday) }
        if isVacation { parts.append("Urlaubstag") }
        if events.isEmpty { parts.append("keine Termine") }
        else { parts.append("\(events.count) Termine") }
        if isPerfect { parts.append("perfekter Tag") }
        return parts.joined(separator: ", ")
    }
}
