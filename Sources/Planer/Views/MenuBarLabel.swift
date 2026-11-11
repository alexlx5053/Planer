import PlanerData
import SwiftUI

/// Der Ring in der Menueleiste.
///
/// Als eigene Ansicht, weil sie zwei Aufgaben hat: das Symbol zeichnen und - da
/// sie im Gegensatz zum Fenster immer lebt - die Bitte aufnehmen, das Fenster
/// zurueckzuholen.
struct MenuBarLabel: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let stats = model.store.stats(for: model.store.today)

        Image(nsImage: MenuBarIcon.image(fraction: stats.fraction, isPerfect: stats.isPerfect))
            .onReceive(NotificationCenter.default.publisher(for: PlanerApp.reopenRequest)) { _ in
                openWindow(id: PlanerApp.mainWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
