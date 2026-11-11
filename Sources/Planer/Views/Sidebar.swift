import PlanerCore
import PlanerData
import SwiftUI

/// Die linke Spalte: Kalender, Fortschritt, naechste Termine, Notizen.
///
/// **Sie scrollt nicht.** Eine Seitenspalte mit Rollbalken ist eine, bei der
/// man nie weiss, ob unten noch etwas steht. Stattdessen teilt sie den Platz
/// auf: Kalender und Ring sind fest, die Terminliste zeigt so viele Eintraege,
/// wie Platz haben, und die Notizen bekommen den Rest. Was nicht hineinpasst,
/// ist einen Klick entfernt - die ganze Terminliste ueber die Ueberschrift,
/// die ganzen Notizen ueber den Knopf daneben.
struct SidebarView: View {
    @Bindable var model: AppModel

    private var store: StateStore { model.store }
    private var day: DateKey { model.selectedDate }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: Metrics.spacing12) {
                MiniCalendar(
                    month: model.visibleMonth,
                    selected: day,
                    today: store.today,
                    mark: model.mark,
                    onSelect: { model.selectedDate = $0 },
                    onStep: { model.stepMonth($0) },
                    onToday: { model.goToToday() }
                )

                divider

                progress

                divider

                upcoming(rows: Self.upcomingRows(forHeight: geometry.size.height))

                divider

                NotesPanel(model: model)
            }
            .padding(.horizontal, Metrics.spacing16)
            .padding(.vertical, Metrics.spacing12)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .frame(width: Metrics.sidebarWidth)
        .background(Palette.canvas)
    }

    private var divider: some View {
        Divider().overlay(Palette.border)
    }

    // MARK: - Fortschritt

    private var progress: some View {
        let stats = store.stats(for: day)
        return HStack(spacing: Metrics.spacing16) {
            ProgressRing(
                fraction: stats.fraction,
                isPerfect: stats.isPerfect,
                caption: stats.itemTotal > 0 ? "\(stats.completedTotal) von \(stats.itemTotal)" : nil,
                diameter: 80,
                lineWidth: 5
            )
            StreakBadge(days: store.streak)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Naechste Termine

    private func upcoming(rows: Int) -> some View {
        let all = store.allUpcomingEvents()
        return UpcomingList(
            items: Array(all.prefix(rows)),
            totalCount: all.count,
            onSelect: { model.selectedDate = $0.day },
            onShowAll: { model.showsUpcoming = true }
        )
    }

    /// Wie viele Termine in die Spalte passen, ohne dass den Notizen die Luft
    /// ausgeht.
    ///
    /// Gerechnet statt gemessen: Kalender, Ring und Abstaende haben feste
    /// Hoehen, und eine Zeile ist immer gleich hoch. Den Notizen bleiben dabei
    /// mindestens gut vier Zeilen - darunter waeren sie nur noch ein Schlitz.
    static func upcomingRows(forHeight height: CGFloat) -> Int {
        let fixed: CGFloat = 24        // Innenabstand oben und unten
            + 236                      // Kalender
            + 80                       // Ring
            + 3 * (2 * Metrics.spacing12 + 1) // drei Trennlinien mit Abstand
            + 26                       // Ueberschrift der Terminliste
            + 26                       // Ueberschrift der Notizen
            + 84                       // kleinste sinnvolle Notizflaeche
        let row: CGFloat = 26
        let fitting = Int(((height - fixed) / row).rounded(.down))
        return min(max(fitting, 2), 6)
    }
}

// MARK: - Notizen

/// Der Zettel neben dem Kalender.
///
/// Klein und trotzdem vollstaendig benutzbar: Ein Klick in den Text, und man
/// schreibt - ohne dass sich etwas vergroessert oder verschiebt. Wird der Text
/// laenger als die Flaeche, laeuft er unten weich aus, und der Knopf oben rechts
/// holt ihn in gross auf den Bildschirm.
///
/// Kein Rollbalken, auch nicht beim Schreiben: Das Feld folgt dem Schreibcursor
/// von selbst, und zum Lesen ist die grosse Ansicht da.
struct NotesPanel: View {
    @Bindable var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
    @State private var textHeight: CGFloat = 0
    @State private var expandHovering = false

    private var store: StateStore { model.store }
    private var notes: String { store.state.notes }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing6) {
            HStack(spacing: Metrics.spacing4) {
                SectionHeader(title: "Notizen")
                expandButton
            }

            box
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: model.isEditingNotes) { _, editing in
            if !editing { editorFocused = false }
        }
    }

    private var expandButton: some View {
        Button {
            model.isEditingNotes = false
            model.showsNotes = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(expandHovering ? Palette.textPrimary : Palette.textTertiary)
                .frame(width: 18, height: 18)
                .expandedHitArea(5)
        }
        .buttonStyle(.pressable(scale: 0.85))
        .onHover { expandHovering = $0 }
        .help("Notizen groß öffnen")
        .accessibilityLabel("Notizen groß öffnen")
    }

    private var box: some View {
        GeometryReader { geometry in
            Group {
                if model.isEditingNotes {
                    editor
                } else {
                    display(size: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .padding(Metrics.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(
                    model.isEditingNotes ? Palette.borderStrong : Palette.border,
                    lineWidth: 1
                )
        )
        .animation(Motion.snappy(reduced: reduceMotion), value: model.isEditingNotes)
    }

    // MARK: Schreiben

    private var editor: some View {
        TextEditor(text: Binding(
            get: { store.state.notes },
            set: { store.setNotes($0) }
        ))
        .font(Typo.caption)
        .foregroundStyle(Palette.textPrimary)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        .focused($editorFocused)
        .onAppear { editorFocused = true }
        .onChange(of: editorFocused) { _, focused in
            // Klick woanders hin beendet das Schreiben - das Feld gibt die
            // Tastatur wieder frei.
            if !focused { model.isEditingNotes = false }
        }
        .onExitCommand { model.isEditingNotes = false }
    }

    // MARK: Lesen

    /// Ruhezustand: nur Text, kein Eingabefeld, kein Rollbalken. Was nicht
    /// hineinpasst, laeuft unten aus.
    private func display(size: CGSize) -> some View {
        let overflows = textHeight > size.height + 1

        return Text(notes.isEmpty ? "Was noch anliegt …" : notes)
            .font(Typo.caption)
            .foregroundStyle(notes.isEmpty ? Palette.textTertiary : Palette.textPrimary)
            // Gleicher Einzug wie im Eingabefeld - sonst springt der Text beim
            // Wechsel um ein paar Punkte zur Seite.
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { text in
                    Color.clear.preference(key: TextHeightKey.self, value: text.size.height)
                }
            )
            // Ein fester Rahmen, kein flexibler: Ein Rahmen mit unbegrenzter
            // Hoehe waechst mit einem laengeren Text mit, und dann schneidet
            // `clipped` nichts ab - der Text liefe ueber die Flaeche hinaus.
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .overlay(alignment: .bottom) {
                if overflows { fadeOut }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.isEditingNotes = true }
            .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Zum Bearbeiten klicken")
    }

    /// Weicher Auslauf mit dem Weg zum Rest.
    private var fadeOut: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Palette.surface.opacity(0), Palette.surface],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)
            .allowsHitTesting(false)

            Button {
                model.showsNotes = true
            } label: {
                Text("mehr")
                    .font(Typo.chip)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.spacing6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.surfaceRaised))
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable(scale: 0.92))
            .help("Alle Notizen zeigen")
        }
    }

    private struct TextHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

// MARK: - Notizen in gross

/// Alle Notizen auf einmal, zum Lesen und Schreiben.
///
/// Derselbe Text wie in der Seitenspalte - nicht eine Kopie, die beim
/// Schliessen zurueckgeschrieben wird. Jeder Tastendruck landet sofort im
/// Bestand, so kann beim Schliessen nichts verloren gehen.
struct NotesSheet: View {
    @Bindable var model: AppModel

    @Environment(\.closePanel) private var dismiss
    @FocusState private var focused: Bool

    private var store: StateStore { model.store }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.spacing12) {
                Text("Notizen")
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.textPrimary)

                Spacer()

                Text(summary)
                    .font(Typo.chip)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)

                Button("Fertig") { dismiss() }
                    .buttonStyle(.pressable)
                    .font(Typo.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
                    .expandedHitArea(6)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Metrics.spacing20)
            .frame(height: 52)

            Divider().overlay(Palette.border)

            TextEditor(text: Binding(
                get: { store.state.notes },
                set: { store.setNotes($0) }
            ))
            .font(Typo.body)
            .foregroundStyle(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .focused($focused)
            .padding(.horizontal, Metrics.spacing16)
            .padding(.vertical, Metrics.spacing12)
        }
        .frame(maxWidth: 620, maxHeight: 560)
        .background(Palette.surface)
        .onAppear { focused = true }
        .onDisappear { store.flush() }
    }

    private var summary: String {
        let lines = store.state.notes
            .split(separator: "\n", omittingEmptySubsequences: true)
            .count
        return lines == 1 ? "1 Zeile" : "\(lines) Zeilen"
    }
}
