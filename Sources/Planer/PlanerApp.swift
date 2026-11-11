import AppKit
import PlanerCore
import ServiceManagement
import PlanerData
import SwiftUI
import UniformTypeIdentifiers

/// Faengt das Beenden der App ab.
///
/// `onDisappear` am Fenster feuert bei ⌘Q nicht zuverlaessig - ohne diesen
/// Umweg gingen die letzten 250 ms an Aenderungen verloren.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }

    /// Das Fenster zu schliessen beendet die App nicht.
    ///
    /// Sonst verschwaende mit dem Fenster auch der Ring aus der Menueleiste -
    /// und genau der soll da sein, wenn kein Fenster offen ist. Beendet wird mit
    /// ⌘Q, wie bei jeder anderen App mit Menueleisten-Symbol.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Klick aufs Dock-Symbol holt das Fenster zurueck.
    ///
    /// Hier gibt es keinen SwiftUI-Zusammenhang, aus dem heraus sich ein Fenster
    /// oeffnen liesse - deshalb der Umweg ueber eine Nachricht, die die Szene
    /// aufnimmt.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NotificationCenter.default.post(name: PlanerApp.reopenRequest, object: nil)
        }
        return true
    }
}

struct PlanerApp: App {
    static let mainWindowID = "planer-hauptfenster"
    /// Wird geschickt, wenn das Fenster zurueckgeholt werden soll - etwa beim
    /// Klick aufs Dock-Symbol, wo kein SwiftUI-Zusammenhang zur Verfuegung steht.
    static let reopenRequest = Notification.Name("io.github.alexlx5053.planer.fensterOeffnen")

    @State private var model: AppModel
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle

    /// Nachfuehren der Uhr. Halbminuetlich genuegt - die Anzeige kennt keine
    /// Sekunden, und ein Sekundentakt kostete nur Strom.
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init() {
        _model = State(initialValue: AppModel(store: StateStore()))
    }

    var body: some Scene {
        // Ein benanntes Einzelfenster statt einer Fenstergruppe.
        //
        // Eine Gruppe verwirft ihr Fenster beim Schliessen restlos - danach gibt
        // es nichts mehr, was man zurueckholen koennte, und die App laeuft
        // unerreichbar weiter. Ein benanntes Fenster laesst sich jederzeit
        // wieder oeffnen, und macOS traegt es von selbst ins Fenster-Menue ein.
        Window("Planer", id: Self.mainWindowID) {
            DashboardView(model: model)
                .frame(minWidth: Metrics.minWindowWidth, minHeight: Metrics.minWindowHeight)
                .preferredColorScheme(.dark)
                .onReceive(tick) { model.tick($0) }
                .onDisappear { model.store.flush() }
                .onAppear { lifecycle.onTerminate = { model.store.flush() } }
        }
        .defaultSize(width: 1160, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { menuCommands }

        // Der Ring in der Menueleiste.
        //
        // Er zeigt den Tagesfortschritt, ohne dass ein Fenster offen sein muss -
        // auf dem Mac der zuverlaessigere Platz als der Schreibtisch, den man
        // unter Fenstern ohnehin selten sieht.
        MenuBarExtra {
            MenuBarPanel(model: model)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: model.store)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Menueleiste
    //
    // Auf dem Mac gehoeren Befehle ins Menue, nicht nur auf eine Taste: Nur so
    // sind sie auffindbar, und nur so zeigt das System die Kuerzel an.

    @CommandsBuilder
    private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                Button("Neuer Termin") { model.newEntry(kind: .event) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Neue Aufgabe") { model.newEntry(kind: .task) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Neue Gewohnheit") { model.newEntry(kind: .habit) }
                    .keyboardShortcut("n", modifiers: [.command, .control])
                Button("Neuer Kurs") { model.newEntry(kind: .course) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Aus Text anlegen …") { model.openCapture() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            .disabled(model.isPresentingSheet)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Löschen widerrufen") { model.undoDeletion() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.pendingUndo == nil)
        }

        CommandGroup(after: .toolbar) {
            // Einzelne Knoepfe statt einer Auswahl: Nur so bekommt jede
            // Ansicht ihr Kuerzel, und das System zeigt es im Menue an. Welche
            // gerade gilt, steht ohnehin im Kopf des Fensters.
            Button("Tag") { model.viewMode = .day }
                .keyboardShortcut("1", modifiers: .command)
            Button("Woche") { model.viewMode = .week }
                .keyboardShortcut("2", modifiers: .command)
            Button("Stundenplan") { model.viewMode = .timetable }
                .keyboardShortcut("3", modifiers: .command)
            Button("Monatsübersicht") { model.showsMonthOverview = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model.isPresentingSheet)
            Button("Alle Termine") { model.showsUpcoming = true }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.isPresentingSheet)
            Button("Notizen") {
                model.isEditingNotes = false
                model.showsNotes = true
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .disabled(model.isPresentingSheet)
            Button(model.isSearchFieldVisible ? "Suche schließen" : "Suchen") { model.toggleSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
        }

        // Ein ausdruecklicher Weg zurueck ins Fenster, im Menue auffindbar.
        CommandGroup(after: .windowList) {
            Button("Planer-Fenster") {
                NotificationCenter.default.post(name: PlanerApp.reopenRequest, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Tag") {
            Button("Heute") { model.goToToday() }
                .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button(model.viewMode.showsWholeWeek ? "Vorherige Woche" : "Vorheriger Tag") {
                model.step(days: -1)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button(model.viewMode.showsWholeWeek ? "Nächste Woche" : "Nächster Tag") {
                model.step(days: 1)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Vorheriger Monat") { model.stepMonth(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Nächster Monat") { model.stepMonth(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

            Divider()

            Button(model.isOnVacation ? "Urlaub beenden" : "Urlaub beginnen") {
                model.toggleVacation()
            }
        }
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    let store: StateStore

    @State private var message: String?
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    /// Der wahre Zustand steht beim System, nicht in unserer Datei - deshalb
    /// wird er dort gelesen und geschrieben statt gespiegelt.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { wanted in
                do {
                    if wanted {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchesAtLogin = SMAppService.mainApp.status == .enabled
                } catch {
                    message = "Konnte den Starteintrag nicht ändern: \(error.localizedDescription)"
                    launchesAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing16) {
            VStack(alignment: .leading, spacing: Metrics.spacing6) {
                SectionHeader(title: "Daten")
                Text(store.storageDirectory.path)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Alles bleibt auf diesem Mac. Beim Start wird eine Tagessicherung angelegt, 14 Stände werden aufbewahrt.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Palette.border)

            VStack(alignment: .leading, spacing: Metrics.spacing6) {
                SectionHeader(title: "Start")

                Toggle("Beim Anmelden starten", isOn: launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textPrimary)

                Text("Damit ist der Ring in der Menüleiste nach jedem Neustart wieder da, ohne dass du die App öffnen musst.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Palette.border)

            HStack(spacing: Metrics.spacing8) {
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.storageDirectory])
                }
                Button("Sichern …") { exportData() }
                Button("Zurückspielen …") { importData() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let message {
                Text(message)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.spacing20)
        .frame(width: 420, alignment: .leading)
        .background(Palette.surface)
    }

    // MARK: - Sichern

    private func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Planer \(DateKey.today.rawValue).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            store.flush()
            try store.export(to: url)
            message = "Gesichert nach \(url.lastPathComponent)."
        } catch {
            message = "Sichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Zurueckspielen ersetzt den gesamten Bestand - deshalb wird vorher
    /// nachgefragt, obwohl die App sonst ohne Bestaetigungsdialoge auskommt.
    /// Hier gibt es kein Rueckgaengig, das den Verlust auffangen wuerde.
    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Bestand ersetzen?"
        alert.informativeText = "Alle Einträge werden durch den Inhalt der Datei ersetzt. "
            + "Der bisherige Stand wird vorher als Sicherung abgelegt."
        alert.addButton(withTitle: "Zurückspielen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try store.importFrom(url)
            message = "Zurückgespielt aus \(url.lastPathComponent)."
        } catch let error as StateStore.ImportError {
            // Diese Meldungen sind schon vollstaendige Saetze - und nicht jede
            // bedeutet, dass die Datei unlesbar war.
            message = error.localizedDescription
        } catch {
            message = "Die Datei ließ sich nicht lesen: \(error.localizedDescription)"
        }
    }
}
