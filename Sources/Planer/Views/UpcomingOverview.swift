import PlanerCore
import PlanerData
import SwiftUI

/// Alle anstehenden Termine auf einen Blick - und von hier aus bearbeitbar.
///
/// Die Seitenspalte zeigt nur, was hineinpasst. Hier steht alles fuer das
/// kommende Jahr, gegliedert so, wie man ueber Zeit nachdenkt: heute, morgen,
/// diese Woche, naechste Woche, danach monatsweise. Je weiter weg, desto
/// groeber die Einteilung - niemand plant den Maerz tageweise.
///
/// Wiederkehrende Termine stehen einmal, an ihrem naechsten Vorkommen, mit dem
/// Rhythmus daneben. Sonst bestuende die Liste zur Haelfte aus dem Training.
struct UpcomingOverview: View {
    @Bindable var model: AppModel

    @Environment(\.closePanel) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: StateStore { model.store }
    private var items: [UpcomingEvent] { store.allUpcomingEvents() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)

            if items.isEmpty {
                emptyState
            } else {
                list
            }

            if let pending = model.pendingUndo {
                undoBar(pending)
            }
        }
        .frame(maxWidth: 640, maxHeight: 600)
        .background(Palette.canvas)
        .animation(Motion.smooth(reduced: reduceMotion), value: items.map(\.id))
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: Metrics.spacing12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Anstehende Termine")
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(countText)
                    .font(Typo.pageSubtitle)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer()

            Button {
                model.editorTarget = .newEvent(store.today)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("Termin").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Metrics.spacing8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.95))
            .keyboardShortcut("n", modifiers: .command)

            Button("Fertig") { dismiss() }
                .buttonStyle(.pressable)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
                .expandedHitArea(6)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Metrics.spacing20)
        .frame(height: 64)
    }

    private var countText: String {
        switch items.count {
        case 0: "Nichts in Sicht"
        case 1: "1 Termin im kommenden Jahr"
        default: "\(items.count) Termine im kommenden Jahr"
        }
    }

    // MARK: - Liste

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.items) { item in
                            UpcomingRow(
                                item: item,
                                onEdit: { model.edit(event: item.event) },
                                onShowDay: {
                                    model.selectedDate = item.day
                                    model.viewMode = .day
                                    dismiss()
                                },
                                onComplete: { store.toggleCompletion(item.event.id, on: item.day) },
                                onDelete: { model.delete(event: item.event) }
                            )
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .padding(.horizontal, Metrics.spacing12)
            .padding(.bottom, Metrics.spacing16)
        }
        .scrollIndicators(.never)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typo.sectionTitle)
            .tracking(Typo.sectionTracking)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.spacing8)
            .padding(.top, Metrics.spacing16)
            .padding(.bottom, Metrics.spacing6)
            .background(Palette.canvas)
    }

    // MARK: - Gliederung

    private var sections: [UpcomingSection] {
        UpcomingGrouping.sections(for: items, today: store.today)
    }

    // MARK: - Leer

    private var emptyState: some View {
        VStack(spacing: Metrics.spacing8) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Keine Termine in Sicht")
                .font(Typo.bodyEmphasized)
                .foregroundStyle(Palette.textSecondary)
            Text("Mit „Termin“ oben rechts legst du einen an.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rueckholen

    /// Der Hinweis zum Rueckgaengigmachen gehoert hierher, nicht ins Fenster
    /// dahinter - dort saehe man ihn erst, wenn er schon verschwunden ist.
    private func undoBar(_ pending: PendingUndo) -> some View {
        HStack(spacing: Metrics.spacing12) {
            Text("\(pending.deleted.descriptionOfKind) „\(pending.deleted.title)“ gelöscht")
                .font(Typo.caption)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Button("Rückgängig") { model.undoDeletion() }
                .buttonStyle(.plain)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
                .expandedHitArea(6)
        }
        .padding(.horizontal, Metrics.spacing20)
        .padding(.vertical, Metrics.spacing12)
        .background(Palette.surfaceRaised)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Zeile

private struct UpcomingRow: View {
    let item: UpcomingEvent
    let onEdit: () -> Void
    let onShowDay: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var event: EventItem { item.event }
    private var color: Color { Palette.eventColor(key: event.colorKey) }

    var body: some View {
        HStack(spacing: Metrics.spacing12) {
            // Datum in fester Breite: Untereinander gelesen ergeben die Tage
            // eine Spalte, an der das Auge entlanglaeuft.
            Text(Self.dateLabel(item.day))
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 74, alignment: .leading)

            Text(timeLabel)
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(event.time == nil ? Palette.textTertiary : Palette.textSecondary)
                .frame(width: 86, alignment: .leading)

            RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                .fill(color)
                .frame(width: Metrics.accentStripWidth, height: 16)

            Text(event.title)
                .font(item.daysAway <= 1 ? Typo.bodyEmphasized : Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            if let recurrence = event.recurrence.shortLabel {
                Chip(text: recurrence, systemImage: "repeat", tint: Palette.textTertiary)
            }

            if !event.notes.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .help(event.notes)
            }

            Spacer(minLength: Metrics.spacing8)

            Text(item.shortLabel)
                .font(Typo.metricSmall)
                .foregroundStyle(item.daysAway <= 1 ? Palette.textPrimary
                                 : item.daysAway <= 7 ? Palette.textSecondary : Palette.textTertiary)
        }
        .padding(.horizontal, Metrics.spacing8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(isHovering ? Palette.surfaceRaised : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Bearbeiten", action: onEdit)
            Button("Tag öffnen", action: onShowDay)
            Button("Als erledigt markieren", action: onComplete)
            Divider()
            Button("Löschen", role: .destructive, action: onDelete)
        }
        .help("Klicken zum Bearbeiten")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(DateField.format(item.day)), \(timeLabel), \(item.longLabel)")
        .accessibilityAction(named: "Bearbeiten", onEdit)
        .accessibilityAction(named: "Tag öffnen", onShowDay)
        .accessibilityAction(named: "Löschen", onDelete)
    }

    /// „14:30", mit Dauer „14:30–15:15", ohne Uhrzeit „ganztägig".
    private var timeLabel: String {
        guard event.time != nil else { return "ganztägig" }
        if event.durationMinutes != nil, let span = event.span { return span.text }
        return event.clock?.text ?? ""
    }

    static func dateLabel(_ day: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EE d.M."
        return formatter.string(from: day.date)
    }
}
