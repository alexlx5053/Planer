import PlanerCore
import SwiftUI

// MARK: - Schliessen

/// Wie eine Ansicht sich selbst schliesst.
///
/// Ersetzt `dismiss` aus SwiftUI: Das funktioniert nur in echten Blaettern,
/// und die gibt es hier nicht mehr. Der Name an der Aufrufstelle bleibt
/// `dismiss()` - fuer die Ansicht aendert sich nichts.
struct ClosePanelAction: Sendable {
    let action: @MainActor @Sendable () -> Void
    @MainActor func callAsFunction() { action() }
}

private struct ClosePanelKey: EnvironmentKey {
    static let defaultValue = ClosePanelAction {}
}

extension EnvironmentValues {
    var closePanel: ClosePanelAction {
        get { self[ClosePanelKey.self] }
        set { self[ClosePanelKey.self] = newValue }
    }
}

// MARK: - Ebenen ueber dem Fenster

/// Zeigt Monatsuebersicht, Terminliste, Notizen und die Bearbeiten-Blaetter
/// als Ebene ueber dem Fenster.
///
/// **Warum keine Blaetter von macOS:** Ein Blatt laesst sich nur ueber seine
/// Knoepfe schliessen. Hier genuegt ein Klick daneben - so, wie man es von
/// Menues und Popovers kennt. Das Fenster dahinter wird abgedunkelt, damit klar
/// ist, dass ein Klick dorthin die Ansicht schliesst und nicht etwas im Fenster
/// ausloest.
///
/// **Was beim Klick daneben passiert:**
/// - Uebersichten und Notizen schliessen sofort. Notizen speichern ohnehin bei
///   jedem Tastendruck, es kann nichts verloren gehen.
/// - Ein Bearbeiten-Blatt uebernimmt, was geaendert wurde - wie ein Termin im
///   Kalender von Apple. Wer etwas verwerfen will, nimmt „Abbrechen". Fehlt
///   der Titel, bleibt das Blatt offen, statt das Geschriebene wegzuwerfen.
///
/// Zwei Ebenen koennen uebereinander liegen: Aus der Terminliste heraus oeffnet
/// sich das Bearbeiten-Blatt darueber. Ein Klick daneben schliesst dann nur
/// das obere.
struct PanelHost: View {
    @Bindable var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Base: Equatable { case month, upcoming, notes, capture }

    private var base: Base? {
        if model.showsMonthOverview { return .month }
        if model.showsUpcoming { return .upcoming }
        if model.showsNotes { return .notes }
        if model.showsCapture { return .capture }
        return nil
    }

    var body: some View {
        ZStack {
            if let base {
                layer(
                    isTop: model.editorTarget == nil,
                    dim: 0.55,
                    onOutside: { close(base) }
                ) {
                    baseContent(base)
                }
            }

            if let target = model.editorTarget {
                layer(
                    isTop: true,
                    // Liegt schon eine Ebene darunter, ist das Fenster bereits
                    // abgedunkelt - eine zweite volle Abdunklung wuerde schwarz.
                    dim: base == nil ? 0.55 : 0.3,
                    onOutside: { model.editorCloseRequest += 1 }
                ) {
                    editorContent(target)
                }
                .id(target.id)
            }
        }
        .animation(Motion.snappy(reduced: reduceMotion), value: base)
        .animation(Motion.snappy(reduced: reduceMotion), value: model.editorTarget?.id)
    }

    // MARK: - Inhalt

    @ViewBuilder
    private func baseContent(_ base: Base) -> some View {
        switch base {
        case .month:
            MonthOverview(model: model)
                .environment(\.closePanel, ClosePanelAction { model.showsMonthOverview = false })
        case .upcoming:
            UpcomingOverview(model: model)
                .environment(\.closePanel, ClosePanelAction { model.showsUpcoming = false })
        case .notes:
            NotesSheet(model: model)
                .environment(\.closePanel, ClosePanelAction { model.showsNotes = false })
        case .capture:
            CapturePanel(model: model)
                .environment(\.closePanel, ClosePanelAction { model.showsCapture = false })
        }
    }

    @ViewBuilder
    private func editorContent(_ target: EditorTarget) -> some View {
        let close = ClosePanelAction { model.editorTarget = nil }
        if target.isCourse {
            CourseEditor(model: model, target: target)
                .environment(\.closePanel, close)
        } else {
            EditorSheet(model: model, target: target)
                .environment(\.closePanel, close)
        }
    }

    private func close(_ base: Base) {
        switch base {
        case .month: model.showsMonthOverview = false
        case .upcoming: model.showsUpcoming = false
        case .notes:
            model.store.flush()
            model.showsNotes = false
        case .capture:
            // Der eingefuegte Text bleibt im Modell stehen - wer versehentlich
            // daneben klickt, findet ihn beim Wiederoeffnen vor.
            model.showsCapture = false
        }
    }

    // MARK: - Ebene

    private func layer<Content: View>(
        isTop: Bool,
        dim: Double,
        onOutside: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color.black.opacity(dim)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onOutside)
                .accessibilityLabel("Schließen")
                .accessibilityAddTraits(.isButton)
                .transition(.opacity)

            content()
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.borderStrong, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.7), radius: 30, y: 10)
                // Ein Klick auf die Ansicht selbst erreicht die Flaeche dahinter
                // nicht: Sie liegt neben der Ansicht, nicht um sie herum. Nur
                // der Rand von 24 Punkten gehoert schon zum Draussen.
                .padding(Metrics.spacing24)
                // Nur die oberste Ebene ist bedienbar. Sonst loeste Escape die
                // Knoepfe beider Ebenen zugleich aus.
                .disabled(!isTop)
                .transition(
                    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
                )
        }
    }
}
