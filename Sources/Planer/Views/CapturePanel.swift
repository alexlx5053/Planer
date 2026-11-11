import AppKit
import PlanerCore
import PlanerData
import SwiftUI

/// Aus eingefuegtem Text werden Termine und Aufgaben.
///
/// Der Ablauf hat drei Stufen, und jede ist sichtbar:
///
/// 1. **Sofort** lesen feste Regeln den Text - Datum, Uhrzeit, Dauer. Das
///    Ergebnis steht da, bevor man die Hand von der Tastatur genommen hat.
/// 2. **Kurz darauf** benennt das Sprachmodell des Macs die Eintraege besser
///    und zerlegt Fliesstext. Es laeuft auf dem Geraet; nichts verlaesst den
///    Rechner, nichts kostet etwas.
/// 3. **Angelegt** wird erst nach einem Klick. Bis dahin sind es Entwuerfe -
///    jeder laesst sich abwaehlen, umbenennen, umdatieren, vom Termin zur
///    Aufgabe machen.
///
/// Dass nichts von selbst im Bestand landet, ist Absicht: Ein Leser, der aus
/// fremdem Text Eintraege macht, irrt sich gelegentlich, und ein falscher
/// Termin im Kalender ist schlimmer als ein Klick mehr.
struct CapturePanel: View {
    @Bindable var model: AppModel

    @Environment(\.closePanel) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var textFocused: Bool

    @State private var drafts: [EntryDraft] = []
    /// Arbeitet das Sprachmodell gerade?
    @State private var isThinking = false
    /// Hat das Sprachmodell zu diesem Stand beigetragen?
    @State private var usedModel = false
    /// Laufende Anfrage - wird verworfen, sobald sich der Text aendert.
    @State private var analysis: Task<Void, Never>?

    private var store: StateStore { model.store }
    private var selectedCount: Int { drafts.filter(\.isIncluded).count }
    private var hasText: Bool {
        !model.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)

            VStack(alignment: .leading, spacing: Metrics.spacing12) {
                input
                status

                if drafts.isEmpty {
                    if !hasText { examples }
                } else {
                    draftList
                }
            }
            .padding(Metrics.spacing20)

            Divider().overlay(Palette.border)
            footer
        }
        .background(Palette.surface)
        .frame(maxWidth: 600)
        // So hoch wie der Inhalt. Erst mit vielen Entwuerfen - wenn die Liste
        // scrollt - nimmt die Ansicht die volle Hoehe. Ein Rahmen mit fester
        // Hoechsthoehe wuerde sich immer bis dorthin strecken und den Inhalt
        // in seine Mitte setzen: oben und unten bliebe Leere.
        .frame(maxHeight: drafts.count > 4 ? 640 : nil)
        .fixedSize(horizontal: false, vertical: drafts.count <= 4)
        .onAppear {
            textFocused = true
            if hasText { analyze() }
        }
        .onChange(of: model.captureText) { _, _ in analyze() }
        .onDisappear { analysis?.cancel() }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: Metrics.spacing8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textSecondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Aus Text anlegen")
                    .font(Typo.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Text("Mail, Nachricht oder Liste einfügen – daraus werden Termine und Aufgaben.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.spacing20)
        .frame(height: 58)
    }

    // MARK: - Eingabe

    private var input: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.captureText)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($textFocused)

            if model.captureText.isEmpty {
                Text("Text hier einfügen oder schreiben …")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textTertiary)
                    // Deckungsgleich mit dem Schreibcursor des Feldes.
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(Metrics.spacing8)
        .frame(height: drafts.isEmpty ? 150 : 110)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(Palette.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(textFocused ? Palette.borderStrong : Palette.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if model.captureText.isEmpty { pasteButton }
        }
        .animation(Motion.smooth(reduced: reduceMotion), value: drafts.isEmpty)
    }

    /// Ein ausdruecklicher Knopf statt stillschweigendem Einfuegen: Was in der
    /// Zwischenablage liegt, geht die App erst etwas an, wenn man es ihr gibt.
    private var pasteButton: some View {
        Button {
            if let text = NSPasteboard.general.string(forType: .string) {
                model.captureText = text
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 10))
                Text("Einfügen").font(Typo.chip)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Metrics.spacing8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                    .fill(Palette.surfaceRaised)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.94))
        .padding(Metrics.spacing8)
        .help("Zwischenablage einfügen (⌘V)")
    }

    // MARK: - Stand

    /// Sagt, wer gelesen hat. Das gehoert dazu: Man soll wissen, ob das
    /// Ergebnis von festen Regeln stammt oder ob ein Sprachmodell mitgewirkt
    /// hat - und dass es in beiden Faellen auf dem eigenen Mac geschah.
    @ViewBuilder
    private var status: some View {
        if hasText {
            HStack(spacing: Metrics.spacing6) {
                if isThinking {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Apple Intelligence liest mit …")
                } else if usedModel {
                    Image(systemName: "sparkles").font(.system(size: 9))
                    Text("Mit Apple Intelligence gelesen · auf diesem Mac")
                } else {
                    Image(systemName: "text.magnifyingglass").font(.system(size: 9))
                    Text(SmartCapture.isAvailable ? "Gelesen" : "Mit festen Regeln gelesen · auf diesem Mac")
                }

                Spacer()

                if !drafts.isEmpty {
                    Text(drafts.count == 1 ? "1 erkannt" : "\(drafts.count) erkannt")
                        .monospacedDigit()
                }
            }
            .font(Typo.chip)
            .foregroundStyle(Palette.textTertiary)
            .frame(height: 14)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing6) {
            SectionHeader(title: "Zum Beispiel")
            ForEach(Self.exampleTexts, id: \.self) { example in
                Button {
                    model.captureText = example
                } label: {
                    Text(example)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.spacing8)
                        .padding(.vertical, Metrics.spacing6)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                                .fill(Palette.surfaceRaised.opacity(0.6))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable(scale: 0.98))
            }
        }
        .padding(.top, Metrics.spacing4)
    }

    private static let exampleTexts = [
        "Zahnarzt am 12.11. um 14:30",
        "Hausarbeit abgeben bis Freitag",
        "Die Klausur findet am 12.2. von 10:15 bis 11:45 in Raum 204 statt. Bitte melde dich bis Freitag an.",
    ]

    // MARK: - Entwuerfe

    /// Wenige Entwuerfe stehen einfach untereinander, und die Ansicht ist so
    /// hoch wie ihr Inhalt. Erst wenn es viele sind, wird gescrollt - sonst
    /// haengt unter zwei Zeilen ein halbes Fenster Leere.
    @ViewBuilder
    private var draftList: some View {
        if drafts.count > 4 {
            ScrollView { draftRows }
                .scrollIndicators(.never)
                .frame(maxHeight: .infinity)
        } else {
            draftRows
        }
    }

    private var draftRows: some View {
        VStack(spacing: Metrics.spacing6) {
            ForEach($drafts) { $draft in
                DraftRow(
                    draft: $draft,
                    conflict: conflict(for: draft)
                )
            }
        }
        .animation(Motion.smooth(reduced: reduceMotion), value: drafts.map(\.id))
    }

    /// Beisst sich ein Termin mit dem Stundenplan oder einem anderen Termin?
    private func conflict(for draft: EntryDraft) -> String? {
        guard draft.isIncluded, let span = draft.span,
              let first = store.conflicts(with: span, on: draft.date).first
        else { return nil }
        return "überschneidet \(first.title) (\(first.span.text))"
    }

    // MARK: - Fusszeile

    private var footer: some View {
        HStack(spacing: Metrics.spacing8) {
            if hasText {
                Button("Leeren") {
                    model.captureText = ""
                    textFocused = true
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Abbrechen") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button(createLabel) { model.create(from: drafts) }
                .buttonStyle(.borderedProminent)
                // ⌘↩ statt ↩: Der Zeilenschalter gehoert im Textfeld dem Text.
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedCount == 0)
                .help("Anlegen (⌘↩)")
        }
        .padding(Metrics.spacing16)
    }

    private var createLabel: String {
        switch selectedCount {
        case 0: "Anlegen"
        case 1: "1 Eintrag anlegen"
        default: "\(selectedCount) Einträge anlegen"
        }
    }

    // MARK: - Lesen

    /// Liest den Text neu: sofort mit den Regeln, dann - wenn vorhanden - mit
    /// dem Sprachmodell.
    private func analyze() {
        analysis?.cancel()
        let text = model.captureText
        let today = store.today

        let local = QuickParser.drafts(from: text, today: today)
        drafts = local
        usedModel = false

        guard SmartCapture.isAvailable,
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        else {
            isThinking = false
            return
        }

        isThinking = true
        analysis = Task {
            // Kurz warten: Beim Tippen soll nicht jeder Buchstabe eine Anfrage
            // ausloesen.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            let suggestions = await SmartCapture.suggestions(for: text)

            // Hat sich der Text inzwischen geaendert, gehoert die Antwort zu
            // einem Stand, den es nicht mehr gibt.
            guard !Task.isCancelled, model.captureText == text else { return }
            isThinking = false

            guard let suggestions, !suggestions.isEmpty else { return }
            let refined = QuickParser.refine(local: local, with: suggestions, text: text, today: today)

            // Nur uebernehmen, wenn an den Entwuerfen noch nichts von Hand
            // geaendert wurde - sonst ueberschriebe die Antwort die Korrektur.
            guard drafts == local else { return }
            if refined != local {
                drafts = refined
            }
            usedModel = true
        }
    }
}

// MARK: - Ein Entwurf

private struct DraftRow: View {
    @Binding var draft: EntryDraft
    let conflict: String?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.spacing8) {
            CheckToggle(
                isOn: draft.isIncluded,
                shape: draft.kind == .event ? .round : .square,
                label: "\(draft.title) anlegen"
            ) {
                draft.isIncluded.toggle()
            }
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: Metrics.spacing4) {
                HStack(spacing: Metrics.spacing8) {
                    TextField("Titel", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(Typo.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)

                    kindButton
                }

                HStack(spacing: Metrics.spacing8) {
                    DateField(date: $draft.date)

                    if draft.kind == .event {
                        Text(timeText)
                            .font(Typo.chip)
                            .monospacedDigit()
                            .foregroundStyle(draft.time == nil ? Palette.textTertiary : Palette.textSecondary)
                    }

                    Spacer(minLength: 0)

                    // Stand kein Datum im Text, ist „heute" nur die Annahme -
                    // das soll man sehen, bevor man anlegt.
                    if !draft.hasExplicitDate {
                        Text("kein Datum im Text")
                            .font(Typo.chip)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                if let conflict {
                    Label(conflict, systemImage: "exclamationmark.triangle")
                        .font(Typo.chip)
                        .foregroundStyle(Palette.urgent)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Metrics.spacing12)
        .padding(.vertical, Metrics.spacing8)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(Palette.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
        .opacity(draft.isIncluded ? 1 : 0.45)
    }

    /// Schaltet zwischen Termin und Aufgabe um. Ein Knopf statt eines Menues:
    /// Es gibt genau zwei Moeglichkeiten, und die andere ist immer einen Klick
    /// entfernt.
    private var kindButton: some View {
        Button {
            draft.kind = draft.kind == .event ? .task : .event
        } label: {
            HStack(spacing: 3) {
                Image(systemName: draft.kind == .event ? "calendar" : "checklist")
                    .font(.system(size: 9))
                Text(draft.kind.label)
                    .font(Typo.chip)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Metrics.spacing6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                    .fill(Palette.surfaceRaised)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.92))
        .help(draft.kind == .event ? "Als Aufgabe anlegen" : "Als Termin anlegen")
    }

    private var timeText: String {
        guard draft.time != nil else { return "ganztägig" }
        if draft.durationMinutes != nil, let span = draft.span { return span.text }
        return draft.time?.text ?? ""
    }
}
