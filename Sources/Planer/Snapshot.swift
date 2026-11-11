import AppKit
import PlanerCore
import PlanerData
import SwiftUI

/// Rendert Ansichten der App in echte Fenster und schreibt sie als PNG.
///
/// Zweck: visuelle Kontrolle waehrend der Entwicklung, ohne dass der
/// aufrufende Prozess die Berechtigung zur Bildschirmaufnahme braucht.
/// Eine App darf ihr eigenes Fenster jederzeit abziehen.
///
/// Aufruf: `Planer --snapshot <zielordner> [--size BxH]`
@MainActor
enum SnapshotRunner {

    struct Variant {
        let name: String
        let appearance: NSAppearance.Name
    }

    static func run(arguments: [String]) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let directory = URL(fileURLWithPath: value(for: "--snapshot", in: arguments) ?? "./snapshots")
        let size = parseSize(value(for: "--size", in: arguments)) ?? CGSize(width: 1100, height: 720)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Die App laeuft ausschliesslich im Dunkelmodus - eine helle Fassung
        // abzuziehen, die es nicht gibt, waere irrefuehrend.
        let variants = [Variant(name: "dunkel", appearance: .darkAqua)]

        let view = value(for: "--view", in: arguments) ?? "app"

        for variant in variants {
            let url = directory.appendingPathComponent("\(variant.name).png")
            switch view {
            case "woche":
                let model = AppModel(store: SampleData.store())
                model.viewMode = .week
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "datum":
                capture(
                    DatePickerPreview(),
                    size: CGSize(width: 300, height: 340),
                    appearance: variant.appearance,
                    to: url
                )
            case "einstellungen":
                capture(
                    SettingsView(store: SampleData.store()),
                    size: CGSize(width: 440, height: 420),
                    appearance: variant.appearance,
                    to: url
                )
            case "menue":
                let model = AppModel(store: SampleData.store())
                capture(
                    MenuBarPanel(model: model),
                    size: CGSize(width: 280, height: 420),
                    appearance: variant.appearance,
                    to: url
                )
            case "symbol":
                capture(
                    MenuBarIconPreview(),
                    size: CGSize(width: 560, height: 180),
                    appearance: variant.appearance,
                    to: url
                )
            case "monat":
                let model = AppModel(store: SampleData.store())
                capture(
                    MonthOverview(model: model),
                    size: CGSize(width: 980, height: 660),
                    appearance: variant.appearance,
                    to: url
                )
            case "urlaub":
                let model = AppModel(store: SampleData.store())
                model.store.startVacation()
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "neu":
                let model = AppModel(store: SampleData.store())
                capture(
                    EditorSheet(model: model, target: .newHabit),
                    size: CGSize(width: 420, height: 320),
                    appearance: variant.appearance,
                    to: url
                )
            case "aufgabe":
                let model = AppModel(store: SampleData.store())
                let task = model.store.state.tasks[1]
                capture(
                    EditorSheet(model: model, target: .task(task)),
                    size: CGSize(width: 420, height: 440),
                    appearance: variant.appearance,
                    to: url
                )
            case "blatt":
                // Das Bearbeiten-Blatt fuer sich - im Fenster liegt es sonst
                // ueber der Ansicht und laesst sich schlecht beurteilen.
                let model = AppModel(store: SampleData.store())
                let event = model.store.state.events[0]
                capture(
                    EditorSheet(model: model, target: .event(event)),
                    size: CGSize(width: 420, height: 560),
                    appearance: variant.appearance,
                    to: url
                )
            case "stundenplan":
                let model = AppModel(store: SampleData.store())
                model.viewMode = .timetable
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "kurs":
                let model = AppModel(store: SampleData.store())
                let course = model.store.state.courses[0]
                capture(
                    CourseEditor(model: model, target: .course(course)),
                    size: CGSize(width: 440, height: 560),
                    appearance: variant.appearance,
                    to: url
                )
            case "kurs-neu":
                let model = AppModel(store: SampleData.store())
                capture(
                    CourseEditor(model: model, target: .newCourse(weekday: 2, start: ClockTime(hour: 14))),
                    size: CGSize(width: 440, height: 560),
                    appearance: variant.appearance,
                    to: url
                )
            case "belegung":
                // Das Terminblatt mit Stundenplan im Hintergrund - hier zeigt
                // sich, ob die Zeit frei ist.
                let model = AppModel(store: SampleData.store())
                let monday = DateKey.today.startOfWeek
                capture(
                    EditorSheet(model: model, target: .newEvent(monday)),
                    size: CGSize(width: 420, height: 700),
                    appearance: variant.appearance,
                    to: url
                )
            case "uni-tag":
                let model = AppModel(store: SampleData.store())
                model.selectedDate = DateKey.today.startOfWeek
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "seite":
                // Nur die Seitenspalte, in genau der Hoehe, die sie im
                // kleinsten Fenster bekommt.
                // Mit langen Notizen - genau der Fall, der ueberlaufen koennte.
                var state = StateStore().state
                state.notes = (1...30).map { "Notiz Zeile \($0)" }.joined(separator: "\n")
                let model = AppModel(store: StateStore(inMemory: state))
                let height = size.height
                capture(SidebarView(model: model).frame(height: height).background(Color.black),
                        size: CGSize(width: Metrics.sidebarWidth, height: height),
                        appearance: variant.appearance, to: url)
            case "text":
                // „Aus Text anlegen" mit einem Beispiel - und, wenn vorhanden,
                // mit der Antwort des Sprachmodells.
                let model = AppModel(store: StateStore(inMemory: StateStore().state))
                model.captureText = value(for: "--text", in: arguments)
                    ?? "Hallo Kim, die Klausur in Statistik findet am 12.2. von 10:15 "
                    + "bis 11:45 in Raum 204 statt. Bitte melde dich bis Freitag dafür an.\nViele Grüße"
                model.showsCapture = true
                capture(DashboardView(model: model), size: size, appearance: variant.appearance,
                        to: url, wait: 7)
            case "text-beispiel":
                // Fuer die Projektseite: ausschliesslich Beispieldaten.
                let model = AppModel(store: SampleData.store())
                model.captureText = "Hallo Kim, die Klausur in Statistik findet am 12.2. von 10:15 "
                    + "bis 11:45 in Raum 204 statt. Bitte melde dich bis Freitag dafür an.\nViele Grüße"
                model.showsCapture = true
                capture(DashboardView(model: model), size: size, appearance: variant.appearance,
                        to: url, wait: 7)
            case "text-leer":
                let model = AppModel(store: StateStore(inMemory: StateStore().state))
                model.showsCapture = true
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "ebene":
                let model = AppModel(store: StateStore())
                model.showsUpcoming = true
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "ebene-blatt":
                let model = AppModel(store: StateStore())
                model.showsUpcoming = true
                if let event = model.store.allUpcomingEvents().first?.event {
                    model.edit(event: event)
                }
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "ebene-monat":
                let model = AppModel(store: StateStore())
                model.showsMonthOverview = true
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "echt-termine":
                let model = AppModel(store: StateStore())
                capture(UpcomingOverview(model: model), size: CGSize(width: 640, height: 600),
                        appearance: variant.appearance, to: url)
            case "echt-notizen":
                let model = AppModel(store: StateStore())
                capture(NotesSheet(model: model), size: CGSize(width: 620, height: 560),
                        appearance: variant.appearance, to: url)
            case "echt-stundenplan":
                let model = AppModel(store: StateStore())
                model.viewMode = .timetable
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "echt-woche":
                let model = AppModel(store: StateStore())
                model.viewMode = .week
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "echt-monat":
                let model = AppModel(store: StateStore())
                capture(MonthOverview(model: model), size: CGSize(width: 980, height: 660),
                        appearance: variant.appearance, to: url)
            case "echt":
                // Mit dem tatsaechlichen Bestand, nicht mit Beispieldaten.
                let model = AppModel(store: StateStore())
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            case "leer":
                // Der Zustand, in dem die App beim allerersten Start steht.
                let model = AppModel(store: StateStore(inMemory: DashboardState()))
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            default:
                let model = AppModel(store: SampleData.store())
                capture(DashboardView(model: model), size: size, appearance: variant.appearance, to: url)
            }
            print("Snapshot: \(url.path)")
        }

        exit(0)
    }

    // MARK: - Aufnahme

    static func capture(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL,
                        wait: TimeInterval = 1.0) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.setFrame(NSRect(origin: .zero, size: size), display: true)

        // SwiftUI braucht einen Durchlauf der Runloop, bis Layout und
        // asynchrone Effekte stehen - sonst faengt man ein leeres Fenster ein.
        window.orderFrontRegardless()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(wait))

        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }

    // MARK: - Argumente

    static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        let next = arguments[index + 1]
        return next.hasPrefix("--") ? nil : next
    }

    static func parseSize(_ raw: String?) -> CGSize? {
        guard let parts = raw?.split(separator: "x"), parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]) else { return nil }
        return CGSize(width: width, height: height)
    }
}
