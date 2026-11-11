import PlanerCore
import SwiftUI

/// Anlegen und Bearbeiten eines Kurses.
///
/// Ein eigenes Blatt, nicht die vierte Spalte im Bearbeiten-Blatt der Termine:
/// Ein Kurs hat keinen Tag, sondern einen Wochentag, keine Uhrzeit, sondern eine
/// Zeitspanne, dazu Raum, Dozent und ein Semester. Das in ein Formular zu
/// zwingen, das fuer Termine gebaut ist, haette beide unleserlich gemacht.
struct CourseEditor: View {
    let model: AppModel
    let target: EditorTarget

    @Environment(\.closePanel) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var kind: CourseKind = .lecture
    @State private var weekday = 1
    @State private var start = Date()
    @State private var end = Date()
    @State private var room = ""
    @State private var lecturer = ""
    @State private var colorKey = "stone"
    @State private var weeks: WeekPattern = .every
    @State private var firstDay: DateKey = .today
    @State private var lastDay: DateKey = .today
    @State private var loaded = false
    /// Der Stand direkt nach dem Laden - daran erkennt das Blatt, ob etwas
    /// geaendert wurde.
    @State private var initialSignature: String?
    /// Wurde daneben geklickt, obwohl der Titel fehlt?
    @State private var showsTitleHint = false

    private var isNew: Bool {
        if case .newCourse = target { return true }
        return false
    }

    private var existing: CourseItem? {
        if case .course(let item) = target { return item }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                fields
                ScrollView { fields }.scrollIndicators(.never)
            }
            Divider().overlay(Palette.border)
            footer
        }
        .frame(width: 440)
        .background(Palette.surface)
        .onAppear(perform: loadOnce)
        .onChange(of: model.editorCloseRequest) { _, _ in closeFromOutside() }
    }

    /// Alles, was im Blatt eingestellt ist, als eine Zeichenkette.
    private var signature: String {
        [
            title, kind.rawValue, "\(weekday)", startClock.text, endClock.text, room, lecturer,
            colorKey, weeks.rawValue, firstDay.rawValue, lastDay.rawValue,
        ].joined(separator: "|")
    }

    // MARK: - Felder

    private var fields: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing12) {
            TextField("Modul oder Kurs", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.pageTitle)
                .foregroundStyle(Palette.textPrimary)
                .focused($titleFocused)

            titleHint

            Divider().overlay(Palette.border)

            CourseRow("Art") {
                Picker("", selection: $kind) {
                    ForEach(CourseKind.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170, alignment: .leading)
            }

            CourseRow("Tag") {
                HStack(spacing: Metrics.spacing4) {
                    // Angezeigt ab Montag, gespeichert ab Sonntag - dieselbe
                    // Umrechnung wie im Rest der App.
                    ForEach(Array([1, 2, 3, 4, 5, 6, 0].enumerated()), id: \.offset) { index, value in
                        dayChip(MiniCalendar.weekdayNames[index], isOn: weekday == value) {
                            weekday = value
                        }
                    }
                }
            }

            CourseRow("Zeit") {
                HStack(spacing: Metrics.spacing6) {
                    DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)

                    Text("bis")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textTertiary)

                    DatePicker("", selection: $end, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)

                    Text(durationText)
                        .font(Typo.chip)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            CourseRow("Woche") {
                Picker("", selection: $weeks) {
                    ForEach(WeekPattern.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            CourseRow("Raum") {
                TextField("z. B. H 12", text: $room)
                    .textFieldStyle(.roundedBorder)
                    .font(Typo.caption)
                    .frame(maxWidth: 140)
            }

            CourseRow("Dozent") {
                TextField("optional", text: $lecturer)
                    .textFieldStyle(.roundedBorder)
                    .font(Typo.caption)
                    .frame(maxWidth: 200)
            }

            CourseRow("Farbe") {
                HStack(spacing: Metrics.spacing8) {
                    ForEach(Palette.eventPalette, id: \.key) { entry in
                        Button { colorKey = entry.key } label: {
                            Circle()
                                .fill(entry.color)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            colorKey == entry.key ? Palette.accent : Palette.border,
                                            lineWidth: colorKey == entry.key ? 2 : 1
                                        )
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.pressable(scale: 0.82))
                        .expandedHitArea(5)
                        .help(entry.name)
                    }
                    Spacer()
                }
            }

            Divider().overlay(Palette.border)

            semesterSection

            if let hint = conflictHint {
                Label(hint, systemImage: "exclamationmark.triangle")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.urgent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.spacing20)
    }

    /// Der Semesterzeitraum.
    ///
    /// Er steht unten und vorbelegt: Beim ersten Kurs mit dem laufenden
    /// Semester, bei jedem weiteren mit dem Zeitraum des vorherigen. So tippt
    /// man ihn einmal und nicht zehnmal - und sieht trotzdem, was gilt.
    private var semesterSection: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing6) {
            CourseRow("Semester") {
                HStack(spacing: Metrics.spacing6) {
                    DateField(date: $firstDay, showsRelativeHint: false)
                    Text("bis")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textTertiary)
                    DateField(date: $lastDay, showsRelativeHint: false)
                }
            }

            Text("Außerhalb dieses Zeitraums erscheint der Kurs nicht - nach dem Semester "
                 + "verschwindet er von selbst.")
                .font(Typo.chip)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 84 + Metrics.spacing12)
        }
    }

    private func dayChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typo.chip)
                .foregroundStyle(isOn ? Palette.onAccent : Palette.textSecondary)
                .frame(minWidth: 26)
                .padding(.vertical, 4)
                .padding(.horizontal, 5)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .fill(isOn ? Palette.accent : Palette.surfaceRaised)
                )
        }
        .buttonStyle(.pressable(scale: 0.9))
    }

    // MARK: - Zeitlogik

    private var startClock: ClockTime { Self.clock(from: start) }
    private var endClock: ClockTime { Self.clock(from: end) }

    private var durationText: String {
        let minutes = max(endClock.minutes - startClock.minutes, 0)
        guard minutes > 0 else { return "" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours):\(String(format: "%02d", rest)) h"
    }

    /// Der Anfang - und das Ende wandert mit.
    ///
    /// Ohne das muesste man beide Felder nachziehen, nur weil die Vorlesung eine
    /// Stunde spaeter liegt, und ein Ende vor dem Anfang waere nebenbei auch
    /// moeglich.
    ///
    /// Bewusst ein eigenes Binding statt `onChange`: `onChange` feuert auch,
    /// wenn das Blatt seine Werte zum ersten Mal setzt - das Ende wuerde dann
    /// um die Differenz zur Uhrzeit des Oeffnens verschoben, und ein Kurs von
    /// 08:15 endete um Mitternacht. Das Binding greift nur bei echter Eingabe.
    private var startBinding: Binding<Date> {
        Binding(
            get: { start },
            set: { new in
                let delta = Self.clock(from: new).minutes - Self.clock(from: start).minutes
                start = new
                if delta != 0 {
                    end = Self.date(from: Self.clock(from: end).adding(minutes: delta))
                }
            }
        )
    }

    /// Ueberschneidung mit einem anderen Kurs an diesem Wochentag.
    ///
    /// Nur Kurse, nicht Termine: Ein Termin, der mit einer neuen Vorlesung
    /// kollidiert, ist ein Termin, den man verschiebt - zwei Vorlesungen
    /// gleichzeitig sind ein Tippfehler.
    private var conflictHint: String? {
        let span = TimeSpan(start: startClock, end: endClock)
        let clashes = model.store.state.courses
            .filter { $0.id != existing?.id }
            .filter { $0.weekday == weekday }
            .filter { $0.weeks == .every || weeks == .every || $0.weeks == weeks }
            .filter { $0.span.overlaps(span) }
            .filter { $0.firstDay <= lastDay && $0.lastDay >= firstDay }

        guard let first = clashes.first else { return nil }
        let more = clashes.count > 1 ? " und \(clashes.count - 1) weiteren" : ""
        return "Überschneidet sich mit \(first.title) (\(first.span.text))\(more)."
    }

    // MARK: - Fusszeile

    private var footer: some View {
        HStack(spacing: Metrics.spacing8) {
            if let course = existing {
                Button("Löschen", role: .destructive) {
                    model.delete(course: course)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Abbrechen") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button("Sichern") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Metrics.spacing16)
    }

    // MARK: - Laden und Sichern

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true

        switch target {
        case .newCourse(let day, let time):
            let semester = model.store.semesterForNewCourse
            weekday = day
            start = Self.date(from: time)
            // Neunzig Minuten: das akademische Standardmass.
            end = Self.date(from: time.adding(minutes: 90))
            firstDay = semester.firstDay
            lastDay = semester.lastDay
            colorKey = Self.nextColorKey(after: model.store.state.courses.last?.colorKey)

        case .course(let item):
            title = item.title
            kind = item.kind
            weekday = item.weekday
            start = Self.date(from: item.start)
            end = Self.date(from: item.end)
            room = item.room
            lecturer = item.lecturer
            colorKey = item.colorKey
            weeks = item.weeks
            firstDay = item.firstDay
            lastDay = item.lastDay

        default:
            break
        }
        titleFocused = true
        DispatchQueue.main.async { initialSignature = signature }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var item = existing ?? CourseItem(title: trimmed)
        item.title = trimmed
        item.kind = kind
        item.weekday = weekday
        item.start = startClock
        // Ein Ende vor dem Anfang ergibt keinen Kurs - dann gilt die
        // Standarddauer.
        item.end = endClock > startClock ? endClock : startClock.adding(minutes: 90)
        item.room = room.trimmingCharacters(in: .whitespaces)
        item.lecturer = lecturer.trimmingCharacters(in: .whitespaces)
        item.colorKey = colorKey
        item.weeks = weeks
        item.firstDay = min(firstDay, lastDay)
        item.lastDay = max(firstDay, lastDay)

        model.save(course: item, isNew: existing == nil)
        dismiss()
    }

    // MARK: - Klick daneben

    /// Was ein Klick neben das Blatt bedeutet.
    ///
    /// - Nichts geaendert: schliessen.
    /// - Etwas geaendert und vollstaendig: uebernehmen und schliessen - wie
    ///   ein Termin im Kalender von Apple. Verwerfen geht mit „Abbrechen".
    /// - Etwas geaendert, aber ohne Titel: offen bleiben. Ohne Titel laesst
    ///   sich nichts sichern, und das Geschriebene einfach wegzuwerfen waere
    ///   der eine Fehler, der hier nicht passieren darf.
    private func closeFromOutside() {
        guard let initialSignature, signature != initialSignature else {
            dismiss()
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showsTitleHint = true
            titleFocused = true
            return
        }
        save()
    }

    @ViewBuilder
    private var titleHint: some View {
        if showsTitleHint && title.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Titel fehlt – ohne ihn lässt sich nichts sichern. Verwerfen mit „Abbrechen“.")
                .font(Typo.chip)
                .foregroundStyle(Palette.urgent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Umrechnung

    static func clock(from date: Date) -> ClockTime {
        let parts = ldCalendar.dateComponents([.hour, .minute], from: date)
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    static func date(from clock: ClockTime) -> Date {
        ldCalendar.date(from: DateComponents(hour: clock.hour, minute: clock.minute)) ?? Date()
    }

    /// Reiht die Farben durch, statt jedem Kurs dieselbe zu geben.
    ///
    /// Ein Stundenplan, in dem alle Bloecke gleich aussehen, ist ein Raster
    /// ohne Information. Von Hand waehlen kann man weiterhin.
    static func nextColorKey(after previous: String?) -> String {
        let keys = Palette.eventPalette.map(\.key)
        guard let previous, let index = keys.firstIndex(of: previous) else { return keys[0] }
        return keys[(index + 1) % keys.count]
    }
}

// MARK: - Beschriftete Zeile

/// Wie `LabeledRow` im Bearbeiten-Blatt, mit derselben Beschriftungsbreite -
/// die beiden Blaetter sollen gleich aussehen, auch wenn sie nicht dieselben
/// Felder haben.
private struct CourseRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spacing12) {
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 84, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}
