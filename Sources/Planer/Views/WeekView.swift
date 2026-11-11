import PlanerCore
import PlanerData
import SwiftUI

/// Die Woche in sieben Spalten, montagsbeginnend.
///
/// Bewusst gedraengter als die Tagesansicht: Hier geht es um den Ueberblick,
/// nicht um Einzelheiten. Gewohnheiten stehen deshalb nur als Zaehler da -
/// zehn Gewohnheiten mal sieben Tage waeren siebzig Zeilen, die niemand liest.
struct WeekView: View {
    @Bindable var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: StateStore { model.store }

    private var days: [DateKey] {
        let monday = model.selectedDate.startOfWeek
        return (0..<7).map { monday.adding(days: $0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.spacing8) {
            ForEach(days, id: \.self) { day in
                column(for: day)
            }
        }
    }

    private func column(for day: DateKey) -> some View {
        let agenda = store.agenda(for: day)
        let stats = store.stats(for: day)
        let isSelected = day == model.selectedDate

        return VStack(alignment: .leading, spacing: Metrics.spacing6) {
            header(day: day, stats: stats)

            if agenda.events.isEmpty && agenda.tasks.isEmpty && agenda.courses.isEmpty {
                Text(agenda.isVacation ? "Urlaub" : "—")
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, 2)
            }

            // Der Stundenplan steht oben in der Spalte und ohne Kaestchen: Er
            // ist gesetzt, nicht zu erledigen.
            ForEach(agenda.courses) { course in
                courseLine(course)
            }

            if !agenda.courses.isEmpty, !agenda.events.isEmpty || !agenda.tasks.isEmpty {
                Divider().overlay(Palette.border).padding(.vertical, 1)
            }

            ForEach(agenda.events) { event in
                compactRow(
                    title: event.title,
                    detail: event.time,
                    tint: Palette.eventColor(key: event.colorKey),
                    shape: .round,
                    isDone: store.isDone(event.id, on: day),
                    toggle: { store.toggleCompletion(event.id, on: day) },
                    edit: { model.edit(event: event) }
                )
            }

            ForEach(agenda.tasks) { task in
                compactRow(
                    title: task.title,
                    detail: nil,
                    tint: task.priority == .high ? Palette.urgent : Palette.accent,
                    shape: .square,
                    isDone: store.isDone(task.id, on: day),
                    toggle: { store.toggleCompletion(task.id, on: day) },
                    edit: { model.edit(task: task) }
                )
            }

            // Gewohnheiten zum Abhaken, nicht nur als Zaehler: Wer am Abend die
            // Woche durchgeht, will gestern nachtragen koennen, ohne erst in den
            // Tag zu wechseln.
            if !agenda.habits.isEmpty {
                Divider().overlay(Palette.border).padding(.vertical, 2)

                HStack(spacing: 0) {
                    Text("Gewohnheiten")
                    Spacer(minLength: 2)
                    Text("\(stats.habitsDone)/\(stats.habitsTotal)")
                        .monospacedDigit()
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(
                    stats.habitsDone == stats.habitsTotal ? Palette.perfect : Palette.textTertiary
                )
                .padding(.horizontal, 2)

                ForEach(agenda.habits) { habit in
                    compactRow(
                        title: habit.title,
                        detail: nil,
                        tint: Palette.accent,
                        shape: .round,
                        isDone: store.isDone(habit.id, on: day),
                        toggle: { store.toggleCompletion(habit.id, on: day) },
                        edit: { model.edit(habit: habit) }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.spacing8)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .cardSurface(radius: Metrics.controlRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent.opacity(0.55) : .clear, lineWidth: 1.5)
        )
        .animation(Motion.snappy(reduced: reduceMotion), value: isSelected)
    }

    // MARK: - Spaltenkopf

    private func header(day: DateKey, stats: DayStats) -> some View {
        Button {
            model.selectedDate = day
            model.viewMode = .day
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Metrics.spacing4) {
                    Text(Self.weekdayShort(day))
                        .font(Typo.chip)
                        .foregroundStyle(day == store.today ? Palette.accent : Palette.textTertiary)

                    // Heute in der hellen Kapsel - dasselbe Zeichen wie im
                    // Stundenplan und im Kalender links.
                    Text("\(day.day)")
                        .font(.system(size: 13, weight: day == store.today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(
                            day == store.today ? Palette.onAccent
                                : holidayName(day) != nil ? Palette.urgent : Palette.textPrimary
                        )
                        .padding(.horizontal, day == store.today ? 6 : 0)
                        .background(Capsule().fill(day == store.today ? Palette.accent : .clear))

                    Spacer(minLength: 0)

                    if stats.isPerfect {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.perfect)
                    }
                }

                if let holiday = holidayName(day) {
                    Text(holiday)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.urgent)
                        .lineLimit(1)
                }

                // Ein Balken statt eines Rings: In einer schmalen Spalte liest
                // sich der Fortschritt waagerecht besser.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.border)
                        Capsule()
                            .fill(stats.isPerfect ? Palette.perfect : Palette.accent)
                            .frame(width: geometry.size.width * stats.fraction)
                    }
                }
                .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.97))
        .help("Diesen Tag öffnen")
    }

    private func holidayName(_ day: DateKey) -> String? { Holidays.name(on: day) }

    // MARK: - Veranstaltung

    private func courseLine(_ course: CourseItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(course.span.text)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
            Text(course.title)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Metrics.accentStripWidth + Metrics.spacing6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Der Streifen liegt auf der Zeile statt neben ihr. Als Geschwister im
        // Stapel waere er in der Hoehe flexibel und zoege den freien Platz der
        // Spalte an sich - der Strich reichte dann weit unter seinen Text.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                .fill(Palette.eventColor(key: course.colorKey))
                .frame(width: Metrics.accentStripWidth)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.edit(course: course) }
        .help(course.spokenDescription)
    }

    // MARK: - Gedraengte Zeile

    private func compactRow(
        title: String,
        detail: String?,
        tint: Color,
        shape: CheckToggle.Shape,
        isDone: Bool,
        toggle: @escaping () -> Void,
        edit: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Metrics.spacing6) {
            CheckToggle(isOn: isDone, shape: shape, tint: tint, label: title, action: toggle)
                .scaleEffect(0.82)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(isDone, color: Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(isDone ? 0.45 : 1)
        // Wie in der Tagesansicht: Das Kaestchen hakt ab, der Text oeffnet
        // den Eintrag. Das Kaestchen gewinnt, weil seine Geste innen liegt.
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .help("Klicken zum Bearbeiten")
    }

    static func weekdayShort(_ day: DateKey) -> String {
        MiniCalendar.weekdayNames[(day.weekdayIndex + 6) % 7]
    }
}
