import PlanerCore
import PlanerData
import SwiftUI

/// Der Stundenplan: eine Woche als Raster, Zeit nach unten, Tage nach rechts.
///
/// Warum ein Raster und keine Liste: Die Frage, die man an einen Stundenplan
/// hat, ist keine Aufzaehlung („was habe ich am Dienstag"), sondern eine
/// raeumliche - *wo ist noch Platz*. In einer Liste muss man Luecken aus
/// Uhrzeiten errechnen; in einem Raster sieht man sie. Der leere Platz ist die
/// Antwort.
///
/// Drei Entscheidungen tragen die Uebersicht:
///
/// - **Die Woche passt ins Fenster.** Die Stundenhoehe richtet sich nach dem
///   verfuegbaren Platz. Ein Stundenplan, den man scrollen muss, zeigt nie die
///   ganze Woche - und genau die will man sehen.
/// - **Kurse sind gefuellt, Termine umrandet.** Der Kurs ist der feste Rahmen,
///   der Termin das, was man hineinlegt. Beisst sich einer mit einem Kurs, wird
///   seine Umrandung zum Warnzeichen.
/// - **Was vorbei ist, tritt zurueck.** Erledigte Tage und abgelaufene
///   Stunden werden blasser. Der Blick geht dahin, wo noch etwas kommt.
struct TimetableView: View {
    @Bindable var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Welche Stelle im Raster gerade angeklickt wurde. Dort erscheint die
    /// Auswahl „Kurs oder Termin".
    @State private var slot: Slot?

    private var store: StateStore { model.store }

    // MARK: - Masse

    private static let gutterWidth: CGFloat = 34
    private static let columnSpacing: CGFloat = 4
    private static let laneSpacing: CGFloat = 2
    /// Darunter wird der Titel unleserlich - dann lieber scrollen.
    private static let minHourHeight: CGFloat = 30
    /// Darueber wirken Bloecke aufgeblasen; der Rest bleibt unten frei.
    private static let maxHourHeight: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.hasCourses || !allBlocks.isEmpty {
                headerRow
                Divider().overlay(Palette.border)
                gridBody
                legend
                    .padding(.top, Metrics.spacing8)
            } else {
                emptyState
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.selectedDate) { _, _ in slot = nil }
        // Ist das Blatt offen, hat sich die Auswahl erledigt.
        .onChange(of: model.editorTarget) { _, _ in slot = nil }
        .onExitCommand { slot = nil }
    }

    // MARK: - Tage und Zeitfenster

    private var monday: DateKey { model.selectedDate.startOfWeek }
    private var today: DateKey { store.today }

    /// Montag bis Freitag immer, Wochenende nur, wenn dort etwas steht.
    ///
    /// Zwei dauerhaft leere Spalten kosten ein Drittel der Breite und sagen
    /// nichts. Steht am Samstag ein Blockseminar, ist die Spalte da.
    private var days: [DateKey] {
        let week = (0..<7).map { monday.adding(days: $0) }
        let weekend = week.suffix(2).filter { day in
            let agenda = store.agenda(for: day)
            return !agenda.busyBlocks.isEmpty || !agenda.events.isEmpty
        }
        return Array(week.prefix(5)) + weekend
    }

    private var allBlocks: [BusyBlock] {
        days.flatMap { store.agenda(for: $0).busyBlocks }
    }

    /// Der gezeigte Tagesabschnitt.
    ///
    /// Er richtet sich nach **allen** Kursen des Semesters, nicht nur nach
    /// denen dieser Woche. Sonst sprange das Raster beim Blaettern: Mal begaenne
    /// es um acht, mal um zehn, und dieselbe Uhrzeit stuende jede Woche an einer
    /// anderen Stelle. Nur Termine dieser Woche duerfen es zusaetzlich dehnen.
    private var window: TimeSpan {
        let spans = store.state.courses.map(\.span) + allBlocks.map(\.span)
        let earliest = spans.map(\.start).min() ?? ClockTime(hour: 8)
        let latest = spans.map(\.end).max() ?? ClockTime(hour: 18)
        return TimeSpan(
            start: min(earliest, ClockTime(hour: 8)).flooredToHour,
            end: max(latest, ClockTime(hour: 18)).ceiledToHour
        )
    }

    private var hours: [Int] {
        Array(window.start.hour...window.end.hour)
    }

    /// Umrechnung von Uhrzeit in Hoehe - fuer eine bestimmte Stundenhoehe.
    private struct Scale {
        let window: TimeSpan
        let hourHeight: CGFloat

        var height: CGFloat { CGFloat(window.minutes) / 60 * hourHeight }

        func y(_ time: ClockTime) -> CGFloat {
            CGFloat(time.minutes - window.start.minutes) / 60 * hourHeight
        }
    }

    // MARK: - Kopfzeile

    private var headerRow: some View {
        // Oben ausgerichtet: Die Wochentage sollen auf einer Linie stehen, auch
        // wenn unter einem davon noch ein ganztaegiger Termin haengt.
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            Color.clear.frame(width: Self.gutterWidth, height: 1)

            ForEach(days, id: \.self) { day in
                columnHeader(day)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, Metrics.spacing6)
    }

    private func columnHeader(_ day: DateKey) -> some View {
        let isToday = day == today
        let holiday = Holidays.name(on: day)
        let agenda = store.agenda(for: day)
        let untimed = agenda.events.filter { $0.time == nil }

        return Button {
            model.selectedDate = day
            model.viewMode = .day
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(WeekView.weekdayShort(day))
                        .font(Typo.chip)
                        .foregroundStyle(isToday ? Palette.textPrimary : Palette.textTertiary)

                    // Heute traegt seine Zahl in einer hellen Kapsel - wie im
                    // Kalender links. Eine eingefaerbte Spalte darunter waere
                    // ein grauer Balken quer durch das ganze Raster.
                    Text("\(day.day)")
                        .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(
                            isToday ? Palette.onAccent
                                : holiday != nil ? Palette.urgent
                                : day < today ? Palette.textSecondary : Palette.textPrimary
                        )
                        .padding(.horizontal, isToday ? 6 : 0)
                        .padding(.vertical, isToday ? 1 : 0)
                        .background(
                            Capsule().fill(isToday ? Palette.accent : .clear)
                        )
                    Spacer(minLength: 0)
                }

                // Was keine Uhrzeit hat, kann im Raster nicht stehen - und darf
                // trotzdem nicht fehlen, sonst sucht man den Geburtstag.
                Group {
                    if let holiday {
                        Text(holiday).foregroundStyle(Palette.urgent)
                    } else if agenda.isVacation {
                        Text("Urlaub").foregroundStyle(Palette.textTertiary)
                    } else if let first = untimed.first {
                        Text(untimed.count > 1 ? "\(first.title) +\(untimed.count - 1)" : first.title)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        // Platzhalter, damit alle Koepfe gleich hoch sind.
                        Text(" ")
                    }
                }
                .font(.system(size: 9))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.97))
        .help("Diesen Tag öffnen")
    }

    // MARK: - Raster

    /// Das Raster nimmt sich die verfuegbare Hoehe. Nur wenn die Woche selbst
    /// bei kleinster lesbarer Stundenhoehe nicht passt, wird gescrollt.
    private var gridBody: some View {
        GeometryReader { geometry in
            let available = geometry.size.height - Metrics.spacing8
            let fitted = available / max(CGFloat(window.minutes) / 60, 1)
            let hourHeight = min(max(fitted, Self.minHourHeight), Self.maxHourHeight)
            let scale = Scale(window: window, hourHeight: hourHeight)

            if fitted >= Self.minHourHeight {
                bodyRow(scale)
            } else {
                ScrollView(.vertical) {
                    bodyRow(scale)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(minHeight: 200)
    }

    private func bodyRow(_ scale: Scale) -> some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            gutter(scale)
            ForEach(days, id: \.self) { day in
                column(day, scale: scale)
            }
        }
        .padding(.top, Metrics.spacing8)
    }

    // MARK: - Zeitachse

    private func gutter(_ scale: Scale) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(hours, id: \.self) { hour in
                Text(ClockTime(hour: hour).shortText)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
                    // Die Zahl sitzt auf ihrer Linie, nicht darunter.
                    .offset(y: scale.y(ClockTime(hour: hour)) - 6)
            }
        }
        .frame(width: Self.gutterWidth - Metrics.spacing6, height: scale.height, alignment: .topTrailing)
        .padding(.trailing, Metrics.spacing6)
    }

    // MARK: - Tagesspalte

    private func column(_ day: DateKey, scale: Scale) -> some View {
        let blocks = placed(for: day)

        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                canvasLayer(day, scale: scale)

                ForEach(blocks) { item in
                    blockView(item, columnWidth: geometry.size.width, scale: scale)
                }

                if day == today, let now = nowTime, scale.window.contains(now) {
                    nowMarker.offset(y: scale.y(now) - 0.75)
                }

                if let slot, slot.day == day {
                    slotChooser(slot)
                        // Am rechten Rand nach innen ruecken, sonst steht die
                        // Auswahl halb ausserhalb des Fensters.
                        .offset(
                            x: day == days.last ? min(0, geometry.size.width - 170) : 0,
                            y: max(0, scale.y(slot.time) - 4)
                        )
                        .zIndex(2)
                }
            }
        }
        .frame(height: scale.height)
        .frame(maxWidth: .infinity)
    }

    /// Stundenlinien - und die Flaeche, auf die man klickt.
    private func canvasLayer(_ day: DateKey, scale: Scale) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(hours, id: \.self) { hour in
                Rectangle()
                    .fill(Palette.border.opacity(hour == window.start.hour ? 0 : 0.75))
                    .frame(height: 1)
                    .offset(y: scale.y(ClockTime(hour: hour)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
            slot = Slot(day: day, time: time(atOffset: point.y, scale: scale))
        }
        .help("Klicken, um hier einen Kurs oder Termin anzulegen")
    }

    /// Uhrzeit an einer angeklickten Hoehe, auf eine Viertelstunde gerundet -
    /// die Einteilung, in der Vorlesungen beginnen.
    private func time(atOffset y: CGFloat, scale: Scale) -> ClockTime {
        let minutes = Int((y / scale.hourHeight) * 60) + scale.window.start.minutes
        let quarter = (minutes / 15) * 15
        return ClockTime(minutes: min(max(quarter, scale.window.start.minutes),
                                      scale.window.end.minutes - 15))
    }

    private var nowTime: ClockTime? {
        let parts = ldCalendar.dateComponents([.hour, .minute], from: model.now)
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private var nowMarker: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Palette.accent)
                .frame(height: 1.5)
            Circle()
                .fill(Palette.accent)
                .frame(width: 6, height: 6)
                .offset(x: -3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Bloecke

    private func blockView(_ item: Placed, columnWidth: CGFloat, scale: Scale) -> some View {
        let laneWidth = (columnWidth - CGFloat(item.laneCount - 1) * Self.laneSpacing)
            / CGFloat(item.laneCount)
        let height = max(CGFloat(item.block.span.minutes) / 60 * scale.hourHeight - 2, 18)

        return blockBody(item, height: height)
            .frame(width: max(laneWidth, 24), height: height, alignment: .topLeading)
            .offset(
                x: CGFloat(item.lane) * (laneWidth + Self.laneSpacing),
                y: scale.y(item.block.span.start) + 1
            )
    }

    /// Ist der Block schon vorbei? Dann tritt er zurueck.
    private func isPast(_ item: Placed) -> Bool {
        if item.day < today { return true }
        guard item.day == today, let now = nowTime else { return false }
        return item.block.span.end <= now
    }

    @ViewBuilder
    private func blockBody(_ item: Placed, height: CGFloat) -> some View {
        let block = item.block
        let isDone = block.event.map { store.isDone($0.id, on: item.day) } ?? false

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                if item.isConflicting && !block.isCourse {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Palette.urgent)
                }
                Text(block.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(isDone, color: Palette.textSecondary)
                    .lineLimit(height > 46 ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Erst ab einer gewissen Hoehe ist Platz fuer mehr als den Namen.
            // Zeit und Raum in einer Zeile: Das ist die Information, die man
            // auf dem Weg zum Hoersaal braucht, und sie kostet nur eine Zeile.
            if height > 30 {
                Text(detailLine(block))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .padding(.leading, block.isCourse ? 3 : 0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(blockBackground(item))
        .overlay(alignment: .leading) {
            // Der Farbstreifen gehoert zum Kurs; der Termin traegt seine Farbe
            // in der Umrandung.
            if block.isCourse {
                RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                    .fill(Palette.eventColor(key: block.colorKey))
                    .frame(width: Metrics.accentStripWidth)
                    .padding(.vertical, 3)
                    .padding(.leading, 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.chipRadius + 1, style: .continuous))
        .opacity(isDone ? 0.4 : isPast(item) ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { open(block) }
        .contextMenu { menu(for: item) }
        .help(helpText(for: item))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityAddTraits(.isButton)
    }

    /// „08:15–09:45 · H 12" beim Kurs, „16:30" beim Termin.
    private func detailLine(_ block: BusyBlock) -> String {
        guard block.isCourse else {
            if let event = block.event, event.durationMinutes != nil {
                return block.span.text
            }
            return block.span.start.text
        }
        return block.room.isEmpty ? block.span.text : "\(block.span.text) · \(block.room)"
    }

    @ViewBuilder
    private func blockBackground(_ item: Placed) -> some View {
        let color = Palette.eventColor(key: item.block.colorKey)
        let shape = RoundedRectangle(cornerRadius: Metrics.chipRadius + 1, style: .continuous)

        if item.block.isCourse {
            // Ein Hauch der Kursfarbe auf der Flaeche: genug, dass man ein Modul
            // ueber die Woche hinweg wiedererkennt, zu wenig, um bunt zu wirken.
            shape
                .fill(Palette.surfaceRaised)
                .overlay(shape.fill(color.opacity(0.14)))
                .overlay(shape.strokeBorder(color.opacity(0.18), lineWidth: 1))
        } else {
            shape
                .fill(Palette.canvas)
                .overlay(
                    shape.strokeBorder(
                        item.isConflicting ? Palette.urgent : color.opacity(0.8),
                        lineWidth: item.isConflicting ? 1.5 : 1
                    )
                )
        }
    }

    private func open(_ block: BusyBlock) {
        slot = nil
        if let course = block.course {
            model.edit(course: course)
        } else if let event = block.event {
            model.edit(event: event)
        }
    }

    @ViewBuilder
    private func menu(for item: Placed) -> some View {
        if let course = item.block.course {
            Button("Bearbeiten") { model.edit(course: course) }
            Button("Diese Sitzung fällt aus") { model.cancelSession(course, on: item.day) }
            Divider()
            Button("Kurs löschen", role: .destructive) { model.delete(course: course) }
        } else if let event = item.block.event {
            Button("Bearbeiten") { model.edit(event: event) }
            Button(store.isDone(event.id, on: item.day) ? "Nicht erledigt" : "Erledigt") {
                store.toggleCompletion(event.id, on: item.day)
            }
            Divider()
            Button("Löschen", role: .destructive) { model.delete(event: event) }
        }
    }

    private func helpText(for item: Placed) -> String {
        var parts: [String] = [item.block.label, item.block.span.text]
        if !item.block.room.isEmpty { parts.append(item.block.room) }
        if let course = item.block.course {
            if !course.lecturer.isEmpty { parts.append(course.lecturer) }
            if let weeks = course.weeks.shortLabel { parts.append(weeks) }
        }
        if item.isConflicting { parts.append("überschneidet sich") }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for item: Placed) -> String {
        let weekday = DashboardView.weekdayName(item.day)
        return "\(weekday), \(item.block.span.text), \(item.block.label)"
            + (item.block.room.isEmpty ? "" : ", Raum \(item.block.room)")
            + (item.isConflicting ? ", überschneidet sich" : "")
    }

    // MARK: - Auswahl an der angeklickten Stelle
    //
    // Ein Klick ins Leere koennte zweierlei meinen: einen Kurs eintragen oder
    // einen Termin in die Luecke legen. Beides ist gleich plausibel, also
    // entscheidet nicht die App, sondern ein zweiter Klick - direkt dort, wo der
    // erste hingegangen ist.

    private struct Slot: Equatable {
        let day: DateKey
        let time: ClockTime
    }

    private func slotChooser(_ slot: Slot) -> some View {
        HStack(spacing: Metrics.spacing4) {
            Text(slot.time.text)
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)

            chooserButton("Termin", symbol: "calendar") {
                model.newEvent(on: slot.day, at: slot.time)
                self.slot = nil
            }
            chooserButton("Kurs", symbol: "graduationcap") {
                model.newCourse(weekday: slot.day.weekdayIndex, start: slot.time)
                self.slot = nil
            }
        }
        .padding(.horizontal, Metrics.spacing6)
        .padding(.vertical, Metrics.spacing4)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(Palette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 1)
        )
        .fixedSize()
        .transition(.opacity)
        .animation(Motion.snappy(reduced: reduceMotion), value: slot)
    }

    private func chooserButton(_ title: String, symbol: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 8))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Metrics.spacing4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.92))
    }

    // MARK: - Anordnung in Spuren

    /// Ein angeordneter Block samt seinem Tag.
    ///
    /// Die Anordnung selbst steckt in `TimetableLayout` - sie ist reine Logik
    /// und dort auch pruefbar. Hier kommt nur der Tag dazu, damit sich zwei
    /// Vorkommen desselben Kurses in der Woche auseinanderhalten lassen.
    private struct Placed: Identifiable {
        let day: DateKey
        let laidOut: LaidOutBlock

        var block: BusyBlock { laidOut.block }
        var lane: Int { laidOut.lane }
        var laneCount: Int { laidOut.laneCount }
        var isConflicting: Bool { laidOut.isConflicting }

        var id: String { "\(day.rawValue)-\(laidOut.id.uuidString)" }
    }

    private func placed(for day: DateKey) -> [Placed] {
        TimetableLayout.lanes(for: store.agenda(for: day).busyBlocks)
            .map { Placed(day: day, laidOut: $0) }
    }

    // MARK: - Fusszeile

    private var legend: some View {
        HStack(spacing: Metrics.spacing12) {
            legendItem(filled: true, text: "Kurs")
            legendItem(filled: false, text: "Termin")

            Spacer()

            if let first = store.state.courses.first {
                // Welches Semester gezeigt wird, steht einmal rechts unten.
                // Laeuft die Woche ausserhalb, sagt es, warum das Raster leer
                // ist.
                Text(Semester(firstDay: first.firstDay, lastDay: first.lastDay).label)
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.leading, Self.gutterWidth + Self.columnSpacing)
    }

    private func legendItem(filled: Bool, text: String) -> some View {
        HStack(spacing: Metrics.spacing4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(filled ? Palette.surfaceRaised : Palette.canvas)
                .frame(width: 14, height: 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(filled ? Palette.border : Palette.textSecondary, lineWidth: 1)
                )
            Text(text)
                .font(Typo.chip)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Noch kein Kurs

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing8) {
            Text("Noch kein Stundenplan")
                .font(Typo.bodyEmphasized)
                .foregroundStyle(Palette.textPrimary)

            Text("Trage deine Module ein - Tag, Uhrzeit und Raum. Sie erscheinen dann in jeder "
                 + "Woche des Semesters, zählen aber in keine Kennzahl: Ein Vorlesungstag ist "
                 + "kein halb erledigter Tag.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)

            Button {
                model.newCourse()
            } label: {
                HStack(spacing: Metrics.spacing4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("Kurs eintragen").font(Typo.caption.weight(.medium))
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Metrics.spacing12)
                .padding(.vertical, Metrics.spacing6)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(Palette.surfaceRaised)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.96))
            .padding(.top, Metrics.spacing4)
        }
        .padding(.vertical, Metrics.spacing24)
    }
}
