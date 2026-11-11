import PlanerCore
import PlanerData
import SwiftUI

/// Die Tagesansicht - der Bildschirm, den man jeden Morgen oeffnet.
struct DashboardView: View {
    @Bindable var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var newEntryHovering = false
    @State private var todayHovering = false

    private var store: StateStore { model.store }
    private var day: DateKey { model.selectedDate }
    private var agenda: DayAgenda { store.agenda(for: day) }

    /// Nach Suchbegriff gefiltert. Die Zaehler bleiben bewusst am ungefilterten
    /// Bestand - „2 von 3" soll den Tag beschreiben, nicht die Suche.
    private var visibleEvents: [EventItem] { agenda.events.filter { model.matches($0.title) } }
    private var visibleTasks: [TaskItem] { agenda.tasks.filter { model.matches($0.title) } }
    private var visibleHabits: [HabitItem] { agenda.habits.filter { model.matches($0.title) } }
    private var visibleCourses: [CourseItem] { agenda.courses.filter { model.matches($0.title) } }

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var stats: DayStats { store.stats(for: day) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)

            if model.isOnVacation {
                vacationBanner
                Divider().overlay(Palette.border)
            }

            HStack(spacing: 0) {
                SidebarView(model: model)
                Divider().overlay(Palette.border)
                content
            }
        }
        .background(Palette.canvas)
        // Ein Klick ins Leere beendet das Schreiben.
        //
        // Ohne das bliebe der Schreibcursor im Zettel haengen: Ein Textfeld gibt
        // die Tastatur von sich aus erst ab, wenn etwas anderes sie haben will -
        // und die schwarze Flaeche will sie nicht. Zeilen, Knoepfe und Karten
        // fangen ihren Klick vorher ab, hier kommt nur an, was daneben trifft.
        .contentShape(Rectangle())
        .onTapGesture { model.isEditingNotes = false }
        .overlay(alignment: .bottom) { undoToast }
        .onChange(of: model.selectedDate) { _, _ in model.isEditingNotes = false }
        .onChange(of: model.viewMode) { _, _ in model.isEditingNotes = false }
        .onChange(of: model.editorTarget) { _, target in
            if target != nil { model.isEditingNotes = false }
        }
        // Grosse Ansichten und Bearbeiten-Blaetter liegen als Ebene ueber dem
        // Fenster - ein Klick daneben schliesst sie.
        .overlay { PanelHost(model: model) }
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(spacing: Metrics.spacing8) {
            todayButton

            Spacer()

            if model.isSearchFieldVisible {
                searchField
            }

            headerButton("magnifyingglass", help: "Suchen (⌘F)", isActive: model.isSearchFieldVisible) {
                model.toggleSearch()
            }

            headerButton("calendar", help: "Monatsübersicht (⌘⇧M)") {
                model.showsMonthOverview = true
            }

            headerButton("beach.umbrella", help: model.isOnVacation ? "Urlaub beenden" : "Urlaub beginnen",
                         isActive: model.isOnVacation) {
                model.toggleVacation()
            }

            newEntryButton
        }
        // Platz fuer die Fensterknoepfe links - die Titelleiste ist ausgeblendet,
        // die Ampel bleibt aber an ihrem Platz.
        .padding(.leading, 80)
        .padding(.trailing, Metrics.spacing16)
        .frame(height: 46)
        .background(Palette.canvas)
    }

    /// Zeichen, Gruss und Uhr sind zusammen der Weg zurueck zu heute.
    ///
    /// Es ist die Stelle, auf die man ohnehin schaut, wenn man wissen will,
    /// „wo bin ich gerade" - und damit die naheliegendste, um wieder dorthin zu
    /// kommen. Sie sieht bewusst nicht wie ein Knopf aus; erst der Mauszeiger
    /// verraet, dass sie eine ist.
    private var todayButton: some View {
        Button {
            model.goToToday()
        } label: {
            HStack(spacing: Metrics.spacing8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.leaf)

                Text(model.greeting)
                    .font(Typo.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)

                Text(model.now, format: .dateTime.hour().minute())
                    .font(Typo.clock)
                    .foregroundStyle(Palette.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Metrics.spacing8)
            .padding(.vertical, Metrics.spacing4)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(todayHovering ? Palette.surfaceRaised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.97))
        .onHover { todayHovering = $0 }
        .accessibilityLabel("Zum heutigen Tag")
        .help("Zum heutigen Tag (⌘T)")
    }

    /// Der einzige Weg, etwas anzulegen - deshalb sichtbar abgesetzt, aber
    /// ohne Farbe: eine Flaeche mit Haarlinie genuegt, um ihn als Knopf zu
    /// lesen. Ein Klick oeffnet die zuletzt benutzte Art, der Pfeil daneben
    /// alle drei.
    private var newEntryButton: some View {
        Menu {
            ForEach(NewEntryKind.allCases, id: \.self) { kind in
                Button {
                    model.newEntry(kind: kind)
                } label: {
                    Label(kind.label, systemImage: kind.symbol)
                }
            }

            Divider()

            Button {
                model.openCapture()
            } label: {
                Label("Aus Text …", systemImage: "sparkles")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Neu")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Metrics.spacing8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(newEntryHovering ? Palette.surfaceRaised : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(newEntryHovering ? Palette.borderStrong : Palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { newEntryHovering = $0 }
        .help("Neuer Eintrag (⌘N)")
    }

    private func headerButton(_ symbol: String, help: String, isActive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Palette.accent : Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                        .fill(isActive ? Palette.accentMuted : .clear)
                )
                .expandedHitArea(5)
        }
        .buttonStyle(.pressable(scale: 0.85))
        .help(help)
    }

    private var searchField: some View {
        TextField("Suchen", text: $model.searchText)
            .textFieldStyle(.plain)
            .font(Typo.caption)
            .foregroundStyle(Palette.textPrimary)
            .focused($searchFocused)
            .frame(width: 160)
            .padding(.horizontal, Metrics.spacing8)
            .padding(.vertical, Metrics.spacing4)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Palette.surfaceRaised)
            )
            .onExitCommand { model.toggleSearch() }
            // Der Fokus laesst sich erst setzen, wenn das Feld tatsaechlich
            // existiert - direkt im Knopfdruck waere es zu frueh.
            .onAppear { searchFocused = true }
    }

    /// Hinweis auf den Urlaub - und der Weg hinaus an derselben Stelle.
    ///
    /// Er erscheint auch fuer zurueckliegende Urlaubstage. Vorher sah ein
    /// solcher Tag voellig normal aus, nur ohne Gewohnheiten und ohne alles
    /// Wiederkehrende - ohne jeden Hinweis, warum. Genau daran laesst sich lange
    /// raetseln.
    private var vacationBanner: some View {
        HStack(spacing: Metrics.spacing8) {
            Image(systemName: "beach.umbrella")
                .font(.system(size: 11))
                .foregroundStyle(Palette.accent)

            Text(vacationText)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            Button("Urlaub beenden") { model.toggleVacation() }
                .buttonStyle(.pressable)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
                .expandedHitArea(6)
        }
        .padding(.horizontal, Metrics.spacing16)
        .padding(.vertical, Metrics.spacing8)
        .background(Palette.accentMuted)
    }

    private var vacationText: String {
        guard let since = model.vacationSince else { return "Urlaubsmodus aktiv" }
        return "Urlaub seit \(DateField.format(since)) · Wiederkehrendes pausiert, die Serie läuft weiter"
    }

    /// Ein zurueckliegender Urlaubstag braucht kein Banner, aber er darf auch
    /// nicht unsichtbar sein: Sonst fehlen an diesem Tag alle Gewohnheiten und
    /// alles Wiederkehrende, ohne dass man den Grund sieht. Ein Klick hebt ihn
    /// auf.
    private var vacationChip: some View {
        Button {
            model.clearVacationOnSelectedDay()
        } label: {
            SolidChip(text: "Urlaubstag", systemImage: "beach.umbrella", tint: Palette.textSecondary)
        }
        .buttonStyle(.pressable)
        .expandedHitArea(5)
        .help("Klicken, um den Urlaubstag aufzuheben")
    }

    // MARK: - Hauptbereich

    @ViewBuilder
    private var content: some View {
        if model.viewMode == .timetable {
            // Der Stundenplan scrollt nicht, er passt sich ein: Die ganze Woche
            // soll auf einen Blick zu sehen sein.
            VStack(alignment: .leading, spacing: Metrics.spacing16) {
                title
                TimetableView(model: model)
            }
            .padding(Metrics.spacing20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.spacing16) {
                    title

                    if model.viewMode == .day {
                        // Der Stundenplan steht oben: Er ist der feste Rahmen
                        // des Tages, in den sich alles andere einfuegen muss.
                        if !agenda.courses.isEmpty {
                            coursesCard
                        }
                        eventsCard
                        tasksCard
                        habitsCard
                    } else {
                        WeekView(model: model)
                    }
                }
                .padding(Metrics.spacing20)
                .frame(maxWidth: model.viewMode == .day ? Metrics.contentWidth : .infinity)
                .frame(maxWidth: .infinity)
            }
            // Ohne Rollbalken: Gescrollt wird mit Trackpad oder Mausrad wie
            // gewohnt, aber die Schiene am Rand - die auf einem Mac mit Maus
            // dauerhaft stehen bleibt - zieht keine Linie mehr durchs Fenster.
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Motion.smooth(reduced: reduceMotion), value: day)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(subheadline)
                    .font(Typo.pageSubtitle)
                    .foregroundStyle(Palette.textSecondary)
            }

            if model.selectedDayIsVacation && !model.isOnVacation {
                vacationChip
            }

            Spacer()

            stepper

            Picker("", selection: $model.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 230)

            if stats.isPerfect && model.isToday {
                SolidChip(text: "Perfekter Tag", systemImage: "checkmark", tint: Palette.perfect)
                    .transition(.opacity)
            }
        }
    }

    /// Vor und zurueck, direkt an der Ansicht.
    ///
    /// Bisher ging das nur ueber die Tastatur oder den Kalender links. Wer mit
    /// der Maus durch die Wochen des Stundenplans will, braucht die Pfeile
    /// dort, wo er hinsieht.
    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", by: -1)
            stepButton("chevron.right", by: 1)
        }
    }

    private func stepButton(_ symbol: String, by direction: Int) -> some View {
        let unit = model.viewMode.showsWholeWeek ? "Woche" : "Tag"
        let label = direction < 0
            ? (unit == "Woche" ? "Vorherige Woche" : "Vorheriger Tag")
            : (unit == "Woche" ? "Nächste Woche" : "Nächster Tag")

        return Button {
            model.step(days: direction)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24, height: 22)
                .expandedHitArea(4)
        }
        .buttonStyle(.pressable(scale: 0.8))
        .help("\(label) (⌘\(direction < 0 ? "←" : "→"))")
        .accessibilityLabel(label)
    }

    private var headline: String {
        switch model.viewMode {
        case .day: model.isToday ? "Heute" : Self.weekdayName(day)
        case .week: day.startOfWeek == store.today.startOfWeek ? "Diese Woche" : "Woche"
        case .timetable: "Stundenplan"
        }
    }

    private var subheadline: String {
        guard model.viewMode.showsWholeWeek else { return Self.longDate(day) }
        let monday = day.startOfWeek
        let range = "\(DateField.format(monday)) – \(DateField.format(monday.adding(days: 6)))"
        // Im Stundenplan steht die Kalenderwoche dabei: Ohne sie laesst sich
        // bei zweiwoechentlichen Kursen nicht sagen, ob diese Woche gemeint ist.
        return model.viewMode == .timetable ? "KW \(monday.weekOfYear) · \(range)" : range
    }

    // MARK: - Stundenplan

    /// Der Unitag: wann welches Modul, und was dazwischen frei ist.
    ///
    /// Sie erscheint nur an Tagen mit Veranstaltungen. Eine leere Karte
    /// „Stundenplan" an einem Samstag waere eine Zeile, die jeden Samstag
    /// dasselbe sagt - und die uebrigen Karten nach unten schiebt.
    private var coursesCard: some View {
        Card(padding: Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Metrics.spacing6) {
                    SectionHeader(title: "Stundenplan")
                    Button {
                        model.viewMode = .timetable
                    } label: {
                        Text("ganze Woche")
                            .font(Typo.chip)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.pressable)
                    .expandedHitArea(6)
                    .help("Ganze Woche als Raster zeigen")
                }
                .padding(.horizontal, Metrics.spacing8)
                .padding(.bottom, Metrics.spacing6)

                ForEach(visibleCourses) { course in
                    SessionRow(
                        course: course,
                        phase: phase(of: course),
                        onEdit: { model.edit(course: course) },
                        onCancelSession: { model.cancelSession(course, on: day) },
                        onDelete: { model.delete(course: course) }
                    )
                }

                if visibleCourses.isEmpty {
                    EmptyHint(text: "Kein Treffer.")
                } else {
                    freeTimeLine
                }
            }
            .animation(Motion.smooth(reduced: reduceMotion), value: agenda.courses)
        }
    }

    /// Was zwischen den Veranstaltungen frei ist.
    ///
    /// Die eigentliche Antwort auf die Frage, die man an einem Unitag hat: Wann
    /// kann ich etwas ausmachen? Sie steht unter den Sitzungen, weil sie sich
    /// aus ihnen ergibt - und sie zaehlt nur Luecken ab einer halben Stunde,
    /// denn zehn Minuten zwischen zwei Hoersaelen sind kein Zeitfenster.
    @ViewBuilder
    private var freeTimeLine: some View {
        // Heute zaehlt nur, was noch kommt: Am Nachmittag ist „frei von acht
        // bis zehn" keine Auskunft mehr.
        let all = store.freeSlots(on: day)
        let slots = model.isToday ? all.remaining(after: nowClock) : all

        if !slots.isEmpty {
            HStack(spacing: Metrics.spacing6) {
                Text(model.isToday ? "noch frei" : "frei")
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)

                ForEach(Array(slots.prefix(4).enumerated()), id: \.offset) { _, slot in
                    Button {
                        model.newEvent(on: day, at: slot.start)
                    } label: {
                        Text(Self.slotLabel(slot))
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
                    .help("Termin um \(slot.start.text) anlegen")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.spacing8)
            .padding(.top, Metrics.spacing8)
        }
    }

    /// Die Uhrzeit, wie sie in der Kopfzeile steht.
    private var nowClock: ClockTime {
        let parts = ldCalendar.dateComponents([.hour, .minute], from: model.now)
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private func phase(of course: CourseItem) -> SessionRow.Phase {
        guard model.isToday else { return day < store.today ? .past : .upcoming }
        if course.end <= nowClock { return .past }
        return course.start <= nowClock ? .running : .upcoming
    }

    /// „ab 15:45", wenn die Luecke bis zum Abend reicht - sonst „12:00–14:00".
    static func slotLabel(_ slot: TimeSpan) -> String {
        slot.end >= DashboardState.plannableDay.end ? "ab \(slot.start.text)" : slot.text
    }

    // MARK: - Ereignisse

    private var eventsCard: some View {
        Card(padding: Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 1) {
                SectionHeader(
                    title: "Termine",
                    done: agenda.events.count { store.isDone($0.id, on: day) },
                    total: agenda.events.count
                )
                .padding(.horizontal, Metrics.spacing8)
                .padding(.bottom, Metrics.spacing6)

                if visibleEvents.isEmpty {
                    EmptyHint(text: isSearching ? "Kein Treffer." : "Keine Termine · klicken zum Hinzufügen")
                } else {
                    ForEach(visibleEvents) { event in
                        EventRow(
                            event: event,
                            isDone: store.isDone(event.id, on: day),
                            onToggle: { store.toggleCompletion(event.id, on: day) },
                            onEdit: { model.edit(event: event) },
                            onDuplicate: { model.duplicate(event: event) },
                            onDelete: { model.delete(event: event) }
                        )
                    }
                }
            }
            .animation(Motion.smooth(reduced: reduceMotion), value: agenda.events)
        }
        .addOnTap { model.newEntry(kind: .event) }
    }

    // MARK: - Aufgaben

    private var tasksCard: some View {
        Card(padding: Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 1) {
                SectionHeader(
                    title: "Aufgaben",
                    done: agenda.tasks.count { store.isDone($0.id, on: day) },
                    total: agenda.tasks.count
                )
                .padding(.horizontal, Metrics.spacing8)
                .padding(.bottom, Metrics.spacing6)

                if visibleTasks.isEmpty {
                    EmptyHint(text: isSearching ? "Kein Treffer." : "Nichts zu erledigen · klicken zum Hinzufügen")
                } else {
                    ForEach(visibleTasks) { task in
                        TaskRow(
                            task: task,
                            isDone: store.isDone(task.id, on: day),
                            onToggle: { store.toggleCompletion(task.id, on: day) },
                            onEdit: { model.edit(task: task) },
                            onDuplicate: { model.duplicate(task: task) },
                            onDelete: { model.delete(task: task) },
                            onPostpone: { model.move(task: task, by: $0) },
                            onDrop: { model.place(draggedTaskID: $0, at: task) }
                        )
                    }
                }
            }
            .animation(Motion.smooth(reduced: reduceMotion), value: agenda.tasks)
        }
        .addOnTap { model.newEntry(kind: .task) }
    }

    // MARK: - Gewohnheiten

    private var habitsCard: some View {
        Card(padding: Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 1) {
                SectionHeader(
                    title: "Gewohnheiten",
                    done: agenda.habits.count { store.isDone($0.id, on: day) },
                    total: agenda.habits.count
                )
                .padding(.horizontal, Metrics.spacing8)
                .padding(.bottom, Metrics.spacing6)

                if visibleHabits.isEmpty {
                    EmptyHint(text: isSearching ? "Kein Treffer." : "Keine Gewohnheiten · klicken zum Hinzufügen")
                } else {
                    ForEach(visibleHabits) { habit in
                        HabitRow(
                            habit: habit,
                            isDone: store.isDone(habit.id, on: day),
                            onToggle: { store.toggleCompletion(habit.id, on: day) },
                            onEdit: { model.edit(habit: habit) },
                            onDelete: { model.delete(habit: habit) }
                        )
                    }
                }

            }
            .animation(Motion.smooth(reduced: reduceMotion), value: agenda.habits)
        }
        .addOnTap { model.newEntry(kind: .habit) }
    }

    // MARK: - Rueckholen

    @ViewBuilder
    private var undoToast: some View {
        if let notice = model.createdNotice {
            HStack(spacing: Metrics.spacing12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)

                Text(notice.count == 1 ? "1 Eintrag angelegt" : "\(notice.count) Einträge angelegt")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textPrimary)

                Button("Rückgängig") { model.undoCreation() }
                    .buttonStyle(.plain)
                    .font(Typo.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
                    .expandedHitArea(6)

                Button {
                    model.dismissCreatedNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .expandedHitArea(8)
            }
            .padding(.horizontal, Metrics.spacing16)
            .padding(.vertical, Metrics.spacing12)
            .background(Palette.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            .padding(.bottom, Metrics.spacing24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let pending = model.pendingUndo {
            HStack(spacing: Metrics.spacing12) {
                Text("\(pending.deleted.descriptionOfKind) „\(pending.deleted.title)“ gelöscht")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textPrimary)

                Button("Rückgängig") { model.undoDeletion() }
                    .buttonStyle(.plain)
                    .font(Typo.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
                    .expandedHitArea(6)

                Button {
                    model.dismissUndo()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .expandedHitArea(8)
            }
            .padding(.horizontal, Metrics.spacing16)
            .padding(.vertical, Metrics.spacing12)
            .background(Palette.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
            .padding(.bottom, Metrics.spacing24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(Motion.snappy(reduced: reduceMotion), value: pending.id)
        }
    }

    // MARK: - Datumsformate

    static func weekdayName(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day.date)
    }

    static func longDate(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        return formatter.string(from: day.date)
    }
}

private extension Sequence {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
