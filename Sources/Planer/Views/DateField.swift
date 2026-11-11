import PlanerCore
import SwiftUI

/// Datumsauswahl im Bearbeiten-Blatt. (Spezifikation 4.20)
///
/// Aufbau wie im Kalender von macOS: ein natives, tippbares Datumsfeld, daneben
/// ein Knopf, der ein Monatsraster aufklappt.
///
/// Das Feld ist bewusst das System-Element und kein Nachbau. Im selben Blatt
/// stehen Klappmenue, Segmentschalter und Ankreuzfeld - allesamt native
/// Bedienelemente. Ein selbst gezeichneter Datumsknopf war dort der einzige
/// Fremdkoerper, und genau das hat man ihm angesehen. Ausserdem kann das native
/// Feld etwas, das kein Nachbau mitbringt: Man tippt das Datum, springt mit dem
/// Tabulator zwischen Tag, Monat und Jahr und aendert Werte mit den Pfeiltasten.
///
/// Das aufklappbare Monatsraster ist dagegen unseres - der Systemkalender bringt
/// eigene Farben und Abstaende mit, die im schwarzen Fenster auffallen.
struct DateField: View {
    @Binding var date: DateKey
    /// Zeigt „heute", „in 5 Tagen" neben dem Feld.
    ///
    /// Abschaltbar, weil der Hinweis nicht ueberall hilft: Beim Anfang eines
    /// Semesters ist „vor 12 Tagen" belanglos und bricht nur die Zeile um.
    var showsRelativeHint = true

    @State private var isCalendarOpen = false
    @State private var visibleMonth: DateKey = .today

    var body: some View {
        HStack(spacing: Metrics.spacing8) {
            DatePicker(
                "",
                selection: Binding(
                    get: { date.date },
                    set: { date = DateKey($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.field)
            .labelsHidden()
            .fixedSize()

            calendarButton

            if showsRelativeHint, let hint = Self.relativeHint(for: date) {
                Text(hint)
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)
                    .transition(.opacity)
            }
        }
    }

    private var calendarButton: some View {
        Button {
            visibleMonth = date
            isCalendarOpen = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 12))
                .foregroundStyle(isCalendarOpen ? Palette.accent : Palette.textSecondary)
                .frame(width: 22, height: 22)
                .expandedHitArea(5)
        }
        .buttonStyle(.pressable(scale: 0.85))
        .help("Kalender öffnen")
        .popover(isPresented: $isCalendarOpen, arrowEdge: .bottom) {
            CalendarPopover(date: $date, visibleMonth: $visibleMonth, isOpen: $isCalendarOpen)
        }
    }

    // MARK: - Beschriftung

    /// „heute", „morgen", „in 5 Tagen" - die Angabe, die man beim Planen
    /// tatsaechlich im Kopf hat.  Weiter als zwei Wochen voraus sagt sie nichts
    /// mehr aus und bleibt deshalb weg.
    static func relativeHint(for day: DateKey, today: DateKey = .today) -> String? {
        switch today.days(until: day) {
        case 0: "heute"
        case 1: "morgen"
        case 2: "übermorgen"
        case -1: "gestern"
        case let offset where offset > 2 && offset <= 14: "in \(offset) Tagen"
        case let offset where offset < -1 && offset >= -14: "vor \(-offset) Tagen"
        default: nil
        }
    }

    static func format(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EE, d. MMM yyyy"
        return formatter.string(from: day.date)
    }
}

// MARK: - Aufklappbarer Kalender

/// Das Monatsraster hinter dem Kalenderknopf.
///
/// Bewusst unser eigenes statt des grafischen System-Kalenders: Der bringt
/// blaue Systemakzente, eigene Schriftgroessen und eigene Abstaende mit, die im
/// schwarzen Fenster wie ein aufgeklebtes Fremdteil wirken. Das Verhalten ist
/// dasselbe wie bei Apple - Auswahl uebernimmt und schliesst.
struct CalendarPopover: View {
    @Binding var date: DateKey
    @Binding var visibleMonth: DateKey
    @Binding var isOpen: Bool

    var body: some View {
        VStack(spacing: Metrics.spacing12) {
            MiniCalendar(
                month: visibleMonth,
                selected: date,
                today: .today,
                mark: { _ in DayMark() },
                onSelect: { selected in
                    date = selected
                    isOpen = false
                },
                onStep: { visibleMonth = visibleMonth.adding(months: $0) },
                onToday: { visibleMonth = .today }
            )

            Divider().overlay(Palette.border)

            HStack {
                Button("Heute") {
                    date = .today
                    isOpen = false
                }
                .buttonStyle(.pressable)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .expandedHitArea(6)

                Spacer()

                Text(DateField.format(date))
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Metrics.spacing12)
        .frame(width: 248)
        .background(Palette.surface)
    }
}
