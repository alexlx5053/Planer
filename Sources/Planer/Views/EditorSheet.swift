import PlanerCore
import PlanerData
import SwiftUI

/// Anlegen und Bearbeiten von Aufgaben und Ereignissen. (Spezifikation 4.16)
struct EditorSheet: View {
    let model: AppModel
    let target: EditorTarget

    @Environment(\.closePanel) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var kind: NewEntryKind = .event
    @State private var title = ""
    @State private var date: DateKey = .today
    @State private var hasTime = false
    @State private var time = Date()
    /// Dauer in Minuten; 0 bedeutet „nicht angegeben".
    @State private var durationMinutes = 0
    @State private var colorKey = "stone"
    @State private var notes = ""
    @State private var recurrence: Recurrence = .none
    @State private var weekdays: Set<Int> = []
    @State private var months: Set<Int> = []
    @State private var priority: Priority = .normal
    @State private var habitStart: DateKey = .today
    @State private var loaded = false
    /// Der Stand direkt nach dem Laden - daran erkennt das Blatt, ob etwas
    /// geaendert wurde.
    @State private var initialSignature: String?
    /// Wurde daneben geklickt, obwohl der Titel fehlt?
    @State private var showsTitleHint = false

    private var isNew: Bool {
        switch target {
        case .newTask, .newEvent, .newEventAt, .newHabit: true
        // Kurse landen im Kursblatt, nicht hier.
        case .task, .event, .habit, .newCourse, .course: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Passt das Blatt nicht ins Fenster, scrollen die Felder - Kopf und
            // Knoepfe bleiben stehen.
            ViewThatFits(in: .vertical) {
                fields
                ScrollView { fields }.scrollIndicators(.never)
            }
            Divider().overlay(Palette.border)
            footer
        }
        .frame(width: 420)
        .background(Palette.surface)
        .onAppear(perform: loadOnce)
        .onChange(of: model.editorCloseRequest) { _, _ in closeFromOutside() }
    }

    /// Alles, was im Blatt eingestellt ist, als eine Zeichenkette.
    private var signature: String {
        [
            kind.rawValue, title, date.rawValue, "\(hasTime)",
            hasTime ? Self.formatTime(time) : "", "\(durationMinutes)", colorKey, notes,
            recurrence.rawValue, "\(weekdays.sorted())", "\(months.sorted())", priority.rawValue,
        ].joined(separator: "|")
    }

    // MARK: - Felder

    private var fields: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing16) {
            if isNew {
                Picker("", selection: $kind) {
                    // Kurse fehlen hier mit Absicht: Sie haben ihr eigenes
                    // Blatt, weil sie andere Felder brauchen.
                    ForEach(NewEntryKind.sheetKinds, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            TextField("Titel", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.pageTitle)
                .foregroundStyle(Palette.textPrimary)
                .focused($titleFocused)

            titleHint

            Divider().overlay(Palette.border)

            if kind == .habit {
                // Eine Gewohnheit hat kein waehlbares Datum und keine
                // Wiederholung: Sie gilt jeden Tag ab dem Anlegen. Der Hinweis
                // sagt das ausdruecklich, damit niemand raetselt, warum sich
                // vergangene Tage nicht veraendert haben.
                Label(habitScopeText, systemImage: "repeat")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                LabeledRow("Datum") {
                    DateField(date: $date)
                }

                if case .task(let existing) = target {
                    postponeRow(existing)
                }
            }

            if kind == .event {
                LabeledRow("Uhrzeit") {
                    HStack(spacing: Metrics.spacing12) {
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .disabled(!hasTime)
                            .opacity(hasTime ? 1 : 0.35)

                        Toggle("ganztägig", isOn: Binding(
                            get: { !hasTime },
                            set: { hasTime = !$0 }
                        ))
                        .toggleStyle(.checkbox)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                    }
                }

                LabeledRow("Dauer") {
                    Picker("", selection: $durationMinutes) {
                        ForEach(Self.durationOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150, alignment: .leading)
                    .disabled(!hasTime)
                    .opacity(hasTime ? 1 : 0.35)
                }

                occupancySection

                LabeledRow("Farbe") {
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
            } else if kind == .task {
                LabeledRow("Priorität") {
                    Picker("", selection: $priority) {
                        Text("Niedrig").tag(Priority.low)
                        Text("Normal").tag(Priority.normal)
                        Text("Hoch").tag(Priority.high)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if kind != .habit {
            LabeledRow("Wiederholung") {
                Picker("", selection: $recurrence) {
                    ForEach(Recurrence.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180, alignment: .leading)
                .onChange(of: recurrence) { _, new in
                    if new == .quarterly && months.isEmpty {
                        months = TaskItem.defaultQuarterMonths
                    }
                }
            }
            }

            if recurrence == .weekly {
                weekdayPicker
            }
            if recurrence == .monthly || recurrence == .quarterly {
                monthPicker
            }

            if kind == .event {
                VStack(alignment: .leading, spacing: Metrics.spacing6) {
                    SectionHeader(title: "Notizen")
                    TextEditor(text: $notes)
                        .font(Typo.body)
                        .foregroundStyle(Palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .frame(height: 56)
                        .padding(Metrics.spacing6)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1)
                        )
                }
            }
        }
        .padding(Metrics.spacing20)
    }

    /// Schnelles Weiterschieben, ohne das Datum von Hand zu setzen.
    ///
    /// Bei einer Wiederholung wandert nur dieses eine Vorkommen - das steht
    /// ausdruecklich dabei, sonst muesste man es ausprobieren.
    @ViewBuilder
    private func postponeRow(_ task: TaskItem) -> some View {
        LabeledRow("Verschieben") {
            VStack(alignment: .leading, spacing: Metrics.spacing4) {
                HStack(spacing: Metrics.spacing4) {
                    postponeButton("Morgen", days: 1, task: task)
                    postponeButton("Übermorgen", days: 2, task: task)
                    postponeButton("+1 Woche", days: 7, task: task)
                }
                if task.recurrence != .none {
                    Text("Nur dieses Vorkommen, die Wiederholung bleibt.")
                        .font(Typo.chip)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private func postponeButton(_ label: String, days: Int, task: TaskItem) -> some View {
        Button(label) {
            model.move(task: task, by: days)
            dismiss()
        }
        .buttonStyle(.pressable)
        .font(Typo.chip)
        .foregroundStyle(Palette.textSecondary)
        .padding(.vertical, 4)
        .padding(.horizontal, Metrics.spacing6)
        .background(
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .fill(Palette.surfaceRaised)
        )
    }

    /// Wochentage in der Reihenfolge, in der man sie liest - die Datenhaltung
    /// zaehlt ab Sonntag, angezeigt wird ab Montag.
    private var weekdayPicker: some View {
        LabeledRow("Wochentage") {
            HStack(spacing: Metrics.spacing4) {
                ForEach(Array([1, 2, 3, 4, 5, 6, 0].enumerated()), id: \.offset) { index, weekday in
                    toggleChip(
                        MiniCalendar.weekdayNames[index],
                        isOn: weekdays.contains(weekday)
                    ) {
                        if weekdays.contains(weekday) { weekdays.remove(weekday) }
                        else { weekdays.insert(weekday) }
                    }
                }
            }
        }
    }

    private var monthPicker: some View {
        LabeledRow("Monate") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(1...12, id: \.self) { month in
                    toggleChip(Self.monthAbbreviations[month - 1], isOn: months.contains(month)) {
                        if months.contains(month) { months.remove(month) } else { months.insert(month) }
                    }
                }
            }
        }
    }

    private func toggleChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
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

    // MARK: - Fusszeile

    private var footer: some View {
        HStack(spacing: Metrics.spacing8) {
            if !isNew {
                Button("Löschen", role: .destructive) {
                    deleteCurrent()
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

    /// `onAppear` kann mehrfach feuern - der Entwurf darf dabei nicht wieder auf
    /// den gespeicherten Stand zurueckfallen.
    private func loadOnce() {
        guard !loaded else { return }
        loaded = true

        switch target {
        case .newTask(let day):
            kind = .task
            date = day
        case .newEvent(let day):
            kind = .event
            date = day
            hasTime = true
            time = Self.nextFullHour()
            durationMinutes = EventItem.assumedDuration
        case .newEventAt(let day, let clock):
            // Aus einer Luecke im Stundenplan heraus angelegt - die Uhrzeit
            // stand da schon fest.
            kind = .event
            date = day
            hasTime = true
            time = CourseEditor.date(from: clock)
            durationMinutes = EventItem.assumedDuration
        case .newHabit:
            kind = .habit
            habitStart = .today
        case .habit(let item):
            kind = .habit
            title = item.title
            habitStart = item.startDate
        case .task(let item):
            kind = .task
            title = item.title
            date = item.startDate
            recurrence = item.recurrence
            weekdays = item.weekdays
            months = item.months
            priority = item.priority
        case .event(let item):
            kind = .event
            title = item.title
            date = item.startDate
            recurrence = item.recurrence
            weekdays = item.weekdays
            months = item.months
            colorKey = item.colorKey
            notes = item.notes
            if let raw = item.time, let parsed = Self.parseTime(raw) {
                hasTime = true
                time = parsed
            }
            durationMinutes = item.durationMinutes ?? 0

        case .newCourse, .course:
            // Kann nicht vorkommen: Dafuer oeffnet `CourseEditor`.
            break
        }
        titleFocused = true
        // Erst im naechsten Durchlauf: Dann stehen alle eben gesetzten Werte
        // fest, und die Signatur beschreibt den geladenen Stand.
        DispatchQueue.main.async { initialSignature = signature }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch (kind, target) {
        case (.habit, .habit(let existing)):
            var item = existing
            item.title = trimmed
            // Das Startdatum bleibt, wie es ist: Eine Umbenennung darf die
            // Historie nicht verschieben.
            model.save(habit: item, isNew: false)

        case (.habit, _):
            model.save(habit: HabitItem(title: trimmed), isNew: true)

        case (.task, .task(let existing)):
            var item = existing
            apply(to: &item, title: trimmed)
            model.save(task: item, isNew: false)

        case (.event, .event(let existing)):
            var item = existing
            apply(to: &item, title: trimmed)
            model.save(event: item, isNew: false)

        case (.task, _):
            var item = TaskItem(title: trimmed, startDate: date)
            apply(to: &item, title: trimmed)
            model.save(task: item, isNew: true)

        case (.event, _):
            var item = EventItem(title: trimmed, startDate: date)
            apply(to: &item, title: trimmed)
            model.save(event: item, isNew: true)

        case (.course, _):
            // Kann nicht vorkommen - dieses Blatt bietet die Art nicht an.
            break
        }
        dismiss()
    }

    private func apply(to item: inout TaskItem, title: String) {
        item.title = title
        item.startDate = date
        item.recurrence = recurrence
        item.weekdays = recurrence == .weekly ? weekdays : []
        item.months = (recurrence == .monthly || recurrence == .quarterly) ? months : []
        item.priority = priority
    }

    private func apply(to item: inout EventItem, title: String) {
        item.title = title
        item.startDate = date
        item.recurrence = recurrence
        item.weekdays = recurrence == .weekly ? weekdays : []
        item.months = (recurrence == .monthly || recurrence == .quarterly) ? months : []
        item.colorKey = colorKey
        item.notes = notes
        item.time = hasTime ? Self.formatTime(time) : nil
        item.durationMinutes = (hasTime && durationMinutes > 0) ? durationMinutes : nil
    }

    private func deleteCurrent() {
        switch target {
        case .task(let item): model.delete(task: item)
        case .event(let item): model.delete(event: item)
        case .habit(let item): model.delete(habit: item)
        default: break
        }
    }

    /// „Gilt ab heute" bzw. „Gilt seit …" - je nachdem, ob sie gerade entsteht.
    private var habitScopeText: String {
        isNew
            ? "Gilt ab heute, dann täglich"
            : "Gilt seit \(DateField.format(habitStart)), täglich"
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

    // MARK: - Uhrzeit

    static func parseTime(_ raw: String) -> Date? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return ldCalendar.date(from: DateComponents(hour: hour, minute: minute))
    }

    /// Die naechste volle Stunde - eine Vorgabe, die haeufiger stimmt als
    /// „jetzt gerade" und die man mit einem Tastendruck aendert.
    static func nextFullHour(from date: Date = Date()) -> Date {
        let hour = ldCalendar.component(.hour, from: date)
        return ldCalendar.date(from: DateComponents(hour: min(hour + 1, 23), minute: 0)) ?? date
    }

    static func formatTime(_ date: Date) -> String {
        let parts = ldCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static let monthAbbreviations = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
                                     "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    /// Die Dauern, die man tatsaechlich braucht - keine freie Eingabe.
    ///
    /// Eine Minutenzahl einzutippen waere genauer und langsamer. Wer wirklich
    /// 37 Minuten meint, meint eine Dreiviertelstunde.
    static let durationOptions: [(label: String, value: Int)] = [
        ("ohne Angabe", 0),
        ("15 Minuten", 15),
        ("30 Minuten", 30),
        ("45 Minuten", 45),
        ("1 Stunde", 60),
        ("1,5 Stunden", 90),
        ("2 Stunden", 120),
        ("3 Stunden", 180),
        ("halber Tag", 240),
    ]

    // MARK: - Belegung
    //
    // Der Abschnitt, der die Frage beantwortet: Passt das ueberhaupt?
    //
    // Er erscheint nur, wenn ein Stundenplan existiert. Ohne Kurse gaebe es
    // nichts, womit sich etwas ueberschneiden koennte - dann waere der Streifen
    // eine leere Zeile, die bei jedem Termin Platz kostet.

    /// Die geplante Zeitspanne, so wie sie gerade im Blatt steht.
    private var plannedSpan: TimeSpan? {
        guard kind == .event, hasTime else { return nil }
        let clock = CourseEditor.clock(from: time)
        return TimeSpan(
            start: clock,
            minutes: durationMinutes > 0 ? durationMinutes : EventItem.assumedDuration
        )
    }

    private var editedID: UUID? {
        if case .event(let item) = target { return item.id }
        return nil
    }

    private var busyBlocks: [BusyBlock] {
        model.store.busyBlocks(on: date).filter { $0.id != editedID }
    }

    private var conflicts: [BusyBlock] {
        guard let plannedSpan else { return [] }
        return busyBlocks.filter { $0.span.overlaps(plannedSpan) }
    }

    /// Das gezeigte Fenster: der planbare Tag, bei Bedarf erweitert.
    private var railWindow: TimeSpan {
        var start = DashboardState.plannableDay.start
        var end = DashboardState.plannableDay.end
        for span in busyBlocks.map(\.span) + [plannedSpan].compactMap({ $0 }) {
            start = min(start, span.start)
            end = max(end, span.end)
        }
        return TimeSpan(start: start.flooredToHour, end: end.ceiledToHour)
    }

    @ViewBuilder
    private var occupancySection: some View {
        if model.hasCourses, hasTime {
            VStack(alignment: .leading, spacing: Metrics.spacing6) {
                SectionHeader(title: "Belegung")

                DayRail(
                    window: railWindow,
                    blocks: busyBlocks,
                    planned: plannedSpan,
                    hasConflict: !conflicts.isEmpty
                )

                if let first = conflicts.first {
                    Label(
                        conflicts.count > 1
                            ? "Überschneidet \(first.label) (\(first.span.text)) und \(conflicts.count - 1) weitere"
                            : "Überschneidet \(first.label) (\(first.span.text))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(Typo.chip)
                    .foregroundStyle(Palette.urgent)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Die Zeit ist frei", systemImage: "checkmark")
                        .font(Typo.chip)
                        .foregroundStyle(Palette.textTertiary)
                }

                freeSlotChips
            }
        }
    }

    /// Freie Luecken zum Anklicken.
    ///
    /// Der kuerzeste Weg von „passt nicht" zu „passt": Statt die Uhrzeit zu
    /// erraten und nachzusehen, nimmt man eine Luecke, die lang genug ist. Nur
    /// solche werden angeboten - ein Vorschlag, in den der Termin nicht
    /// hineinpasst, waere keiner.
    @ViewBuilder
    private var freeSlotChips: some View {
        let needed = durationMinutes > 0 ? durationMinutes : EventItem.assumedDuration
        let slots = model.store
            .freeSlots(on: date, minimumMinutes: max(needed, 15))
            .filter { $0.minutes >= needed }

        if !slots.isEmpty {
            HStack(spacing: Metrics.spacing4) {
                Text("frei")
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)

                ForEach(Array(slots.prefix(5).enumerated()), id: \.offset) { _, slot in
                    Button {
                        time = CourseEditor.date(from: slot.start)
                    } label: {
                        Text(DashboardView.slotLabel(slot))
                            .font(Typo.chip)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Metrics.spacing6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                                    .fill(Palette.surfaceRaised)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable(scale: 0.94))
                    .help("Beginn auf \(slot.start.text) setzen")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Beschriftete Zeile

private struct LabeledRow<Content: View>: View {
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
