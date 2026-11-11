import PlanerCore
import PlanerData
import SwiftUI

/// Was hinter dem Menueleisten-Symbol aufklappt.
///
/// Es beantwortet zwei Fragen, die man sich im Vorbeigehen stellt: Was steht
/// heute noch an, und was kommt als Naechstes. Keine Kennzahlen - die stehen in
/// der App, und wer nur kurz hinschaut, will Namen lesen, keine Prozente.
///
/// Abhaken geht direkt hier: Wo ein Kaestchen steht, erwartet man, dass es sich
/// anklicken laesst.
struct MenuBarPanel: View {
    @Bindable var model: AppModel

    @Environment(\.openWindow) private var openWindow

    /// Mehr als das passt nicht in ein Fenster, das im Vorbeigehen gelesen wird.
    private let maxToday = 7

    private var store: StateStore { model.store }
    private var today: DateKey { store.today }
    private var agenda: DayAgenda { store.agenda(for: today) }
    private var stats: DayStats { store.stats(for: today) }

    /// Was nach heute kommt.
    ///
    /// Heutige Termine stehen bereits oben - sie hier zu wiederholen kostete
    /// Platz und sagte nichts Neues.
    private var comingUp: [UpcomingEvent] {
        Array(store.upcomingEvents(limit: 8).filter { $0.daysAway > 0 }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing12) {
            header

            if !agenda.courses.isEmpty {
                Divider().overlay(Palette.border)
                courseSection
            }

            Divider().overlay(Palette.border)
            todaySection

            if !comingUp.isEmpty {
                Divider().overlay(Palette.border)
                upcomingSection
            }

            Divider().overlay(Palette.border)
            actions
        }
        .padding(Metrics.spacing12)
        .frame(width: 280)
        .background(Palette.canvas)
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: Metrics.spacing6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.leaf)
            Text(Self.todayLabel(today))
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if stats.isPerfect {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.perfect)
            }
        }
    }

    // MARK: - Uni

    /// Der Stundenplan des Tages.
    ///
    /// Zuerst, noch vor den Terminen: Was gesetzt ist, bestimmt den Tag. Und
    /// ohne Kaestchen - hier gibt es nichts abzuhaken, nur etwas nachzusehen.
    private var courseSection: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing4) {
            SectionHeader(title: "Uni")

            ForEach(agenda.courses.prefix(5)) { course in
                HStack(spacing: Metrics.spacing8) {
                    Text(course.span.text)
                        .font(Typo.chip)
                        .monospacedDigit()
                        .foregroundStyle(
                            isOver(course) ? Palette.textTertiary : Palette.textSecondary
                        )
                        .frame(width: 76, alignment: .leading)

                    Text(course.title)
                        .font(Typo.caption)
                        .foregroundStyle(
                            isOver(course) ? Palette.textTertiary : Palette.textPrimary
                        )
                        .lineLimit(1)

                    Spacer(minLength: Metrics.spacing4)

                    if !course.room.isEmpty {
                        Text(course.room)
                            .font(Typo.chip)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(.vertical, 1)
            }

            if agenda.courses.count > 5 {
                Text("+\(agenda.courses.count - 5) weitere")
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// Vorbei? Dann tritt die Zeile zurueck.
    ///
    /// Im Vorbeigehen interessiert, was noch kommt. Was schon war, soll die
    /// Liste nicht gleich gewichtig fuellen.
    private func isOver(_ course: CourseItem) -> Bool {
        let parts = ldCalendar.dateComponents([.hour, .minute], from: model.now)
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) >= course.end
    }

    // MARK: - Heute

    /// Termine zuerst, dann Aufgaben - dieselbe Reihenfolge wie in der App.
    private var todayItems: [TodayItem] {
        let events = agenda.events.map {
            TodayItem(id: $0.id, title: $0.title, detail: $0.time,
                      tint: Palette.eventColor(key: $0.colorKey), isRound: true)
        }
        let tasks = agenda.tasks.map {
            TodayItem(id: $0.id, title: $0.title, detail: nil,
                      tint: $0.priority == .high ? Palette.urgent : Palette.accent,
                      isRound: false)
        }
        return events + tasks
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing4) {
            SectionHeader(title: "Heute")

            if todayItems.isEmpty {
                Text(agenda.isVacation ? "Urlaub." : "Nichts eingetragen.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(todayItems.prefix(maxToday)) { item in
                    row(item)
                }
                if todayItems.count > maxToday {
                    Text("+\(todayItems.count - maxToday) weitere")
                        .font(Typo.chip)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, 23)
                }
            }

            if stats.habitsTotal > 0 {
                Text("Gewohnheiten \(stats.habitsDone)/\(stats.habitsTotal)")
                    .font(Typo.chip)
                    .monospacedDigit()
                    .foregroundStyle(
                        stats.habitsDone == stats.habitsTotal ? Palette.perfect : Palette.textTertiary
                    )
                    .padding(.top, Metrics.spacing2)
            }
        }
    }

    private func row(_ item: TodayItem) -> some View {
        let isDone = store.isDone(item.id, on: today)

        return HStack(spacing: Metrics.spacing8) {
            CheckToggle(
                isOn: isDone,
                shape: item.isRound ? .round : .square,
                tint: item.tint,
                label: item.title
            ) {
                store.toggleCompletion(item.id, on: today)
            }

            Text(item.title)
                .font(Typo.caption)
                .foregroundStyle(Palette.textPrimary)
                .strikethrough(isDone, color: Palette.textSecondary)
                .lineLimit(1)

            Spacer(minLength: Metrics.spacing6)

            if let detail = item.detail {
                Text(detail)
                    .font(Typo.chip)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .opacity(isDone ? 0.45 : 1)
        .padding(.vertical, 1)
    }

    // MARK: - Naechste Termine

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing4) {
            SectionHeader(title: "Als Nächstes")

            ForEach(comingUp) { item in
                HStack(spacing: Metrics.spacing8) {
                    Circle()
                        .fill(Palette.eventColor(key: item.event.colorKey))
                        .frame(width: 4, height: 4)
                        .padding(.leading, 6)
                    Text(item.event.title)
                        .font(Typo.caption)
                        .foregroundStyle(
                            item.daysAway <= 1 ? Palette.textPrimary : Palette.textSecondary
                        )
                        .lineLimit(1)
                    Spacer(minLength: Metrics.spacing6)
                    Text(item.shortLabel)
                        .font(Typo.chip)
                        .monospacedDigit()
                        .foregroundStyle(
                            item.daysAway <= 1 ? Palette.textPrimary : Palette.textTertiary
                        )
                }
            }
        }
    }

    // MARK: - Aktionen

    private var actions: some View {
        HStack(spacing: Metrics.spacing8) {
            Button("Öffnen") { openApp() }
                .buttonStyle(.pressable)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .expandedHitArea(6)

            Spacer()

            Button("Neuer Eintrag") {
                openApp()
                model.newEntry()
            }
            .buttonStyle(.pressable)
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)
            .expandedHitArea(6)
        }
    }

    /// Holt das Fenster nach vorn. Aus der Menueleiste heraus ist die App zwar
    /// aktiv, ihr Fenster aber oft hinter allem anderen.
    private func openApp() {
        openWindow(id: PlanerApp.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func todayLabel(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter.string(from: day.date)
    }

    /// Termine und Aufgaben in einer Liste - fuer die Anzeige ist der
    /// Unterschied nur die Form des Kaestchens.
    private struct TodayItem: Identifiable {
        let id: UUID
        let title: String
        let detail: String?
        let tint: Color
        let isRound: Bool
    }
}
