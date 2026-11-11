import PlanerCore
import SwiftUI

// MARK: - Ereignis

struct EventRow: View {
    let event: EventItem
    let isDone: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var color: Color { Palette.eventColor(key: event.colorKey) }

    var body: some View {
        ItemRow(stripColor: color, isDone: isDone) {
            CheckToggle(isOn: isDone, shape: .round, tint: color, label: event.title, action: onToggle)

            Text(event.title)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .strikethrough(isDone, color: Palette.textSecondary)
                .lineLimit(1)

            if let recurrence = event.recurrence.shortLabel {
                Chip(text: recurrence, systemImage: "repeat")
            }

            Spacer(minLength: Metrics.spacing8)

            if !event.notes.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .help(event.notes)
            }

            // Mit angegebener Dauer die ganze Spanne - „16:30–17:30" sagt mehr
            // als „16:30", wenn man wissen will, wann man wieder frei ist.
            if event.durationMinutes != nil, let span = event.span {
                Chip(text: span.text)
            } else if let time = event.time {
                Chip(text: time)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Bearbeiten", action: onEdit)
            Button("Duplizieren", action: onDuplicate)
            Divider()
            Button("Löschen", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: "Bearbeiten", onEdit)
        .accessibilityAction(named: "Duplizieren", onDuplicate)
        .accessibilityAction(named: "Löschen", onDelete)
    }
}

// MARK: - Aufgabe

struct TaskRow: View {
    let task: TaskItem
    let isDone: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    /// Um so viele Tage weiterschieben.
    let onPostpone: (Int) -> Void
    /// Eine andere Aufgabe wurde auf diese gezogen.
    let onDrop: (String) -> Void

    @State private var isDropTarget = false

    var body: some View {
        ItemRow(stripColor: task.priority == .high ? Palette.urgent : nil, isDone: isDone) {
            CheckToggle(isOn: isDone, label: task.title, action: onToggle)

            Text(task.title)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .strikethrough(isDone, color: Palette.textSecondary)
                .lineLimit(1)

            if task.priority == .high {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.urgent)
                    .accessibilityLabel("Hohe Priorität")
            }

            if let recurrence = task.recurrence.shortLabel {
                Chip(text: recurrence, systemImage: "repeat")
            }

            Spacer(minLength: Metrics.spacing8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        // Die Kennung genuegt als Fracht - das Ziel schlaegt die Aufgabe selbst
        // nach, statt sie durch die Zwischenablage zu schicken.
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            onDrop(first)
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.accent)
                .frame(height: 1.5)
                .opacity(isDropTarget ? 1 : 0)
        }
        .contextMenu {
            Button("Bearbeiten", action: onEdit)
            Menu("Verschieben auf") {
                Button("Morgen") { onPostpone(1) }
                Button("Übermorgen") { onPostpone(2) }
                Button("Nächste Woche") { onPostpone(7) }
            }
            Button("Duplizieren", action: onDuplicate)
            Divider()
            Button("Löschen", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: "Bearbeiten", onEdit)
        .accessibilityAction(named: "Auf morgen verschieben") { onPostpone(1) }
        .accessibilityAction(named: "Duplizieren", onDuplicate)
        .accessibilityAction(named: "Löschen", onDelete)
    }
}

// MARK: - Gewohnheit

struct HabitRow: View {
    let habit: HabitItem
    let isDone: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ItemRow(isDone: isDone) {
            CheckToggle(isOn: isDone, shape: .round, label: habit.title, action: onToggle)

            Text(habit.title)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Metrics.spacing8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Umbenennen", action: onEdit)
            Button("Löschen", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: "Umbenennen", onEdit)
        .accessibilityAction(named: "Löschen", onDelete)
    }
}

// MARK: - Leerer Zustand

/// Was steht, wenn nichts ansteht.
///
/// Ein leerer Kasten wirkt wie ein Fehler. Ein Satz und ein Weg zum naechsten
/// Schritt wirken wie eine Antwort.
struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.caption)
            .foregroundStyle(Palette.textTertiary)
            .padding(.vertical, Metrics.spacing6)
            .padding(.horizontal, Metrics.spacing8 + Metrics.accentStripWidth + Metrics.spacing6)
    }
}

// MARK: - Sitzung des Stundenplans

/// Eine Veranstaltung an einem bestimmten Tag.
///
/// **Ohne Haekchen** - und das ist der Unterschied, auf den es ankommt. Eine
/// Vorlesung wird nicht erledigt; sie findet statt. Ein Kaestchen davor hiesse,
/// der Tag sei unvollstaendig, solange man es nicht angeklickt hat, und genau
/// das soll der Stundenplan nicht tun. Statt des Kaestchens steht die Uhrzeit
/// da, denn das ist, was man wissen will.
struct SessionRow: View {
    /// Wo die Sitzung im Lauf des Tages steht.
    enum Phase { case past, running, upcoming }

    let course: CourseItem
    /// Nur am heutigen Tag von Belang - an jedem anderen ist alles „kommt".
    var phase: Phase = .upcoming
    let onEdit: () -> Void
    let onCancelSession: () -> Void
    let onDelete: () -> Void

    private var color: Color { Palette.eventColor(key: course.colorKey) }

    var body: some View {
        // Was vorbei ist, tritt zurueck - wie ein abgehakter Eintrag, nur ohne
        // dass man etwas dafuer tun musste.
        ItemRow(stripColor: color, isDone: phase == .past) {
            Text(course.span.text)
                .font(Typo.chip)
                .monospacedDigit()
                .foregroundStyle(phase == .running ? Palette.textPrimary : Palette.textSecondary)
                // Feste Breite, damit die Titel darunter auf einer Kante
                // stehen und sich die Liste senkrecht lesen laesst.
                .frame(width: 82, alignment: .leading)

            Text(course.title)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Chip(text: course.kind.shortLabel, tint: Palette.textTertiary)

            if phase == .running {
                SolidChip(text: "läuft", tint: Palette.perfect)
            }

            if let weeks = course.weeks.shortLabel {
                Chip(text: weeks, systemImage: "repeat", tint: Palette.textTertiary)
            }

            Spacer(minLength: Metrics.spacing8)

            if !course.room.isEmpty {
                Chip(text: course.room, systemImage: "mappin", tint: Palette.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Bearbeiten", action: onEdit)
            Button("Diese Sitzung fällt aus", action: onCancelSession)
            Divider()
            Button("Kurs löschen", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(course.spokenDescription)
        .accessibilityAction(named: "Bearbeiten", onEdit)
        .accessibilityAction(named: "Sitzung fällt aus", onCancelSession)
    }
}
